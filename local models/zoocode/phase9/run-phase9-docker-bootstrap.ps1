param(
    [ValidateRange(60, 600)]
    [int]$DockerStartupTimeoutSeconds = 300,

    [ValidateRange(120, 600)]
    [int]$StabilizationDelaySeconds = 180,

    [switch]$InstallBrowser
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$profileRunner = Join-Path $PSScriptRoot 'run-phase9-docker-profile.ps1'
$playwrightRunner = Join-Path $PSScriptRoot 'run-phase9-closeout-playwright.ps1'

if (-not (Test-Path $profileRunner)) {
    throw "Docker profile runner not found: $profileRunner"
}

if (-not (Test-Path $playwrightRunner)) {
    throw "Playwright runner not found: $playwrightRunner"
}

Write-Host "Phase 9 Docker bootstrap started." -ForegroundColor Cyan
Write-Host "Step 1/2: start dev/http using the existing Docker profile runner." -ForegroundColor Cyan

& pwsh -NoProfile -ExecutionPolicy Bypass -File $profileRunner -Environment dev -Profile http -Reset -Strict
if ($LASTEXITCODE -ne 0) {
    throw "Docker profile runner failed for dev/http with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Step 2/2: run Playwright closeout after the dev/http stack stabilizes." -ForegroundColor Cyan

if ($InstallBrowser) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightRunner -StabilizationDelaySeconds $StabilizationDelaySeconds -InstallBrowser
} else {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightRunner -StabilizationDelaySeconds $StabilizationDelaySeconds
}

if ($LASTEXITCODE -ne 0) {
    throw "Playwright closeout failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Phase 9 Docker bootstrap completed successfully." -ForegroundColor Green
