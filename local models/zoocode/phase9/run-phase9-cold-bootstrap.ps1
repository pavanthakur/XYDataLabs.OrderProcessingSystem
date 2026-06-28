param(
    [ValidateRange(60, 600)]
    [int]$DockerStartupTimeoutSeconds = 300,

    [ValidateRange(120, 600)]
    [int]$StabilizationDelaySeconds = 180,

    [switch]$InstallBrowser
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$dockerBootstrapScript = Join-Path $repoRoot 'Resources\Docker\start-docker.ps1'
$playwrightCloseoutScript = Join-Path $PSScriptRoot 'run-phase9-closeout-playwright.ps1'
$phase9LogDir = Join-Path $repoRoot '.tmp'
$phase9LogFile = Join-Path $phase9LogDir 'phase9-cold-bootstrap.log'

if (-not (Test-Path $phase9LogDir)) {
    New-Item -ItemType Directory -Path $phase9LogDir | Out-Null
}

Start-Transcript -Path $phase9LogFile -Append | Out-Null

function Invoke-Checked {
    param(
        [scriptblock]$ScriptBlock,
        [string]$FailureMessage
    )

    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)"
    }
}

if (-not (Test-Path $dockerBootstrapScript)) {
    throw "Docker bootstrap script not found: $dockerBootstrapScript"
}

if (-not (Test-Path $playwrightCloseoutScript)) {
    throw "Playwright closeout script not found: $playwrightCloseoutScript"
}

try {
    Write-Host "Phase 9 cold bootstrap started." -ForegroundColor Cyan
    Write-Host "Step 1/2: start Docker dev stack from a clean machine state." -ForegroundColor Cyan

    Invoke-Checked {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $dockerBootstrapScript -Environment dev -Profile http
    } "Docker dev bootstrap failed"

    Write-Host ""
    Write-Host "Step 2/2: run Playwright closeout against the Docker-backed dev stack." -ForegroundColor Cyan

    Invoke-Checked {
        if ($InstallBrowser) {
            pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightCloseoutScript -StabilizationDelaySeconds $StabilizationDelaySeconds -InstallBrowser
        }
        else {
            pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightCloseoutScript -StabilizationDelaySeconds $StabilizationDelaySeconds
        }
    } "Phase 9 Playwright closeout failed"

    Write-Host ""
    Write-Host "Phase 9 cold bootstrap completed successfully." -ForegroundColor Green
}
finally {
    Stop-Transcript | Out-Null
}
