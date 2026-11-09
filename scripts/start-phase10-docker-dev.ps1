#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('up', 'down')]
    [string]$Action = 'up',

    [ValidateSet('apps', 'infrastructure', 'messaging')]
    [string]$Profile = 'apps',

    [ValidateRange(60, 900)]
    [int]$HealthTimeoutSec = 300,

    [switch]$CleanImages,

    [switch]$RemoveVolumes,

    [switch]$ResetData,

    [switch]$ColdBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
if ($CleanImages) { throw '-CleanImages is retired: use an explicit reviewed image cleanup after stopping the stack. It is not a storage reset.' }
if ($RemoveVolumes) { throw '-RemoveVolumes is retired. Use -ResetData with confirmation for a project-scoped reset.' }
if ($WhatIfPreference) { Write-Host "Would $Action project xy-phase10 (reset data: $ResetData). No changes made."; return }
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$tenantBootstrapContractPath = Join-Path $workspaceRoot 'Resources\Configuration\tenant-bootstrap.local.json'
if (-not (Test-Path -LiteralPath $tenantBootstrapContractPath)) { throw 'Local tenant bootstrap contract is missing.' }
$tenantBootstrapContract = Get-Content -LiteralPath $tenantBootstrapContractPath -Raw | ConvertFrom-Json
if ($tenantBootstrapContract.schemaVersion -ne 1 -or $tenantBootstrapContract.scope -ne 'docker-dev' -or $tenantBootstrapContract.seedPolicy -ne 'missing-only' -or $null -eq $tenantBootstrapContract.providerDefaults.OpenPay.use3DSecure) { throw 'Local tenant bootstrap contract is invalid.' }
$contractOpenPayThreeDsDefault = ([bool]$tenantBootstrapContract.providerDefaults.OpenPay.use3DSecure).ToString().ToLowerInvariant()
$previousOpenPayThreeDsDefault = [Environment]::GetEnvironmentVariable('PHASE10_OPENPAY_3DS_DEFAULT')
Initialize-Phase10LogRedaction -Settings (Get-Phase10LocalSettings -Path $envFile)
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-profile.txt'
$latestFailurePointerPath = Join-Path $logRoot 'latest-playwright-failure.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runDir = if ([string]::IsNullOrWhiteSpace($env:PHASE10_RUN_ROOT)) {
    Join-Path $logRoot "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')_profile"
}
else {
    $env:PHASE10_RUN_ROOT
}
$startupLogPath = Join-Path $runDir '00-start-profile.log'
$progressLogPath = Join-Path $runDir '01-env-ready.log'
$summaryPath = Join-Path $runDir 'profile-summary.json'
$diagnosticsPath = Join-Path $runDir 'profile-diagnostics.json'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'profile-run-plan.txt') -Value @(
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

function Assert-DockerAvailable {
    Assert-Phase10LocalDockerEndpoint
    try {
        $output = & docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }
    }
    catch {
        throw "Docker Desktop is not reachable from this shell. Start Docker Desktop, make sure this Windows user can access the Docker engine, then rerun the Phase 10 clean Azure-parity hook. Details: $($_.Exception.Message)"
    }
}

function Wait-ForUrl {
    param(
        [string]$Url,
        [int]$TimeoutSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -SkipHttpErrorCheck -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url after $TimeoutSec seconds."
}

function Wait-ForSuccessfulUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSec = 300,

        [string]$ContainsText
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -SkipHttpErrorCheck -Uri $Url -TimeoutSec 5
            $content = [string]$response.Content
            $containsExpectedText = [string]::IsNullOrWhiteSpace($ContainsText) -or $content.Contains($ContainsText, [StringComparison]::OrdinalIgnoreCase)
            if ($response.StatusCode -eq 200 -and $containsExpectedText) {
                return
            }
        }
        catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for successful response from $Url after $TimeoutSec seconds."
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


function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $effectiveSettings = Get-Phase10LocalSettings -Path $envFile
    return $effectiveSettings[$Name]
}

function Get-ComposeEnvArguments {
    $arguments = @()
    if (Test-Path -LiteralPath $envExampleFile) {
        $arguments += @('--env-file', $envExampleFile)
    }

    if (Test-Path -LiteralPath $envFile) {
        $arguments += @('--env-file', $envFile)
    }

    return $arguments
}

function Get-ComposeProfileArguments {
    $profiles = switch ($Profile) {
        'infrastructure' { @('data', 'identity', 'storage') }
        'messaging' { @('data', 'identity', 'storage', 'messaging') }
        default {
            $selectedProfiles = @('data', 'identity', 'storage', 'apps')
            if ((Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
                $selectedProfiles += 'messaging'
            }

            $selectedProfiles
        }
    }

    $arguments = @()
    foreach ($selectedProfile in $profiles) {
        $arguments += @('--profile', $selectedProfile)
    }

    return $arguments
}


function Escape-SqlLiteral {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return $Value.Replace("'", "''")
}


function Assert-Phase10RedisAzureParity {
    Write-Host 'Validating Phase 10 local Redis parity...' -ForegroundColor Cyan
    $composeProfileArgs = Get-ComposeProfileArguments
    $composeEnvArgs = Get-ComposeEnvArguments
    $output = & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs exec -T redis redis-cli ping 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Redis readiness check failed. $([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() })))"
    }

    $response = ([string]::Join('', @($output | ForEach-Object { $_.ToString() }))).Trim()
    if ($response -ne 'PONG') {
        throw "Redis readiness check returned '$response' instead of PONG."
    }

    Add-Content -Path $progressLogPath -Value 'Verified Redis readiness: PONG'
}

function Ensure-Phase10Databases {
    Write-Host 'Ensuring Phase 10 local SQL databases exist...' -ForegroundColor Cyan

    foreach ($databaseName in (Get-Phase10Databases)) {
        $query = @"
IF DB_ID(N'$databaseName') IS NULL
BEGIN
    CREATE DATABASE [$databaseName];
END
"@

        Invoke-Phase10SqlCmdInComposeContainer -Database 'master' -Query $query | Out-Null
        Add-Content -Path $progressLogPath -Value "Ensured database exists: $databaseName"
    }
}

Push-Location $workspaceRoot
try {
    if ($Action -eq 'up') { $env:PHASE10_OPENPAY_3DS_DEFAULT = $contractOpenPayThreeDsDefault }
    $summary = [ordered]@{
        target = 'phase10-docker-http'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = $null
        status = 'running'
        runDir = $runDir
        latestPointerPath = $latestPointerPath
    }

    if ($Action -eq 'down') {
        Assert-DockerAvailable
        Add-Content -Path $progressLogPath -Value 'Stopping Phase 10 local container stack.'
        $composeProfileArgs = Get-ComposeProfileArguments
        $composeEnvArgs = Get-ComposeEnvArguments
        $downArguments = @('down')
        if ($ResetData) {
            Confirm-Phase10Reset -Approve { $PSCmdlet.ShouldProcess('xy-phase10 containers and named SQL/Azurite volumes', 'Permanently reset local trial data') }
            Assert-Phase10VolumeOwnership
            $downArguments += '--volumes'
        }
        $downArguments += '--remove-orphans'
        & docker compose @composeEnvArgs -f $composeFile --profile '*' @downArguments 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Docker compose down failed with exit code $LASTEXITCODE"
        }

        $summary.status = 'passed'
        return
    }

    Assert-DockerAvailable
    Assert-Phase10StorageCapacity -Path (Get-Phase10DockerDiskLocation) -ForBuild | Out-Null
    $localSettings = Get-Phase10LocalSettings -Path $envFile
    Assert-Phase10LocalSettings -Settings $localSettings -FullStack:((Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true' -or $Profile -eq 'messaging')
    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local container stack.'
    $requiredPorts = @(8081, (Get-Phase10SqlHostPort), 6379, 5022, 5080, 5081, 5082, 5083, 5084, 10000, 10001, 10002)
    if ((Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true' -or $Profile -eq 'messaging') { $requiredPorts += @(5672, 5300, 5085) }
    Assert-Phase10PortOwnership -Ports $requiredPorts
    $composeProfileArgs = Get-ComposeProfileArguments
    $composeEnvArgs = Get-ComposeEnvArguments
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs config --quiet 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-config.log') | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose config validation failed with exit code $LASTEXITCODE"
    }

    if ($ColdBuild) {
        $rollbackImages = @()
        foreach ($service in @('orders', 'payments', 'inventory', 'notifications', 'gateway', 'ui', 'functions', 'azurite')) {
            $containerIds = @(& docker ps -a --filter 'label=com.docker.compose.project=xy-phase10' --filter "label=com.docker.compose.service=$service" -q)
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect current project image references before cold build.' }
            foreach ($containerId in $containerIds) {
                $imageId = [string](& docker inspect --format '{{.Image}}' $containerId)
                if ($LASTEXITCODE -ne 0 -or -not $imageId) { throw "Could not record the current $service rollback image." }
                $rollbackImages += [ordered]@{ service = $service; id = $imageId.Trim() }
            }
        }
        $rollbackPath = Join-Path $runDir 'rollback-images.json'
        Set-Content -LiteralPath $rollbackPath -Value (@{ capturedUtc = [DateTime]::UtcNow.ToString('o'); images = $rollbackImages } | ConvertTo-Json -Depth 5) -Encoding utf8
        Add-Content -Path $progressLogPath -Value "Recorded $($rollbackImages.Count) pre-cold-build project container image IDs for rollback protection."
    }
    if ($ResetData) {
        Confirm-Phase10Reset -Approve { $PSCmdlet.ShouldProcess('xy-phase10 containers and named SQL/Azurite volumes', 'Permanently reset local trial data') }
        Assert-Phase10VolumeOwnership
        & docker compose @composeEnvArgs -f $composeFile --profile '*' down --volumes --remove-orphans 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-reset.log') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Project reset failed; refusing to rebuild.' }
    }
    $platformServices = @('sql-server', 'redis', 'keycloak-local', 'azurite')
    if ($Profile -eq 'messaging' -or (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        $platformServices += @('servicebus-sql', 'servicebus-emulator')
    }

    $buildArgs = @('build')
    if ($ColdBuild) { $buildArgs += '--no-cache' }
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs @buildArgs azurite 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-azurite-build.log') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Local Azurite build failed; no cached-image fallback is permitted.' }
    if ($ColdBuild) {
        & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs --profile functions build --no-cache orders payments inventory notifications gateway ui functions 2>&1 |
            Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-apps-build.log') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cold application/Functions image build failed; startup will not fall back to existing images.' }
    }
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs up -d @platformServices 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-platform-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose platform dependency startup failed with exit code $LASTEXITCODE"
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'invoke-phase10-database-bootstrap.ps1') `
        -Profile $Profile `
        -NoBuild:$ColdBuild `
        -RunDir $runDir `
        -ProgressLogPath $progressLogPath 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'phase10-database-bootstrap.log') | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Phase 10 database bootstrap failed with exit code $LASTEXITCODE."
    }

    Assert-Phase10RedisAzureParity
    Wait-ForUrl -Url 'http://localhost:8081/' -TimeoutSec $HealthTimeoutSec
    & (Join-Path $PSScriptRoot 'sync-local-identity.ps1') -Project xy-phase10
    Wait-ForUrl -Url 'http://localhost:10000/' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:10001/' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:10002/' -TimeoutSec $HealthTimeoutSec

    if ($Profile -eq 'infrastructure' -or $Profile -eq 'messaging') {
        Add-Content -Path $progressLogPath -Value "Phase 10 local container infrastructure profile '$Profile' is ready."
        Write-Host "Phase 10 local container infrastructure profile '$Profile' is ready."
        $summary.status = 'passed'
        return
    }

    if ($Profile -eq 'messaging' -or (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        Wait-ForTcpPort -HostName 'localhost' -Port 5672 -TimeoutSec $HealthTimeoutSec
        Wait-ForUrl -Url 'http://localhost:5300/health' -TimeoutSec $HealthTimeoutSec
    }

    Add-Content -Path $progressLogPath -Value 'Starting application service image startup.'
    $appUpArguments = @('up', '-d')
    if ($ColdBuild) { $appUpArguments += '--no-build' } else { $appUpArguments += '--build' }
    $appUpArguments += @('orders', 'payments', 'inventory', 'notifications', 'gateway', 'ui')
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs @appUpArguments 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-apps-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose app startup failed with exit code $LASTEXITCODE"
    }
    if ((Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        $functionsLogPath = Join-Path $runDir 'docker-compose-functions-up.log'
        $functionsExitCode = 1
        foreach ($attempt in 1..3) {
            $functionUpArguments = @('up', '-d')
            if ($ColdBuild) { $functionUpArguments += '--no-build' } else { $functionUpArguments += '--build' }
            $functionUpArguments += 'functions'
            & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs --profile functions @functionUpArguments 2>&1 | Protect-Phase10Log |
                Tee-Object -FilePath $functionsLogPath -Append
            $functionsExitCode = $LASTEXITCODE
            if ($functionsExitCode -eq 0) { break }
            if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
        }
        if ($functionsExitCode -ne 0) { throw 'Functions build/start failed after 3 attempts. No stale-image fallback is permitted.' }
    }

    Add-Content -Path $progressLogPath -Value 'Waiting for application readiness URLs.'
    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5081/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5084/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec $HealthTimeoutSec
    Wait-ForSuccessfulUrl -Url 'http://localhost:5081/api/v1/Info/runtime-configuration' -TimeoutSec $HealthTimeoutSec -ContainsText 'activeTenantCode'
    Wait-ForSuccessfulUrl -Url 'http://localhost:5080/api/v1/Info/runtime-configuration' -TimeoutSec $HealthTimeoutSec -ContainsText 'activeTenantCode'

    Add-Content -Path $progressLogPath -Value 'Phase 10 local container stack is ready.'
    Write-Host 'Phase 10 local container stack is ready.'
    Write-Host 'Gateway: http://localhost:5080'
    Write-Host 'UI:      http://localhost:5022'
    Write-Host 'Orders:  http://localhost:5081'
    Write-Host 'Inventory: http://localhost:5082'
    Write-Host 'Notifications: http://localhost:5083'
    Write-Host 'Payments: http://localhost:5084'
    $summary.status = 'passed'
}
catch {
    $summary.status = 'failed'
    Set-Content -Path $latestFailurePointerPath -Value $runDir -Encoding utf8
    throw
}
finally {
    if ($null -eq $previousOpenPayThreeDsDefault) { Remove-Item Env:PHASE10_OPENPAY_3DS_DEFAULT -ErrorAction SilentlyContinue }
    else { $env:PHASE10_OPENPAY_3DS_DEFAULT = $previousOpenPayThreeDsDefault }
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
    $diagnostics = [ordered]@{
        target = $summary.target
        mode = 'profile'
        status = $summary.status
        startedUtc = $summary.startedUtc
        finishedUtc = $summary.finishedUtc
        runDir = $runDir
        summaryPath = $summaryPath
        logs = [ordered]@{
            startup = $startupLogPath
            progress = $progressLogPath
            composePlatformUp = Join-Path $runDir 'docker-compose-platform-up.log'
            composeAppsUp = Join-Path $runDir 'docker-compose-apps-up.log'
            composeDown = Join-Path $runDir 'docker-compose-down.log'
        }
        latestPointers = [ordered]@{
            run = $rootMarkerPath
            profile = $latestPointerPath
            failure = $latestFailurePointerPath
        }
    }
    Set-Content -Path $diagnosticsPath -Value ($diagnostics | ConvertTo-Json -Depth 6) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    if ($summary.status -eq 'failed') {
        Set-Content -Path $latestFailurePointerPath -Value $runDir -Encoding utf8
    }
    Write-Host "Phase 10 Docker profile run directory: $runDir" -ForegroundColor Cyan
    Write-Host "Phase 10 Docker profile diagnostics: $diagnosticsPath" -ForegroundColor Cyan
    if ($summary.status -eq 'failed') {
        Write-Host "Phase 10 Docker profile latest failure pointer: $latestFailurePointerPath" -ForegroundColor Yellow
    }
    Pop-Location
}
