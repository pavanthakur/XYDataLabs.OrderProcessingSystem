#Requires -Version 7.0

param(
    [ValidateRange(120, 300)]
    [int]$StabilizationDelaySeconds = 180,
    [switch]$InstallBrowser
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\docker-http'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-smoke.txt'
$environmentPointerPath = Join-Path $logRoot 'latest-playwright-docker-http.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_smoke"
$runDir = Join-Path $logRoot $runStamp
$playwrightScript = Join-Path $PSScriptRoot 'test-frontend-tenant-bootstrap.ps1'
$summaryPath = Join-Path $runDir 'summary.json'
$artifactRootPath = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot 'TestResults\Playwright\docker-http'))
$latestPointerAbsolutePath = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot 'TestResults\Playwright\docker-http\latest-playwright-smoke.txt'))
$environmentPointerAbsolutePath = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot 'TestResults\Playwright\docker-http\latest-playwright-docker-http.txt'))

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
Set-Content -Path $latestPointerPath -Value "$runDir" -Encoding utf8
Set-Content -Path $environmentPointerPath -Value "$runDir" -Encoding utf8
Set-Content -Path $rootMarkerPath -Value "$runDir" -Encoding utf8

$runPlanPath = Join-Path $runDir 'run-plan.txt'
$startupLogPath = Join-Path $runDir 'startup.log'
$progressLogPath = Join-Path $runDir 'progress.log'
Set-Content -Path $runPlanPath -Value @(
    'Docker dev HTTP smoke run',
    'Goal: confirm the Docker HTTP browser bootstrap path is healthy.',
    'Stages:',
    '1. Wait for API and UI endpoints to be ready.',
    '2. Stabilize the environment.',
    '3. Run the tenant bootstrap smoke flow.',
    '4. Write summary.json and update latest pointers.'
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Smoke startup`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "Smoke progress log initialized.`n" -Encoding utf8

if (-not (Test-Path $playwrightScript)) {
    throw "Playwright smoke script not found: $playwrightScript"
}

Write-Host "Waiting for Docker dev HTTP endpoints before Playwright run..."
Add-Content -Path $startupLogPath -Value "Waiting for Docker dev HTTP endpoints before Playwright run."
Add-Content -Path $progressLogPath -Value "Waiting for Docker dev HTTP endpoints before Playwright run."

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
                Add-Content -Path $progressLogPath -Value "Endpoint ready: $Url"
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url"
}

Wait-ForHttpOk -Url 'http://localhost:5020/health/ready' -TimeoutSeconds 300
Wait-ForHttpOk -Url 'http://localhost:5022/' -TimeoutSeconds 300

Write-Host "Stabilizing for $StabilizationDelaySeconds seconds before browser automation."
Add-Content -Path $startupLogPath -Value "Stabilizing for $StabilizationDelaySeconds seconds before browser automation."
Add-Content -Path $progressLogPath -Value "Stabilizing for $StabilizationDelaySeconds seconds before browser automation."
Start-Sleep -Seconds $StabilizationDelaySeconds

$arguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    $playwrightScript
    '-Target'
    'docker-dev-http'
    '--artifact-root'
    $artifactRootPath
    '--latest-pointer-path'
    $latestPointerAbsolutePath
)

if ($InstallBrowser) {
    $arguments += '-InstallBrowser'
}

$outputPath = Join-Path $runDir 'playwright.log'
$summary = [ordered]@{
    target = 'docker-dev-http'
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    status = 'running'
    runDir = $runDir
    latestPointerPath = $latestPointerPath
}

try {
    Add-Content -Path $progressLogPath -Value "Starting smoke execution."
    & pwsh @arguments 2>&1 | Tee-Object -FilePath $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Docker dev HTTP smoke failed with exit code $LASTEXITCODE"
    }

    $summary.status = 'passed'
    Add-Content -Path $progressLogPath -Value "Smoke execution completed successfully."
}
catch {
    $summary.status = 'failed'
    Add-Content -Path $progressLogPath -Value "Smoke execution failed: $($_.Exception.Message)"
    throw
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value "$runDir" -Encoding utf8
    Set-Content -Path $environmentPointerPath -Value "$runDir" -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value "$runDir" -Encoding utf8
}

exit $LASTEXITCODE
