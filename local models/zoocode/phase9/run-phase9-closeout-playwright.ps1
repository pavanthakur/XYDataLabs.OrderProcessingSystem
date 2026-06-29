param(
    [ValidateRange(120, 300)]
    [int]$StabilizationDelaySeconds = 180,
    [switch]$InstallBrowser,
    [ValidateSet('local-http', 'docker-dev-http')]
    [string]$Target = 'docker-dev-http'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$playwrightScript = Join-Path $repoRoot 'scripts\test-frontend-tenant-bootstrap.ps1'
$readyMap = @{
    'local-http' = @{
        Api = 'http://localhost:5010/health/ready'
        Ui  = 'http://localhost:5173/'
    }
    'docker-dev-http' = @{
        Api = 'http://localhost:5020/health/ready'
        Ui  = 'http://localhost:5022/'
    }
}

$localReadyUrl = $readyMap[$Target].Api
$uiReadyUrl = $readyMap[$Target].Ui

function Wait-ForHttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) {
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url"
}

if (-not (Test-Path $playwrightScript)) {
    throw "Playwright smoke script not found: $playwrightScript"
}

Wait-ForHttpOk -Url $localReadyUrl -TimeoutSeconds 300
Wait-ForHttpOk -Url $uiReadyUrl -TimeoutSeconds 300

Write-Host "VS-style local environment is ready. Waiting an additional $StabilizationDelaySeconds seconds before Playwright smoke testing." -ForegroundColor Yellow
Start-Sleep -Seconds $StabilizationDelaySeconds

if ($InstallBrowser) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightScript -InstallBrowser -Target local-http
}
else {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $playwrightScript -Target $Target
}

if ($LASTEXITCODE -ne 0) {
    throw "Playwright closeout failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Phase 9 Playwright closeout completed." -ForegroundColor Green
