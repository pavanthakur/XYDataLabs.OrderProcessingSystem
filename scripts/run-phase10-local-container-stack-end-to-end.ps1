#Requires -Version 7.0

param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_endtoend"
$runDir = Join-Path $logRoot $runStamp
$summaryPath = Join-Path $runDir 'summary.json'
$startupLogPath = Join-Path $runDir '00-end-to-end.log'
$progressLogPath = Join-Path $runDir 'progress.log'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-full-validation.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 local container stack end-to-end run',
    'Goal: validate the already-started Phase 10 local container stack and clean it up afterwards.',
    'Stages:',
    '1. Confirm gateway and UI readiness.',
    '2. Run smoke validation.',
    '3. Run integration suite.',
    '4. Run payment matrix.',
    '5. Tear down the compose stack and remove the Phase 10 images.',
    '6. Write summary.json and update latest pointers.'
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 end-to-end wrapper started`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "Phase 10 end-to-end progress log initialized.`n" -Encoding utf8

function Write-ProgressLine {
    param([Parameter(Mandatory = $true)][string]$Message)

    Add-Content -Path $progressLogPath -Value "[$(Get-Date -Format o)] $Message"
    Write-Host $Message
}

function Assert-DockerAvailable {
    try {
        & docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker is not available."
        }
    }
    catch {
        throw 'Docker Desktop is not running or the Docker engine is unavailable. Start Docker Desktop and retry the Phase 10 local container stack task.'
    }
}

function Wait-ForUrl {
    param(
        [Parameter(Mandatory = $true)]
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
        }
        catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url after $TimeoutSec seconds."
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Script
    )

    $logPath = Join-Path $runDir (($Name -replace '[^a-z0-9-]+', '-').ToLowerInvariant() + '.log')
    Write-ProgressLine "Running $Name..."
    try {
        & $Script 2>&1 | Tee-Object -FilePath $logPath
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE"
        }
        Write-ProgressLine "$Name passed."
        return $true
    }
    catch {
        Write-ProgressLine "$Name failed: $($_.Exception.Message)"
        throw
    }
}

$summary = [ordered]@{
    target = 'phase10-docker-http'
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    status = 'running'
    runDir = $runDir
    latestPointerPath = $latestPointerPath
    steps = @()
}
$runFailed = $false
$dockerAvailable = $false

try {
    Assert-DockerAvailable
    $dockerAvailable = $true
    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec 300
    $summary.steps += [ordered]@{
        name = 'readiness'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($startupLogPath)
    }

    Start-Sleep -Seconds $StabilizationDelaySeconds

    Invoke-LoggedCommand -Name 'smoke' -Script {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts\run-phase10-docker-dev-smoke.ps1') -StabilizationDelaySeconds $StabilizationDelaySeconds
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'smoke'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'run-phase10-docker-dev-smoke.log'
    }

    Invoke-LoggedCommand -Name 'integration' -Script {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts\run-integration-tests-docker.ps1')
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'integration'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'run-integration-tests-docker.log'
    }

    Invoke-LoggedCommand -Name 'matrix' -Script {
        npm --prefix (Join-Path $workspaceRoot 'automation') run run:docker:dev:http:playwright-matrix
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'matrix'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'npm-run-docker-dev-http-playwright-matrix.log'
    }
}
catch {
    $runFailed = $true
    $summary.steps += [ordered]@{
        name = 'failure'
        status = 'failed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'progress.log'
        error = $_.Exception.Message
    }
    throw
}
finally {
    try {
        if ($dockerAvailable) {
            Write-ProgressLine 'Running cleanup for Phase 10 local container stack...'
            & docker compose -f $composeFile --profile apps down -v 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log') | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Docker compose down failed with exit code $LASTEXITCODE"
            }

            $images = @(
                'ghcr.io/pavanthakur/orderprocessing-gateway:dev',
                'ghcr.io/pavanthakur/orderprocessing-orders:dev',
                'ghcr.io/pavanthakur/orderprocessing-inventory:dev',
                'ghcr.io/pavanthakur/orderprocessing-notifications:dev',
                'ghcr.io/pavanthakur/orderprocessing-ui:dev'
            )

            foreach ($image in $images) {
                $imageId = docker images -q $image 2>$null
                if ($imageId) {
                    docker rmi -f $image | Out-Null
                    Write-ProgressLine "Removed image $image"
                }
                else {
                    Write-ProgressLine "Image not found: $image"
                }
            }
        }
        else {
            Write-ProgressLine 'Skipping cleanup because Docker was unavailable.'
        }
        $summary.steps += [ordered]@{
            name = 'cleanup'
            status = 'passed'
            startedUtc = (Get-Date).ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            log = 'docker-compose-down.log'
        }
    }
    catch {
        $runFailed = $true
        $summary.steps += [ordered]@{
            name = 'cleanup'
            status = 'failed'
            startedUtc = (Get-Date).ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            log = 'docker-compose-down.log'
            error = $_.Exception.Message
        }
        Write-ProgressLine "Cleanup failed: $($_.Exception.Message)"
    }

    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.status = if ($runFailed) { 'failed' } else { 'passed' }
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
}
