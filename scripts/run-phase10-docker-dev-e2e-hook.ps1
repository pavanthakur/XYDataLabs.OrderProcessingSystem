#Requires -Version 7.0

param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$IntegrationConsoleVerbosity = 'minimal',

    [string]$RunId = '',

    [switch]$ReuseExistingStack,

    [switch]$SkipStartIfNeeded
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$stackStartScript = Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1'
$e2eScript = Join-Path $PSScriptRoot 'run-phase10-local-container-stack-end-to-end.ps1'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
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

New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
$previousDockerConfig = $env:DOCKER_CONFIG
$previousPhase10RunId = $env:PHASE10_RUN_ID
$previousPhase10RunRoot = $env:PHASE10_RUN_ROOT
$env:DOCKER_CONFIG = $dockerConfigRoot
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
    cleanAzureParity = -not $ReuseExistingStack
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
    Assert-ScriptExists -Path $stackStartScript
    Assert-ScriptExists -Path $e2eScript

    $gatewayReady = Test-UrlReachable -Url 'http://localhost:5080/health/alive'
    $uiReady = Test-UrlReachable -Url 'http://localhost:5022/'

    if (-not $ReuseExistingStack) {
        Write-Host 'Starting Phase 10 Docker dev HTTP stack in clean Azure-parity mode...' -ForegroundColor Cyan
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    elseif (-not ($gatewayReady -and $uiReady)) {
        if ($SkipStartIfNeeded) {
            throw 'Phase 10 Docker dev HTTP stack is not reachable. Start Docker Desktop or omit -SkipStartIfNeeded to let the hook bring the stack up.'
        }

        Write-Host 'Phase 10 Docker dev HTTP stack is not ready. Starting it now...' -ForegroundColor Cyan
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    else {
        Write-Host 'Phase 10 Docker dev HTTP stack is already reachable. Reusing the live stack.' -ForegroundColor Cyan
        $runSummary.reusedExistingStack = $true
    }

    Write-Host 'Running Phase 10 Docker dev HTTP end-to-end validation hook...' -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $e2eScript -StabilizationDelaySeconds $StabilizationDelaySeconds -IntegrationConsoleVerbosity $IntegrationConsoleVerbosity
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
    Write-RunSummary -Summary $runSummary
    Write-Host "Phase 10 run summary: $runSummaryPath" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }

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
