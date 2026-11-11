#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$IntegrationConsoleVerbosity = 'minimal',

    [string]$RunId = '',

    [switch]$ReuseExistingStack,

    [switch]$SkipStartIfNeeded,

    [switch]$ResetData,

    [switch]$ColdBuild,

    [switch]$VerifyPersistence,

    [ValidateSet('sandbox', 'deterministic', 'both')]
    [string]$PaymentSuite = 'sandbox',

    [ValidateSet('baseline','extended')]
    [string]$AcceptanceProfile = 'baseline'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
if ($ResetData -and $ReuseExistingStack) { throw '-ResetData cannot be combined with -ReuseExistingStack.' }
if ($ColdBuild -and $ReuseExistingStack) { throw '-ColdBuild cannot be combined with -ReuseExistingStack; cold build requires the startup path.' }
if ($WhatIfPreference) { Write-Host "Would start/test xy-phase10 (reset data: $ResetData). No changes made."; return }
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$stackStartScript = Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1'
$e2eScript = Join-Path $PSScriptRoot 'run-phase10-local-container-stack-end-to-end.ps1'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$resolvedRunId = if ([string]::IsNullOrWhiteSpace($RunId)) {
    "phase10-docker-http-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
}
else {
    $RunId
}
$runRoot = Join-Path $logRoot $resolvedRunId
$runSummaryPath = Join-Path $runRoot 'run-summary.md'
$runSummaryJsonPath = Join-Path $runRoot 'run-summary.json'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-run.txt'
$latestFailurePointerPath = Join-Path $logRoot 'latest-playwright-failure.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$storageReportScript = Join-Path $PSScriptRoot 'inspect-phase10-docker-storage.ps1'
$acceptanceLockPath=Join-Path $workspaceRoot 'TestResults/phase10-docker-acceptance.lock'
$acceptanceLockOwned=$false

New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
$previousPhase10RunId = $env:PHASE10_RUN_ID
$previousPhase10RunRoot = $env:PHASE10_RUN_ROOT
$env:PHASE10_RUN_ID = $resolvedRunId
$env:PHASE10_RUN_ROOT = $runRoot

Set-Content -Path $latestPointerPath -Value $runRoot -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runRoot -Encoding utf8

function Test-UrlReachable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

function Assert-ScriptExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required script not found: $Path"
    }
}

$runSummary = [ordered]@{
    runId = $resolvedRunId
    runRoot = $runRoot
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    status = 'running'
    stabilizationDelaySeconds = $StabilizationDelaySeconds
    integrationConsoleVerbosity = $IntegrationConsoleVerbosity
    reusedExistingStack = $false
    summaryPath = $runSummaryPath
    summaryJsonPath = $runSummaryJsonPath
    profileSummaryPath = Join-Path $runRoot 'profile-summary.json'
    e2eSummaryPath = Join-Path $runRoot 'e2e-summary.json'
    diagnosticsPath = Join-Path $runRoot 'diagnostics.json'
    integrationRunPath = Join-Path $runRoot 'integration'
    latestPointerPath = $latestPointerPath
    latestFailurePointerPath = $latestFailurePointerPath
    cleanAzureParity = [bool]$ResetData
    coldBuild = [bool]$ColdBuild
    paymentSuite = $PaymentSuite
    acceptanceProfile = $AcceptanceProfile
    gitProvenance = @{ start = $null; finish = $null }
    error = $null
}

function Get-Phase10GitSnapshot {
    param([Parameter(Mandatory = $true)][string]$Directory)
    try {
        $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $commit = @(& $git.Source -C $Directory rev-parse --verify HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or $commit.Count -ne 1 -or $commit[0] -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$') {
            throw 'Could not resolve a valid Git commit.'
        }
        $changes = @(& $git.Source --no-optional-locks -C $Directory status --porcelain=v1 --untracked-files=normal 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Git worktree status.' }
        return @{ commit = $commit[0]; worktree = $(if ($changes.Count -gt 0) { 'dirty' } else { 'clean' }) }
    } catch {
        Write-Warning 'Git provenance is unavailable; candidate identity remains unverified.'
        return @{ commit = $null; worktree = 'unknown' }
    }
}

function Write-RunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Summary
    )

    $Summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')

    Set-Content -Path $runSummaryJsonPath -Value ($Summary | ConvertTo-Json -Depth 8) -Encoding utf8

    $summaryLines = @(
        '# Phase 10 Docker Dev HTTP Run',
        '',
        '| Field | Value |',
        '|---|---|',
        "| Run ID | $($Summary.runId) |",
        "| Status | $($Summary.status) |",
        "| Started UTC | $($Summary.startedUtc) |",
        "| Finished UTC | $($Summary.finishedUtc) |",
        "| Run Root | $($Summary.runRoot) |",
        "| Reused Existing Stack | $($Summary.reusedExistingStack) |",
        "| Stabilization Delay Seconds | $($Summary.stabilizationDelaySeconds) |",
        "| Integration Console Verbosity | $($Summary.integrationConsoleVerbosity) |",
        '',
        '## Run Packet',
        '',
        '| Artifact | Path |',
        '|---|---|',
        "| Profile Summary | $($Summary.profileSummaryPath) |",
        "| End-to-End Summary | $($Summary.e2eSummaryPath) |",
        "| Diagnostics | $($Summary.diagnosticsPath) |",
        "| Integration Logs | $($Summary.integrationRunPath) |",
        "| JSON Summary | $($Summary.summaryJsonPath) |"
    )

    if (-not [string]::IsNullOrWhiteSpace($Summary.error)) {
        $summaryLines += ''
        $summaryLines += '## Failure'
        $summaryLines += ''
        $summaryLines += $Summary.error
    }

    Set-Content -Path $runSummaryPath -Value $summaryLines -Encoding utf8
}

function Invoke-Phase10Preview {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $automationRoot = Join-Path $workspaceRoot 'automation'
    $previewLog = Join-Path $Directory 'phase10-preview.log'
    & npm --prefix $automationRoot run report:phase10-preview -- $Directory 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath $previewLog | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Directory 'phase10-preview.html') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Directory 'index.html') -PathType Leaf)) {
        throw 'Phase 10 preview generation failed; inspect the sanitized preview log.'
    }
}

function Write-Phase10Completion {
    param([Parameter(Mandatory = $true)][string]$Directory, [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Summary)
    $paths = @('acceptance-packet.json', 'run-summary.json', 'phase10-preview.html', 'phase10-coverage-summary.json', 'index.html',
        'docker-image-identities-before.json', 'docker-image-identities-after.json')
    foreach ($name in $paths) {
        $item = Get-Item -LiteralPath (Join-Path $Directory $name) -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 2MB) {
            throw 'Finalization artifact is not a bounded regular file.'
        }
    }
    $packet = Get-Content -LiteralPath (Join-Path $Directory 'acceptance-packet.json') -Raw | ConvertFrom-Json
    $savedSummary = Get-Content -LiteralPath (Join-Path $Directory 'run-summary.json') -Raw | ConvertFrom-Json
    if ($Summary.status -notin @('passed', 'partial', 'failed') -or
        [string]::IsNullOrWhiteSpace($Summary.runId) -or
        $Summary.runId -cne (Split-Path -Leaf $Directory) -or
        $savedSummary.runId -cne $Summary.runId -or
        $packet.status -cne $Summary.status -or $savedSummary.status -cne $Summary.status -or
        $packet.runRoot -cne $savedSummary.runRoot -or $savedSummary.runRoot -cne $Directory) {
        throw 'Finalization artifacts have inconsistent run identity or status.'
    }
    $hashes = [ordered]@{}
    foreach ($name in $paths) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $Directory $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $record = [ordered]@{
        schema = 'phase10-completion-v4'
        runId = $Summary.runId
        status = $Summary.status
        sha256 = $hashes
    }
    $temporary = Join-Path $Directory ('phase10-completion-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $destination = Join-Path $Directory 'phase10-completion.json'
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Depth 5))
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        [IO.File]::Move($temporary, $destination)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

try {
    $handle=[IO.File]::Open($acceptanceLockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes($runRoot);$handle.Write($bytes,0,$bytes.Length);$acceptanceLockOwned=$true}finally{$handle.Dispose()}
    $runSummary.gitProvenance.start = Get-Phase10GitSnapshot -Directory $workspaceRoot
    if (Test-Path (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock')) { throw 'Payment fixture recovery is required before deployment.' }
    if (@(Get-ChildItem (Join-Path $workspaceRoot 'TestResults') -Filter 'integration-active-*.lock').Count) { throw 'Active/interrupted integration execution must be reviewed before deployment.' }
    Assert-ScriptExists -Path $stackStartScript
    Assert-ScriptExists -Path $e2eScript
    Assert-Phase10PortOwnership -Ports @(5080, 5022, (Get-Phase10SqlHostPort))

    $gatewayReady = Test-UrlReachable -Url 'http://localhost:5080/health/alive'
    $uiReady = Test-UrlReachable -Url 'http://localhost:5022/'

    if (-not $ReuseExistingStack) {
        Write-Host 'Starting Phase 10 Docker dev HTTP stack (data preserved unless -ResetData was confirmed)...' -ForegroundColor Cyan
        & $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300 -ResetData:$ResetData -ColdBuild:$ColdBuild
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    elseif (-not ($gatewayReady -and $uiReady)) {
        if ($SkipStartIfNeeded) {
            throw 'Phase 10 Docker dev HTTP stack is not reachable. Start Docker Desktop or omit -SkipStartIfNeeded to let the hook bring the stack up.'
        }

        Write-Host 'Phase 10 Docker dev HTTP stack is not ready. Starting it now...' -ForegroundColor Cyan
        & $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300 -ColdBuild:$ColdBuild -Confirm:$false
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    else {
        Write-Host 'Phase 10 Docker dev HTTP stack is already reachable. Reusing the live stack.' -ForegroundColor Cyan
        $runSummary.reusedExistingStack = $true
    }

    $storageReportScript = Join-Path $PSScriptRoot 'inspect-phase10-docker-storage.ps1'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $storageReportScript -Mode Report -ManifestPath (Join-Path $runRoot 'storage-before.json') 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runRoot 'storage-before.log') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Pre-test Docker storage report failed; stopping before test work.' }

    Write-Host 'Running Phase 10 Docker dev HTTP end-to-end validation hook...' -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $e2eScript -StabilizationDelaySeconds $StabilizationDelaySeconds -IntegrationConsoleVerbosity $IntegrationConsoleVerbosity -PaymentSuite $PaymentSuite -AcceptanceProfile $AcceptanceProfile -VerifyPersistence:$VerifyPersistence
    if ($LASTEXITCODE -ne 0) {
        throw "Phase 10 Docker dev HTTP end-to-end validation hook failed with exit code $LASTEXITCODE."
    }

    $runSummary.status = 'passed'
    Write-Host 'Phase 10 Docker dev HTTP execution completed; finalization is pending.' -ForegroundColor Cyan
}
catch {
    $runSummary.status = 'failed'
    $runSummary.error = $_.Exception.Message
    try {
        Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8
    } catch {
        Write-Warning 'Could not write the Phase 10 failure pointer; run evidence may be incomplete.'
    }
    throw
}
finally {
  $finalizationComplete = $true
  try {
    $fixtureDirectory=Join-Path $workspaceRoot 'TestResults/DockerStorage/payment-state'
    $ownedFixtures=@(if(Test-Path $fixtureDirectory){Get-ChildItem $fixtureDirectory -Filter '*.json' | Where-Object LastWriteTimeUtc -ge ([DateTime]::Parse($runSummary.startedUtc).ToUniversalTime()) | ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}})
    $fixtureLockPresent=Test-Path (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock')
    $allRestored=(-not$fixtureLockPresent)-and@($ownedFixtures|Where-Object status -ne 'restored').Count-eq 0
    $restoration=@{status=$(if($allRestored){'passed'}else{'failed'});fixtureCount=$ownedFixtures.Count;allRestored=$allRestored;fixtureLockPresent=$fixtureLockPresent}
    $restoration|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $runRoot 'fixture-restoration.json')
    try {
        & pwsh -NoProfile -File $storageReportScript -Mode Report -ManifestPath (Join-Path $runRoot 'storage-after.json') 2>&1 |
            Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runRoot 'storage-after.log') | Out-Null
        $runSummary.storageExitCode = $LASTEXITCODE
    } catch { $runSummary.storageExitCode = 1 }
    $childPath=Join-Path $runRoot 'e2e-summary.json'
    $child=if(Test-Path $childPath){Get-Content $childPath -Raw|ConvertFrom-Json}else{$null}
    if($child.status-eq'partial'-and$runSummary.status-ne'failed'){$runSummary.status='partial'}
    if($runSummary.storageExitCode-ne 0){$runSummary.status='failed'}
    if(-not$allRestored){$runSummary.status='failed'}
    if($runFailed){$runSummary.status='failed'}
    if($runSummary.status-eq'failed'){Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8}
    $steps=@($child.steps|Where-Object {$null-ne$_})
    foreach($name in @('foundations','smoke','integration','openpay-local-baseline','baseline-validation','customer-directory','tenantc-routing-regression','payments-deterministic','sandbox-payments','currency-order-entry','order-continuation','messaging-functions','persistence','provider-restoration')){
        if($name-notin$steps.name){$steps+=@{name=$name;status='not-run'}}
    }
    $profilePath=Join-Path $runRoot 'profile-summary.json'
    $deployment=if($runSummary.reusedExistingStack){'reused-ready-stack'}elseif(Test-Path $profilePath){(Get-Content $profilePath -Raw|ConvertFrom-Json).status}else{'not-run'}
    $runSummary.gitProvenance.finish = Get-Phase10GitSnapshot -Directory $workspaceRoot
    $packet=@{status=$runSummary.status;runRoot=$runRoot;deployment=$deployment;steps=$steps;restoration=$restoration;storageExitCode=$runSummary.storageExitCode;deferrals=@('DW-023','DW-024');notCertified=@('fulfillment','monetary installments','deferred unresolved-order eligibility/recovery');note='Raw failed/partial evidence is preserved; capability gaps are not PASS.'}
    $packet|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $runRoot 'acceptance-packet.json')
    Write-RunSummary -Summary $runSummary
    try {
        Invoke-Phase10Preview -Directory $runRoot
    } catch {
        $finalizationComplete = $false
        $runSummary.status = 'failed'
        if ([string]::IsNullOrWhiteSpace($runSummary.error)) {
            $runSummary.error = 'Phase 10 preview generation failed; inspect the sanitized preview log.'
        } else {
            $runSummary.error += ' Phase 10 preview generation also failed; inspect the sanitized preview log.'
        }
        $packet.status = 'failed'
        $packet.reportPreview = 'failed'
        $packet|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $runRoot 'acceptance-packet.json')
        Write-RunSummary -Summary $runSummary
        Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8
        Write-Warning 'Phase 10 preview generation failed; the run is marked failed.'
    }
  } catch {
    $finalizationComplete = $false
    $runSummary.status = 'failed'
    if ([string]::IsNullOrWhiteSpace($runSummary.error)) {
        $runSummary.error = 'Phase 10 finalization failed; run evidence may be incomplete.'
    } else {
        $runSummary.error += ' Phase 10 finalization also failed; run evidence may be incomplete.'
    }
    Write-Warning 'Phase 10 finalization failed; run evidence may be incomplete.'
    try {
        if ($null -ne $packet) {
            $packet.status = 'failed'
            $packet|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $runRoot 'acceptance-packet.json')
        }
        Write-RunSummary -Summary $runSummary
        Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8
    } catch {
        Write-Warning 'Could not persist failed finalization status; existing run evidence must not be trusted.'
    }
  } finally {
    try {
        if($acceptanceLockOwned){Remove-Item -LiteralPath $acceptanceLockPath}
    } catch {
        $finalizationComplete = $false
        $runSummary.status = 'failed'
        if ([string]::IsNullOrWhiteSpace($runSummary.error)) {
            $runSummary.error = 'Could not remove the owned Phase 10 acceptance lock.'
        } else {
            $runSummary.error += ' Could not remove the owned Phase 10 acceptance lock.'
        }
        Write-Warning 'Could not remove the owned Phase 10 acceptance lock.'
        try {
            if ($null -ne $packet) {
                $packet.status = 'failed'
                $packet|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $runRoot 'acceptance-packet.json')
            }
            Write-RunSummary -Summary $runSummary
            Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8
        } catch {
            Write-Warning 'Could not persist the lock cleanup failure; existing run evidence must not be trusted.'
        }
    }
    Write-Host "Phase 10 run summary: $runSummaryPath" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($previousPhase10RunId)) {
        Remove-Item Env:PHASE10_RUN_ID -ErrorAction SilentlyContinue
    }
    else {
        $env:PHASE10_RUN_ID = $previousPhase10RunId
    }

    if ([string]::IsNullOrWhiteSpace($previousPhase10RunRoot)) {
        Remove-Item Env:PHASE10_RUN_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:PHASE10_RUN_ROOT = $previousPhase10RunRoot
    }
  }
  if ($finalizationComplete) {
    try {
        Write-Phase10Completion -Directory $runRoot -Summary $runSummary
    } catch {
        $runSummary.status = 'failed'
        Write-Warning 'Could not publish Phase 10 completion record; run evidence is incomplete.'
    }
  }
}
if ($runSummary.status -eq 'failed') {
    throw 'Phase 10 finalization reported a failed run; inspect the run summary.'
}
