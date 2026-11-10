#Requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Get-Content (Join-Path $PSScriptRoot 'local-payment-test-state.ps1') -Raw
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
foreach($name in @('Get-Snapshot','Restore-Snapshot')){
    $node=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name-eq$name},$true)
    Invoke-Expression $node.Extent.Text
}
$shared='OrderProcessingSystem_Dev';$script:route='OpenPay';$script:rzFlag=$false;$script:calls=@()
function Table($rows){
    $table=[Data.DataTable]::new()
    foreach($key in $rows[0].Keys){[void]$table.Columns.Add($key,[object])}
    foreach($item in $rows){$row=$table.NewRow();foreach($key in $item.Keys){$row[$key]=$item[$key]};$table.Rows.Add($row)}
    return ,$table
}
function Invoke-Database($database,$sql,$parameters=@{}){
    $script:calls+=@{database=$database;sql=$sql}
    if($sql.StartsWith('SELECT Id,Code')){
        if($parameters.code-ne$script:fixtureCode){throw 'Unexpected fixture tenant query.'}
        return ,(Table @(@{Id=3;Code=$script:fixtureCode;TenantTier='Dedicated';Status='Active';PaymentProviderCode=$script:route}))
    }
    if($sql.StartsWith('SELECT Id,PaymentProviderCode')){return ,(Table @(@{Id=3;PaymentProviderCode='OpenPay'}))}
    if($sql.StartsWith('SELECT Id,ProviderType')){
        if($database-eq$shared){throw 'Dedicated provider rows must not be required in the shared registry.'}
        return ,(Table @(@{Id=5;ProviderType='OpenPay';Use3DSecure=$true;IsProduction=$false},@{Id=6;ProviderType='Razorpay';Use3DSecure=$script:rzFlag;IsProduction=$false}))
    }
    if($sql.StartsWith('UPDATE dbo.Tenants')){
        if($database-ne$shared){throw 'Do not mutate the dedicated mirror route.'}
        $script:route=if($parameters.ContainsKey('route')){$parameters.route}else{$parameters.provider};return ,(Table @(@{Restored=1}))
    }
    if($sql.StartsWith('UPDATE payments.PaymentProviders')){if($parameters.provider-eq'Razorpay'){$script:rzFlag=$parameters.flag};return ,(Table @(@{Restored=1}))}
    throw 'Unexpected mock SQL.'
}
function Get-Phase10ComposeDedicatedTenantDatabaseMap { return @{ $script:fixtureCode='OrderProcessingSystem_IsolatedFixture_Dev' } }
$prepareRoute=$ast.Find({param($node) $node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Right.Extent.Text.Contains('SET PaymentProviderCode=@provider')},$true)
$prepareFlag=$ast.Find({param($node) $node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Right.Extent.Text.Contains('Use3DSecure=@flag WHERE TenantId=@id')},$true)
if(-not$prepareRoute-or-not$prepareFlag){throw 'Missing fixture preparation assignments.'}
foreach($script:fixtureCode in @('TenantC','Clinic-West-47')){
    $script:route='OpenPay';$script:rzFlag=$false;$script:calls=@()
    $original=Get-Snapshot $script:fixtureCode
    if($original.registryRoute-ne'OpenPay'-or$original.providers.Count-ne 2){throw 'Independent registry/provider snapshot failed.'}
    if($original.businessDatabase-ne'OrderProcessingSystem_IsolatedFixture_Dev'){throw 'Explicit dedicated mapping was not used.'}
    $snapshot=@{original=$original};$ProviderType='Razorpay';$TenantCode=$script:fixtureCode;$ThreeDs='true'
    . ([scriptblock]::Create($prepareRoute.Extent.Text))
    . ([scriptblock]::Create($prepareFlag.Extent.Text))
    $prepared=Get-Snapshot $script:fixtureCode
    if($prepared.registryRoute-ne'Razorpay'-or$prepared.businessRoute-ne'OpenPay'-or-not($prepared.providers|Where-Object provider -eq 'Razorpay').threeDs){throw 'Preparation did not separate authoritative route from dedicated provider settings.'}
    Restore-Snapshot $snapshot
    if($script:route-ne'OpenPay'-or$script:rzFlag){throw 'Exact restoration failed.'}
    Write-Host "PASS $script:fixtureCode shared registry without shared provider rows prepares/restores independently via explicit mapping."
}
# Exercise actual PowerShell-to-native argument expansion using source command construction.
$capture=Join-Path $PSScriptRoot 'tests/capture-native-args.ps1'
function docker { throw 'Docker execution is forbidden in this argument-capture test.' }
$startup=Get-Content (Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1') -Raw
$bootstrap=Get-Content (Join-Path $PSScriptRoot 'invoke-phase10-database-bootstrap.ps1') -Raw
$composeEnvArgs=@('--env-file','example.env','--env-file','private.env');$composeProfileArgs=@('--profile','apps');$composeFile='compose.yml'
foreach($ColdBuild in @($false,$true)){
    foreach($marker in @('$buildArgs = @(', '$appUpArguments = @(', '$functionUpArguments = @(')){
        $start=$startup.IndexOf($marker);$end=$startup.IndexOf('2>&1',$start)
        if($start-lt 0-or$end-lt 0){throw 'Missing startup argument construction.'}
        $snippet=$startup.Substring($start,$end-$start)
        if(-not$snippet.Contains('& docker ')){throw 'Unknown native invocation; do not execute the source fragment.'}
        $snippet=$snippet.Replace('& docker','& pwsh -NoProfile -File $capture')
        $captured=@(Invoke-Expression $snippet|ConvertFrom-Json)
        if($captured -contains '-' -or $captured -contains 'b'){throw 'Scalar flag was split at native boundary.'}
        $flag=if($marker-eq'$buildArgs = @('){if($ColdBuild){'--no-cache'}else{'build'}}else{if($ColdBuild){'--no-build'}else{'--build'}}
        if($flag-notin$captured){throw "Missing native startup flag $flag"}
    }
}
foreach($NoBuild in @($false,$true)){
    $start=$bootstrap.IndexOf('$buildOption = @()');$end=$bootstrap.IndexOf('2>&1',$start)
    $snippet=$bootstrap.Substring($start,$end-$start)
    if(-not$snippet.Contains('$output = & docker ')){throw 'Unknown bootstrap invocation; do not execute the source fragment.'}
    $snippet=$snippet.Replace('$output = & docker','& pwsh -NoProfile -File $capture')
    $captured=@(Invoke-Expression $snippet|ConvertFrom-Json)
    if(($captured-contains'--build')-eq$NoBuild-or'orders'-notin$captured-or'-'-in$captured){throw 'Bootstrap native argument capture failed.'}
}
Write-Host 'PASS daily/cold build, app/Functions startup and bootstrap native arguments.'
# Execute only the deterministic orchestration branch, replacing its native process
# with argument capture. No Docker, SQL or provider process is launched.
$orchestrationAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-phase10-local-container-stack-end-to-end.ps1'),[ref]$null,[ref]$null)
$matrixIf=$orchestrationAst.Find({param($node) $node-is[Management.Automation.Language.IfStatementAst]-and$node.Clauses[0].Item1.Extent.Text-eq"`$PaymentSuite -in @('deterministic', 'both')"},$true)
if(-not$matrixIf){throw 'Deterministic matrix branch is missing.'}
$matrixBody=$matrixIf.Clauses[0].Item2.Extent.Text
if(@($matrixIf.Clauses[0].Item2.FindAll({param($node) $node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-eq'pwsh'},$true)).Count-ne 1){throw 'Expected one discovered-tenant matrix invocation.'}
$matrixCode=$matrixBody.Substring(1,$matrixBody.Length-2).Replace('& pwsh','& pwsh -NoProfile -File $capture')
function Invoke-LoggedCommand {
    param([string]$Name,[scriptblock]$Script)
    if($Name-ne'payments-deterministic'){throw 'Unexpected targeted runtime payment invocation.'}
    $script:matrixCaptured=@(& $Script | ConvertFrom-Json)
}
$workspaceRoot=$root
foreach($AcceptanceProfile in @('baseline','extended')){
    $summary=@{steps=@()};$script:matrixCaptured=@()
    & ([scriptblock]::Create($matrixCode))
    $captured=$script:matrixCaptured
    if('-TenantCode'-in$captured-or'-ProviderType'-in$captured-or$AcceptanceProfile-notin$captured-or'deterministic'-notin$captured){throw 'Matrix was restricted to a tenant/provider or lost the selected profile.'}
    if(@($summary.steps).Count-ne 1-or$summary.steps[0].name-ne'payments-deterministic'){throw 'Unexpected deterministic matrix stages.'}
}
Write-Host 'PASS native matrix invocation discovers tenants without sample filters and preserves both acceptance profiles.'
# Absolute and relative artifact paths must resolve to the same owned directory.
$messagingAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'test-local-messaging.ps1'),[ref]$null,[ref]$null)
$artifactAssignment=$messagingAst.Find({param($node) $node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-eq'$artifact'},$true)
$relativePath='TestResults/DockerStorage/path-selftest'
foreach($ArtifactDirectory in @($relativePath,(Join-Path $root $relativePath))){
    . ([scriptblock]::Create($artifactAssignment.Extent.Text))
    if($artifact-ne[IO.Path]::GetFullPath((Join-Path $root $relativePath))){throw 'Messaging absolute/relative artifact resolution failed.'}
}
$auditAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'audit-phase10-sandbox-evidence.ps1'),[ref]$null,[ref]$null)
$dateFunction=$auditAst.Find({param($node) $node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-eq'ConvertTo-EvidenceUtc'},$true)
Invoke-Expression $dateFunction.Extent.Text
$iso='2026-11-09T20:40:01.216Z'
$jsonDate=('{"timestamp":"'+$iso+'"}'|ConvertFrom-Json).timestamp
foreach($value in @($iso,$jsonDate)){
    if((ConvertTo-EvidenceUtc $value).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')-ne$iso){throw 'Evidence UTC conversion changed the calendar date.'}
}
Write-Host 'PASS messaging artifact paths and JSON/string UTC correlation dates.'
# Execute the real final-report block in an isolated artifact directory with all external work mocked.
$hookSource=Get-Content (Join-Path $PSScriptRoot 'run-phase10-docker-dev-e2e-hook.ps1') -Raw
$hookAst=[Management.Automation.Language.Parser]::ParseInput($hookSource,[ref]$null,[ref]$null)
$tryNode=$hookAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]}|Select-Object -Last 1
$finalCode=$tryNode.Finally.Statements.Extent.Text-join[Environment]::NewLine
$workspaceRoot=Join-Path $root ('TestResults/DockerStorage/report-selftest-'+[guid]::NewGuid().ToString('N'))
$runRoot=Join-Path $workspaceRoot 'TestResults/run'
[void][IO.Directory]::CreateDirectory($runRoot)
@{status='partial';steps=@(@{name='sandbox-payments';status='partial'})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $runRoot 'e2e-summary.json')
$runSummary=[ordered]@{status='passed';startedUtc=[DateTime]::UtcNow.ToString('o');reusedExistingStack=$true}
$storageReportScript='mock-storage';$runSummaryPath=Join-Path $runRoot 'run-summary.md';$acceptanceLockOwned=$false
$previousPhase10RunId=$env:PHASE10_RUN_ID;$previousPhase10RunRoot=$env:PHASE10_RUN_ROOT
function pwsh {$global:LASTEXITCODE=0;return '{}'}
function Protect-Phase10Log {process{$_}}
function Write-RunSummary {}
& ([scriptblock]::Create($finalCode))
$packet=Get-Content (Join-Path $runRoot 'acceptance-packet.json') -Raw|ConvertFrom-Json
if($packet.status-ne'partial'-or@($packet.steps|Where-Object status -eq 'not-run').Count-lt 1-or$packet.restoration.status-ne'passed'){throw 'Partial/not-run/restoration packet semantics failed.'}
Write-Host 'PASS failed/partial final-report aggregation writes storage/restoration evidence without claiming PASS.'
. (Join-Path $PSScriptRoot 'phase10-acceptance-report.ps1')
$deferred=Resolve-Phase10ContinuationDecision -Summary ([pscustomobject]@{status='partial';results=@([pscustomobject]@{status='gap-observed';gap='No order-based Check payment status / Resume payment action.'})})
if($deferred.Status-ne'deferred'-or$deferred.Deferrals-notcontains'DW-023'){throw 'Approved continuation deferral was not preserved as deferred evidence.'}
foreach($invalid in @(
    [pscustomobject]@{status='failed';results=@()},
    [pscustomobject]@{status='partial';results=@()},
    [pscustomobject]@{status='partial';results=@([pscustomobject]@{status='gap-observed';gap='Unexpected order status mismatch'})},
    [pscustomobject]@{status='passed';results=@([pscustomobject]@{status='gap-observed';gap='No order-based Check payment status / Resume payment action.'})}
)){
    $rejected=$false;try{Resolve-Phase10ContinuationDecision -Summary $invalid|Out-Null}catch{$rejected=$true}
    if(-not$rejected){throw 'Continuation aggregation accepted a failed, incomplete, unapproved, or contradictory report.'}
}
Write-Host 'PASS structured continuation outcome rejects false PASS and labels only approved DW-023 recovery gaps deferred.'
$paymentRunnerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-local-payment-tests.ps1'),[ref]$null,[ref]$null)
$paymentTry=$paymentRunnerAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]}|Select-Object -Last 1
$paymentFinally=$paymentTry.Finally.Statements.Extent.Text-join[Environment]::NewLine
$compose=@('compose');$previous='true';$script:mockDockerExit=0;$script:runtimeModeObserved=$null
function docker {$script:runtimeModeObserved=$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS;$global:LASTEXITCODE=$script:mockDockerExit}
$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS='true'
& ([scriptblock]::Create($paymentFinally))
if($script:runtimeModeObserved-ne'false'-or$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS-ne'true'){throw 'Sandbox restore did not run or caller runtime setting was not restored.'}
$script:mockDockerExit=7;$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS='true';$restoreFailureObserved=$false
try{& ([scriptblock]::Create($paymentFinally))}catch{$restoreFailureObserved=$true}
if(-not$restoreFailureObserved-or$script:runtimeModeObserved-ne'false'-or$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS-ne'true'){throw 'Failed sandbox restore was hidden or caller runtime setting was not restored.'}
Write-Host 'PASS simulated/sandbox adapter wrapper restores sandbox after success and failure, while preserving caller environment.'
$e2eAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-phase10-local-container-stack-end-to-end.ps1'),[ref]$null,[ref]$null)
$e2eTry=$e2eAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]}|Select-Object -Last 1
$e2eFinally=$e2eTry.Finally.Statements.Extent.Text-join[Environment]::NewLine
$cleanupRoot=Join-Path $root ('TestResults/DockerStorage/cleanup-selftest-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($cleanupRoot)
$runDir=$cleanupRoot;$workspaceRoot=$root;$composeFile='compose.yml';$envExampleFile='example.env';$envFile='local.env'
$CleanupOnExit=$true;$RemoveVolumes=$false;$dockerAvailable=$true;$previousDockerConfig=$null
$progressLogPath=Join-Path $cleanupRoot 'progress.log';$summaryPath=Join-Path $cleanupRoot 'summary.json';$diagnosticsPath=Join-Path $cleanupRoot 'diagnostics.json'
$rootMarkerPath=Join-Path $cleanupRoot 'root-pointer.txt';$latestPointerPath=Join-Path $cleanupRoot 'latest-pointer.txt';$latestFailurePointerPath=Join-Path $cleanupRoot 'failure-pointer.txt'
$summary=[ordered]@{target='phase10-test';startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;status='running';steps=@()};$runFailed=$false;$runPartial=$false
function Write-ProgressLine([string]$Message){Add-Content -LiteralPath $progressLogPath -Value $Message}
function docker {$global:LASTEXITCODE=31;return 'mocked compose cleanup failure'}
& ([scriptblock]::Create($e2eFinally))
$cleanupSummary=Get-Content $summaryPath -Raw|ConvertFrom-Json
if($cleanupSummary.status-ne'failed'-or@($cleanupSummary.steps|Where-Object {$_.name-eq'cleanup'-and$_.status-eq'failed'}).Count-ne 1){throw 'Cleanup failure was not retained in the independent E2E stage summary.'}
Write-Host 'PASS mocked project cleanup failure remains a failed stage and cannot be overwritten by partial acceptance.'
