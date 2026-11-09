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

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
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
    error = $null
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

try {
    $handle=[IO.File]::Open($acceptanceLockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes($runRoot);$handle.Write($bytes,0,$bytes.Length);$acceptanceLockOwned=$true}finally{$handle.Dispose()}
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
    Write-Host 'Phase 10 Docker dev HTTP end-to-end validation hook completed successfully.' -ForegroundColor Green
}
catch {
    $runSummary.status = 'failed'
    $runSummary.error = $_.Exception.Message
    Set-Content -Path $latestFailurePointerPath -Value $runRoot -Encoding utf8
    throw
}
finally {
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
    $steps=@($child.steps|Where-Object {$null-ne$_})
    foreach($name in @('foundations','smoke','integration','openpay-local-baseline','baseline-validation','customer-directory','tenantc-routing-regression','payments-deterministic','sandbox-payments','currency-order-entry','order-continuation','messaging-functions','persistence','provider-restoration')){
        if($name-notin$steps.name){$steps+=@{name=$name;status='not-run'}}
    }
    $profilePath=Join-Path $runRoot 'profile-summary.json'
    $deployment=if($runSummary.reusedExistingStack){'reused-ready-stack'}elseif(Test-Path $profilePath){(Get-Content $profilePath -Raw|ConvertFrom-Json).status}else{'not-run'}
    $packet=@{status=$runSummary.status;runRoot=$runRoot;deployment=$deployment;steps=$steps;restoration=$restoration;storageExitCode=$runSummary.storageExitCode;deferrals=@('DW-023','DW-024');notCertified=@('fulfillment','monetary installments','deferred unresolved-order eligibility/recovery');note='Raw failed/partial evidence is preserved; capability gaps are not PASS.'}
    $packet|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $runRoot 'acceptance-packet.json')
    Write-RunSummary -Summary $runSummary
    if($acceptanceLockOwned){Remove-Item -LiteralPath $acceptanceLockPath}
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
