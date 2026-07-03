param(
    [ValidateSet('up', 'down')]
    [string]$Action = 'up',

    [ValidateSet('apps', 'all')]
    [string]$Profile = 'apps',

    [ValidateRange(60, 900)]
    [int]$HealthTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-profile.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_profile"
$runDir = Join-Path $logRoot $runStamp
$startupLogPath = Join-Path $runDir '00-start-profile.log'
$progressLogPath = Join-Path $runDir '01-env-ready.log'
$summaryPath = Join-Path $runDir 'summary.json'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 local container stack run',
    'Goal: start the Phase 10 local container stack with SQL and Redis.',
    'Stages:',
    '1. Bring up the compose stack.',
    '2. Wait Ready + Keycloak.',
    '3. Write summary.json and update latest pointers.'
) -Encoding utf8
    Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 Docker profile startup`n" -Encoding utf8
    Set-Content -Path $progressLogPath -Value "Phase 10 Docker profile readiness log initialized.`n" -Encoding utf8

if (-not (Test-Path $composeFile)) {
    throw "Compose file not found: $composeFile"
}

function Wait-ForUrl {
    param(
        [string]$Url,
        [int]$TimeoutSec
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

    throw "Timed out waiting for $Url after $TimeoutSec seconds."
}

function Stop-ContainersOnPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $containers = & docker ps --filter "publish=$Port" --format '{{.ID}} {{.Names}}'
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect Docker containers on port $Port."
    }

    if ([string]::IsNullOrWhiteSpace($containers)) {
        return
    }

    foreach ($line in $containers -split "`r?`n") {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $containerId = ($line -split '\s+')[0]
        Add-Content -Path $progressLogPath -Value "Stopping container on port ${Port}: $line"
        & docker stop $containerId 2>&1 | Tee-Object -FilePath (Join-Path $runDir "docker-stop-$Port.log") | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stop Docker container $containerId on port $Port."
        }
    }
}

Push-Location $workspaceRoot
try {
    $summary = [ordered]@{
        target = 'phase10-docker-http'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = $null
        status = 'running'
        runDir = $runDir
        latestPointerPath = $latestPointerPath
    }

    if ($Action -eq 'down') {
        Add-Content -Path $progressLogPath -Value 'Stopping Phase 10 local container stack.'
        & docker compose --env-file $envFile -f $composeFile --profile $Profile down -v 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Docker compose down failed with exit code $LASTEXITCODE"
        }

        $summary.status = 'passed'
        return
    }

    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local container stack.'
    foreach ($port in @(8081, 1433, 6379, 5022)) {
        Stop-ContainersOnPort -Port $port
    }
    & docker compose --env-file $envFile -f $composeFile --profile $Profile down -v 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-preflight-down.log') | Out-Null
    & docker compose --env-file $envFile -f $composeFile --profile $Profile up -d --build 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose up failed with exit code $LASTEXITCODE"
    }

    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec $HealthTimeoutSec

    Add-Content -Path $progressLogPath -Value 'Phase 10 local container stack is ready.'
    Write-Host 'Phase 10 local container stack is ready.'
    Write-Host 'Gateway: http://localhost:5080'
    Write-Host 'UI:      http://localhost:5022'
    Write-Host 'Orders:  http://localhost:5081'
    Write-Host 'Inventory: http://localhost:5082'
    Write-Host 'Notifications: http://localhost:5083'
    $summary.status = 'passed'
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    Pop-Location
}
