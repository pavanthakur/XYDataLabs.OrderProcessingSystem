#Requires -Version 7.0

param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$bootstrapScript = Join-Path $PSScriptRoot 'test-frontend-tenant-bootstrap.ps1'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-smoke.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_smoke"
$runDir = Join-Path $logRoot $runStamp
$startupLogPath = Join-Path $runDir '02-smoke.log'
$progressLogPath = Join-Path $runDir '02-smoke.log'
$summaryPath = Join-Path $runDir 'summary.json'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 Docker HTTP smoke run',
    'Goal: validate the browser flow against the Phase 10 Docker HTTP stack.',
    'Stages:',
    '1. Wait for gateway and UI readiness.',
    '2. Stabilize the environment.',
    '3. Run the tenant bootstrap smoke flow.',
    '4. Write summary.json and update latest pointers.'
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 Docker smoke startup`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "Phase 10 Docker smoke progress log initialized.`n" -Encoding utf8

function Wait-ForUrl {
    param(
        [string]$Url,
        [int]$TimeoutSec = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url"
}

Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec 300
Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec 300

Start-Sleep -Seconds $StabilizationDelaySeconds

$summary = [ordered]@{
    target = 'phase10-docker-http'
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    status = 'running'
    runDir = $runDir
    latestPointerPath = $latestPointerPath
}

try {
    Add-Content -Path $progressLogPath -Value 'Starting browser smoke execution.'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $bootstrapScript -Target phase10-docker-http
    if ($LASTEXITCODE -ne 0) {
        throw "Phase 10 smoke failed with exit code $LASTEXITCODE"
    }

    $summary.status = 'passed'
    Add-Content -Path $progressLogPath -Value 'Smoke execution completed successfully.'
}
catch {
    $summary.status = 'failed'
    Add-Content -Path $progressLogPath -Value "Smoke execution failed: $($_.Exception.Message)"
    throw
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
}
