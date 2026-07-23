#Requires -Version 7.0

param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [switch]$InfrastructureOnly,

    [switch]$IncludeMessaging
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
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
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null

$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 local container stack readiness run',
    'Goal: confirm Docker Desktop is available and the started Phase 10 stack is ready.',
    'Stages:',
    '1. Confirm Docker engine availability.',
    '2. Validate Docker Compose config.',
    '3. Wait for SQL, Redis, Keycloak, and Azurite readiness.',
    '4. Wait for Service Bus emulator when selected.',
    '5. Wait for gateway and UI unless this is infrastructure-only.',
    '6. Stabilize the stack.',
    '7. Write summary.json and update latest pointers.'
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
            $response = Invoke-WebRequest -UseBasicParsing -SkipHttpErrorCheck -Uri $Url -TimeoutSec 5
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

function Wait-ForTcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutSec = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connectTask = $client.ConnectAsync($HostName, $Port)
            if ($connectTask.Wait([TimeSpan]::FromSeconds(5)) -and $client.Connected) {
                return
            }
        }
        catch {
        }
        finally {
            $client.Dispose()
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for TCP $HostName`:$Port after $TimeoutSec seconds."
}

function Invoke-ComposeConfigValidation {
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "Docker env file not found: $envFile. Copy Resources/Docker/.env.local.example to .env.local and set local-only values."
    }

    & docker compose --env-file $envExampleFile --env-file $envFile -f $composeFile --profile data --profile identity --profile storage --profile apps config --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose config validation failed for $composeFile."
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

try {
    Assert-DockerAvailable
    $summary.steps += [ordered]@{
        name = 'docker-preflight'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($startupLogPath)
    }

    Write-ProgressLine 'Validating Docker Compose config...'
    Invoke-ComposeConfigValidation
    $summary.steps += [ordered]@{
        name = 'compose-config'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($progressLogPath)
    }

    Write-ProgressLine 'Waiting for SQL, Redis, Keycloak, and Azurite readiness...'
    Wait-ForTcpPort -HostName 'localhost' -Port 1433 -TimeoutSec 300
    Wait-ForTcpPort -HostName 'localhost' -Port 6379 -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:8081/' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:10000/' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:10001/' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:10002/' -TimeoutSec 300

    if ($IncludeMessaging) {
        Write-ProgressLine 'Waiting for Service Bus emulator readiness...'
        Wait-ForTcpPort -HostName 'localhost' -Port 5672 -TimeoutSec 300
        Wait-ForUrl -Url 'http://localhost:5300/health' -TimeoutSec 300
    }

    if (-not $InfrastructureOnly) {
        Write-ProgressLine 'Waiting for gateway and UI readiness...'
        Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec 300
        Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec 300
    }

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
    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
}
