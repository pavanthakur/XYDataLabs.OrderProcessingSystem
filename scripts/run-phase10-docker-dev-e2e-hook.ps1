#Requires -Version 7.0

param(
    [ValidateRange(30, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [switch]$SkipStartIfNeeded
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$stackStartScript = Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1'
$e2eScript = Join-Path $PSScriptRoot 'run-phase10-local-container-stack-end-to-end.ps1'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'

New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

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

try {
    Assert-ScriptExists -Path $stackStartScript
    Assert-ScriptExists -Path $e2eScript

    $gatewayReady = Test-UrlReachable -Url 'http://localhost:5080/health/alive'
    $uiReady = Test-UrlReachable -Url 'http://localhost:5022/'

    if (-not ($gatewayReady -and $uiReady)) {
        if ($SkipStartIfNeeded) {
            throw 'Phase 10 Docker dev HTTP stack is not reachable. Start Docker Desktop or pass -StartIfNeeded to let the hook bring the stack up.'
        }

        Write-Host 'Phase 10 Docker dev HTTP stack is not ready. Starting it now...' -ForegroundColor Cyan
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $stackStartScript -Action up -Profile apps -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start the Phase 10 Docker dev HTTP stack with exit code $LASTEXITCODE."
        }
    }
    else {
        Write-Host 'Phase 10 Docker dev HTTP stack is already reachable. Reusing the live stack.' -ForegroundColor Cyan
    }

    Write-Host 'Running Phase 10 Docker dev HTTP end-to-end validation hook...' -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $e2eScript -SkipProfileStart -StabilizationDelaySeconds $StabilizationDelaySeconds
    if ($LASTEXITCODE -ne 0) {
        throw "Phase 10 Docker dev HTTP end-to-end validation hook failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Phase 10 Docker dev HTTP end-to-end validation hook completed successfully.' -ForegroundColor Green
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
}
