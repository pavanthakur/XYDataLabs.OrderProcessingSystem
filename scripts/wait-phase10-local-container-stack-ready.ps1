#Requires -Version 7.0

param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_profile"
$runDir = Join-Path $logRoot $runStamp
$startupLogPath = Join-Path $runDir '01-env-ready.log'
$progressLogPath = Join-Path $runDir '01-env-ready.log'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-profile.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 local container stack readiness run',
    'Goal: confirm Docker Desktop is available and the started stack is ready, including Keycloak.',
    'Stages:',
    '1. Confirm Docker engine availability.',
    '2. Wait for gateway, UI, and Keycloak readiness.',
    '3. Stabilize the stack.',
    '4. Write summary.json and update latest pointers.'
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 env-ready check started`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "Phase 10 env-ready progress log initialized.`n" -Encoding utf8

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
        throw 'Docker Desktop is not running or the Docker engine is unavailable. Start Docker Desktop and retry the Phase 10 env-ready task.'
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

try {
    Assert-DockerAvailable
    $summary.steps += [ordered]@{
        name = 'docker-preflight'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($startupLogPath)
    }

    Write-ProgressLine 'Waiting for gateway, UI, and Keycloak readiness...'
    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:8081/health/ready' -TimeoutSec 300
    $summary.steps += [ordered]@{
        name = 'readiness'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($progressLogPath)
    }

    Start-Sleep -Seconds $StabilizationDelaySeconds
    $summary.steps += [ordered]@{
        name = 'stabilization'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($progressLogPath)
        delaySeconds = $StabilizationDelaySeconds
    }

    $summary.status = 'passed'
    Write-ProgressLine 'Phase 10 local container stack is ready.'
}
catch {
    $runFailed = $true
    $summary.steps += [ordered]@{
        name = 'failure'
        status = 'failed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($progressLogPath)
        error = $_.Exception.Message
    }
    Write-ProgressLine "Env-ready check failed: $($_.Exception.Message)"
    throw
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.status = if ($runFailed) { 'failed' } else { 'passed' }
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
}
