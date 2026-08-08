#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$BurstMessageCount = 100,

    [ValidateRange(30, 3600)]
    [int]$PerformanceTimeoutSeconds = 2400,

    [ValidateRange(1, 120)]
    [double]$MaximumP95Seconds = 30,

    [switch]$UseCleanReset,

    [switch]$SkipOperationalChecks,

    [switch]$SkipStartIfNeeded
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$stackStartScript = Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1'
$localProofScript = Join-Path $PSScriptRoot 'run-phase10-local-nfr-proof.ps1'
$artifactRoot = Join-Path $workspaceRoot 'TestResults\Phase10\docker-preazure'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $artifactRoot "phase10-docker-nfr-$runStamp"
$startedUtc = (Get-Date).ToUniversalTime().ToString('o')
$progressPath = Join-Path $runDir 'wrapper-progress.log'
$currentStepPath = Join-Path $runDir 'wrapper-current-step.txt'
$planPath = Join-Path $runDir 'wrapper-run-plan.txt'
$summaryPath = Join-Path $runDir 'wrapper-summary.json'
$latestPointerPath = Join-Path $artifactRoot 'latest-phase10-docker-nfr.txt'
$failurePointerPath = Join-Path $artifactRoot 'latest-failure-phase10-docker-nfr.txt'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -LiteralPath $progressPath -Value '' -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8
Set-Content -LiteralPath $planPath -Encoding utf8 -Value @(
    'Phase 10 docker NFR proof',
    "Started (UTC): $((Get-Date).ToUniversalTime().ToString('o'))",
    'Purpose: reuse the proven local NFR proof engine against the Docker Dev HTTP stack and record Docker-specific evidence.',
    "Clean reset: $(if ($UseCleanReset) { 'enabled' } else { 'available via -UseCleanReset' }).",
    "Operational checks: $(if ($SkipOperationalChecks) { 'skipped via -SkipOperationalChecks' } else { 'enabled' }).",
    "Stack start on demand: $(if ($SkipStartIfNeeded) { 'disabled' } else { 'enabled' })."
)

function Write-WrapperProgress {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format o), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressPath -Value $line -Encoding utf8
}

function Test-UrlReachable {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

Set-Content -LiteralPath $summaryPath -Encoding utf8 -Value (@{
    target = 'phase10-docker-nfr'
    status = 'running'
    startedUtc = $startedUtc
    completedUtc = $null
    runDir = $runDir
    localProofRunRoot = Join-Path $runDir 'nfr'
    proofScript = $localProofScript
    latestPointerPath = $latestPointerPath
    failurePointerPath = $failurePointerPath
} | ConvertTo-Json -Depth 8)

Write-WrapperProgress "Docker NFR wrapper initialized. runDir=$runDir"
Set-Content -LiteralPath $currentStepPath -Value 'stack-readiness' -Encoding utf8

try {
    $gatewayReady = Test-UrlReachable -Url 'http://localhost:5080/health/alive'
    $uiReady = Test-UrlReachable -Url 'http://localhost:5022/'

    if (-not ($gatewayReady -and $uiReady)) {
        if ($SkipStartIfNeeded) {
            throw 'The Phase 10 Docker Dev HTTP stack is not reachable. Start Docker Desktop or rerun without -SkipStartIfNeeded.'
        }

        Write-WrapperProgress 'Starting the Phase 10 Docker Dev HTTP stack because the endpoints are not yet reachable.'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker Dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    else {
        Write-WrapperProgress 'The Phase 10 Docker Dev HTTP stack is already reachable.'
    }

    Set-Content -LiteralPath $currentStepPath -Value 'local-proof' -Encoding utf8
    Write-WrapperProgress 'Running the shared NFR proof engine against the Docker stack.'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $localProofScript `
        -ArtifactRoot $runDir `
        -ProofName 'Phase 10 docker NFR proof' `
        -BurstMessageCount $BurstMessageCount `
        -PerformanceTimeoutSeconds $PerformanceTimeoutSeconds `
        -MaximumP95Seconds $MaximumP95Seconds `
        -UseCleanReset:$UseCleanReset `
        -SkipOperationalChecks:$SkipOperationalChecks

    if ($LASTEXITCODE -ne 0) {
        throw "Phase 10 docker NFR proof failed with exit code $LASTEXITCODE."
    }

    Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
    Set-Content -LiteralPath $summaryPath -Encoding utf8 -Value (@{
        target = 'phase10-docker-nfr'
        status = 'passed'
        startedUtc = $startedUtc
        completedUtc = (Get-Date).ToUniversalTime().ToString('o')
        runDir = $runDir
        localProofRunRoot = Join-Path $runDir 'nfr'
        proofScript = $localProofScript
        latestPointerPath = $latestPointerPath
        failurePointerPath = $failurePointerPath
    } | ConvertTo-Json -Depth 8)
    Remove-Item -LiteralPath $failurePointerPath -Force -ErrorAction SilentlyContinue
    Write-WrapperProgress 'Phase 10 docker NFR proof passed.'
}
catch {
    Set-Content -LiteralPath $currentStepPath -Value 'failed' -Encoding utf8
    Set-Content -LiteralPath $failurePointerPath -Value $runDir -Encoding utf8
    Set-Content -LiteralPath $summaryPath -Encoding utf8 -Value (@{
        target = 'phase10-docker-nfr'
        status = 'failed'
        startedUtc = $startedUtc
        completedUtc = (Get-Date).ToUniversalTime().ToString('o')
        runDir = $runDir
        localProofRunRoot = Join-Path $runDir 'nfr'
        proofScript = $localProofScript
        latestPointerPath = $latestPointerPath
        failurePointerPath = $failurePointerPath
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 8)
    Write-WrapperProgress "Phase 10 docker NFR proof failed: $($_.Exception.Message)"
    throw
}
