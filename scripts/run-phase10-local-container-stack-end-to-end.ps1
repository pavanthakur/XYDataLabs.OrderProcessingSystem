#Requires -Version 7.0

param(
    [ValidateRange(30, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$IntegrationConsoleVerbosity = 'minimal',

    [switch]$CleanupOnExit,

    [switch]$RemoveVolumes,

    [switch]$RemoveImages
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$runDir = if ([string]::IsNullOrWhiteSpace($env:PHASE10_RUN_ROOT)) {
    Join-Path $logRoot "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')_endtoend"
}
else {
    $env:PHASE10_RUN_ROOT
}
$summaryPath = Join-Path $runDir 'e2e-summary.json'
$diagnosticsPath = Join-Path $runDir 'diagnostics.json'
$startupLogPath = Join-Path $runDir '00-end-to-end.log'
$progressLogPath = Join-Path $runDir 'progress.log'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-full-validation.txt'
$latestFailurePointerPath = Join-Path $logRoot 'latest-playwright-failure.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null

$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'end-to-end-run-plan.txt') -Value @(
    'Phase 10 local container stack end-to-end run',
    'Goal: validate the already-started Phase 10 local container stack and clean it up afterwards.',
    'Stages:',
    '1. Confirm gateway and UI readiness.',
    '2. Run smoke validation.',
    '3. Run integration suite.',
    '4. Run payment matrix.',
    '5. Preserve the stack by default so NFR and rollback proof can run.',
    '6. Tear down only when CleanupOnExit is explicitly selected.',
    '7. Write summary.json and update latest pointers.'
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
        $output = & docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }
    }
    catch {
        throw "Docker Desktop is not running or the Docker engine is unavailable. Start Docker Desktop and retry the Phase 10 local container stack task. Details: $($_.Exception.Message)"
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
        log = 'smoke.log'
    }

    Invoke-LoggedCommand -Name 'integration-prep' -Script {
        dotnet build-server shutdown
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'integration-prep'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'integration-prep.log'
    }

    Invoke-LoggedCommand -Name 'integration' -Script {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts\run-integration-tests-docker.ps1') -ConsoleVerbosity $IntegrationConsoleVerbosity
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'integration'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'integration.log'
    }

    Invoke-LoggedCommand -Name 'matrix' -Script {
        npm --prefix (Join-Path $workspaceRoot 'automation') run run:docker:dev:http:playwright-matrix
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'matrix'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'matrix.log'
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
        if ($dockerAvailable -and $CleanupOnExit) {
            Write-ProgressLine 'Running cleanup for Phase 10 local container stack...'
            $downArguments = @(
                'compose',
                '--env-file', $envExampleFile,
                '--env-file', $envFile,
                '-f', $composeFile,
                '--profile', 'data',
                '--profile', 'identity',
                '--profile', 'storage',
                '--profile', 'messaging',
                '--profile', 'apps',
                '--profile', 'functions',
                'down',
                '--remove-orphans'
            )
            if ($RemoveVolumes) {
                $downArguments += '--volumes'
            }
            & docker @downArguments 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log') | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Docker compose down failed with exit code $LASTEXITCODE"
            }

            if ($RemoveImages) {
                $imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER }
                $imageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG }
                $images = @(
                    "ghcr.io/$imageOwner/orderprocessing-gateway:$imageTag",
                    "ghcr.io/$imageOwner/orderprocessing-orders:$imageTag",
                    "ghcr.io/$imageOwner/orderprocessing-payments:$imageTag",
                    "ghcr.io/$imageOwner/orderprocessing-inventory:$imageTag",
                    "ghcr.io/$imageOwner/orderprocessing-notifications:$imageTag",
                    "ghcr.io/$imageOwner/orderprocessing-ui:$imageTag"
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
        }
        elseif ($dockerAvailable) {
            Write-ProgressLine 'Preserving the running stack, volumes, and image tags for NFR/rollback proof.'
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
    finally {
        if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
            Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
        }
        else {
            $env:DOCKER_CONFIG = $previousDockerConfig
        }
    }

    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.status = if ($runFailed) { 'failed' } else { 'passed' }
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    $diagnostics = [ordered]@{
        target = $summary.target
        mode = 'endtoend'
        status = $summary.status
        startedUtc = $summary.startedUtc
        finishedUtc = $summary.finishedUtc
        runDir = $runDir
        summaryPath = $summaryPath
        logs = [ordered]@{
            startup = $startupLogPath
            progress = $progressLogPath
            smoke = Join-Path $runDir 'smoke.log'
            integrationPrep = Join-Path $runDir 'integration-prep.log'
            integration = Join-Path $runDir 'integration.log'
            integrationDetails = Join-Path $runDir 'integration'
            matrix = Join-Path $runDir 'matrix.log'
            cleanup = Join-Path $runDir 'docker-compose-down.log'
        }
        latestPointers = [ordered]@{
            run = $rootMarkerPath
            fullValidation = $latestPointerPath
            failure = $latestFailurePointerPath
        }
        failure = if ($runFailed) {
            [ordered]@{
                step = ($summary.steps | Where-Object { $_.name -eq 'failure' } | Select-Object -First 1)
                note = 'See the integration log and the step log path recorded in the step details.'
            }
        } else {
            $null
        }
    }
    Set-Content -Path $diagnosticsPath -Value ($diagnostics | ConvertTo-Json -Depth 8) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    if ($runFailed) {
        Set-Content -Path $latestFailurePointerPath -Value $runDir -Encoding utf8
    }
    Write-Host "Phase 10 Docker end-to-end run directory: $runDir" -ForegroundColor Cyan
    Write-Host "Phase 10 Docker end-to-end diagnostics: $diagnosticsPath" -ForegroundColor Cyan
    if ($runFailed) {
        Write-Host "Phase 10 Docker end-to-end latest failure pointer: $latestFailurePointerPath" -ForegroundColor Yellow
    }
}
