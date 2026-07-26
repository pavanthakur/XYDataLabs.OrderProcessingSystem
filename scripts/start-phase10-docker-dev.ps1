param(
    [ValidateSet('up', 'down')]
    [string]$Action = 'up',

    [ValidateSet('apps', 'infrastructure', 'messaging')]
    [string]$Profile = 'apps',

    [ValidateRange(60, 900)]
    [int]$HealthTimeoutSec = 300,

    [switch]$CleanImages,

    [switch]$RemoveVolumes
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
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
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null

$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot
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
        $containerName = ($line -split '\s+', 2)[1]
        $stopLogPath = Join-Path $runDir "docker-stop-$Port.log"
        Add-Content -Path $progressLogPath -Value "Stopping container on port ${Port}: $line"
        & docker stop -t 30 $containerId 2>&1 | Tee-Object -FilePath $stopLogPath -Append | Out-Null
        $stopExitCode = $LASTEXITCODE

        $remainingContainer = & docker ps -a --filter "id=$containerId" --format '{{.ID}}'
        if ($stopExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remainingContainer)) {
            Add-Content -Path $progressLogPath -Value "docker stop did not fully clear $containerName on port ${Port}; attempting docker kill."
            & docker kill $containerId 2>&1 | Tee-Object -FilePath $stopLogPath -Append | Out-Null
            $killExitCode = $LASTEXITCODE
            $remainingContainer = & docker ps -a --filter "id=$containerId" --format '{{.ID}}'

            if ($killExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remainingContainer)) {
                Add-Content -Path $progressLogPath -Value "docker kill did not fully clear $containerName on port ${Port}; attempting docker rm -f."
                & docker rm -f $containerId 2>&1 | Tee-Object -FilePath $stopLogPath -Append | Out-Null
                $removeExitCode = $LASTEXITCODE
                $remainingContainer = & docker ps -a --filter "id=$containerId" --format '{{.ID}}'

                if ($removeExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remainingContainer)) {
                    throw "Failed to stop Docker container $containerId on port $Port."
                }
            }
        }
    }
}

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
    }

    if (-not (Test-Path $envFile)) {
        return $null
    }

    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
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

function Remove-Phase10LocalImages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageTag
    )

    $imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER }
    $imageNames = @(
        "ghcr.io/$imageOwner/orderprocessing-orders:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-payments:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-inventory:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-notifications:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-gateway:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-ui:$ImageTag"
    )

    foreach ($imageName in $imageNames) {
        $exists = & docker image inspect $imageName 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($exists)) {
            Add-Content -Path $progressLogPath -Value "Removing stale local image: $imageName"
            & docker image rm -f $imageName 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-image-prune.log') | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove stale local image $imageName."
            }
        }
    }
}

function Get-Phase10Databases {
    @(
        'OrderProcessingSystem_Dev',
        'OrderProcessingSystem_TenantC_Dev'
    )
}

function Get-LatestPhase10MigrationId {
    $migrationsPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.Infrastructure\Migrations'
    $migrationFiles = @(
        Get-ChildItem -LiteralPath $migrationsPath -Filter '*.cs' -File |
            Where-Object {
                $_.Name -notlike '*.Designer.cs' -and
                $_.Name -ne 'OrderProcessingSystemDbContextModelSnapshot.cs' -and
                $_.BaseName -match '^\d+_'
            } |
            Sort-Object Name
    )

    if ($migrationFiles.Count -eq 0) {
        throw "No EF migration files were found under $migrationsPath."
    }

    return $migrationFiles[-1].BaseName
}

function Invoke-Phase10SqlCmdInComposeContainer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $escapedQuery = $normalizedQuery.Replace('"', '\"')
    $shellCommand = [string]::Format(
        'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -l 60 -C -S localhost -U sa -P "$SA_PASSWORD" -d "{0}" -h -1 -W -Q "SET NOCOUNT ON; {1}"',
        $Database,
        $escapedQuery)

    $attempt = 1
    while ($attempt -le 30) {
        $composeProfileArgs = Get-ComposeProfileArguments
        $composeEnvArgs = Get-ComposeEnvArguments
        $output = & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs exec -T sql-server /bin/sh -lc $shellCommand 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @($output | ForEach-Object { $_.ToString() })
        }

        if ($attempt -eq 30) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }

        Start-Sleep -Seconds 5
        $attempt++
    }
}

function Get-Phase10SqlScalar {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $output = @(Invoke-Phase10SqlCmdInComposeContainer -Database $Database -Query $Query)
    $lines = @(
        $output |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch '^\(\d+ rows? affected\)$'
            }
    )

    if ($lines.Count -eq 0) {
        return ''
    }

    return $lines[-1]
}

function Test-Phase10MigrationApplied {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMigrationId
    )

    $query = @"
IF OBJECT_ID(N'dbo.__EFMigrationsHistory', N'U') IS NULL
BEGIN
    SELECT N'__EFMigrationsHistory missing';
END
ELSE
BEGIN
    SELECT TOP (1) [MigrationId] FROM [__EFMigrationsHistory] ORDER BY [MigrationId] DESC;
END
"@

    $appliedMigration = Get-Phase10SqlScalar -Database $DatabaseName -Query $query
    return ($appliedMigration -eq $ExpectedMigrationId)
}

function Invoke-Phase10SqlScriptInComposeContainer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $composeProfileArgs = Get-ComposeProfileArguments
    $composeEnvArgs = Get-ComposeEnvArguments
    $containerId = (& docker compose @composeEnvArgs -f $composeFile @composeProfileArgs ps -q sql-server 2>&1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw "Could not resolve the Phase 10 sql-server container id."
    }

    $containerScriptPath = "/tmp/phase10-$DatabaseName-migrations.sql"
    & docker cp $ScriptPath "${containerId}:$containerScriptPath" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy migration script into the sql-server container: $ScriptPath"
    }

    $sqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
    $shellCommand = "/opt/mssql-tools18/bin/sqlcmd -l 60 -S localhost -U sa -P '$sqlPassword' -C -b -I -d '$DatabaseName' -i '$containerScriptPath'"
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $composeProfileArgs = Get-ComposeProfileArguments
        $composeEnvArgs = Get-ComposeEnvArguments
        $output = & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs exec -T sql-server /bin/sh -lc $shellCommand 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @($output | ForEach-Object { $_.ToString() })
        }

        $message = ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        if ($attempt -eq 5) {
            throw "Failed to apply EF migration script to $DatabaseName after $attempt attempt(s). $message"
        }

        Start-Sleep -Seconds 10
    }
}

function Invoke-Phase10EfDatabaseUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [string]$SqlPassword,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMigrationId
    )

    $arguments = @(
        'ef', 'migrations', 'script',
        '--idempotent',
        '--project', 'XYDataLabs.OrderProcessingSystem.Infrastructure',
        '--startup-project', 'XYDataLabs.OrderProcessingSystem.API',
        '--context', 'OrderProcessingSystemDbContext',
        '--verbose'
    )

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $attemptLogPath = Join-Path $runDir "ef-script-$DatabaseName-attempt-$attempt.log"
        $scriptPath = Join-Path $runDir "ef-script-$DatabaseName-attempt-$attempt.sql"
        $scriptArguments = @($arguments + @('--output', $scriptPath))
        Add-Content -Path $progressLogPath -Value "Starting EF migration script attempt $attempt for $DatabaseName. Log: $attemptLogPath Script: $scriptPath"

        $output = & dotnet @scriptArguments 2>&1
        $exitCode = $LASTEXITCODE
        $message = ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        Set-Content -Path $attemptLogPath -Value $message -Encoding utf8

        if ($exitCode -eq 0 -and (Test-Path $scriptPath)) {
            $applyOutput = Invoke-Phase10SqlScriptInComposeContainer -DatabaseName $DatabaseName -ScriptPath $scriptPath
            Set-Content -Path (Join-Path $runDir "ef-apply-$DatabaseName-attempt-$attempt.log") -Value $applyOutput -Encoding utf8
        }

        if ($exitCode -eq 0 -and (Test-Phase10MigrationApplied -DatabaseName $DatabaseName -ExpectedMigrationId $ExpectedMigrationId)) {
            Add-Content -Path $progressLogPath -Value "EF migration verified for ${DatabaseName}: $ExpectedMigrationId"
            return
        }

        $appliedMigration = Get-Phase10SqlScalar -Database $DatabaseName -Query @"
IF OBJECT_ID(N'dbo.__EFMigrationsHistory', N'U') IS NULL
BEGIN
    SELECT N'__EFMigrationsHistory missing';
END
ELSE
BEGIN
    SELECT TOP (1) [MigrationId] FROM [__EFMigrationsHistory] ORDER BY [MigrationId] DESC;
END
"@

        Add-Content -Path $progressLogPath -Value "EF migration script attempt $attempt did not verify for $DatabaseName. ExitCode=$exitCode Expected=$ExpectedMigrationId Actual=$appliedMigration Log=$attemptLogPath Script=$scriptPath"
        if ($attempt -eq 5) {
            throw "EF migration failed to verify for $DatabaseName after $attempt attempt(s). Expected '$ExpectedMigrationId', actual '$appliedMigration'. See $attemptLogPath."
        }

        Start-Sleep -Seconds 10
    }
}

function Invoke-Phase10DatabaseBootstrap {
    Write-Host 'Applying Phase 10 local EF migrations...' -ForegroundColor Cyan
    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local EF migration bootstrap.'
    $latestMigrationId = Get-LatestPhase10MigrationId
    foreach ($databaseName in @('OrderProcessingSystem_Dev', 'OrderProcessingSystem_TenantC_Dev')) {
        Add-Content -Path $progressLogPath -Value "Starting EF migration bootstrap for $databaseName."
        Write-Host "  Migrating $databaseName..." -ForegroundColor Yellow
        $localSqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
        Invoke-Phase10EfDatabaseUpdate -DatabaseName $databaseName -SqlPassword $localSqlPassword -ExpectedMigrationId $latestMigrationId
        Add-Content -Path $progressLogPath -Value "Completed EF migration bootstrap for $databaseName."
    }
    Add-Content -Path $progressLogPath -Value 'Completed Phase 10 local EF migration bootstrap.'
}

function Assert-Phase10DatabaseAzureParity {
    Write-Host 'Validating Phase 10 local database parity with clean Azure deployment...' -ForegroundColor Cyan

    $latestMigrationId = Get-LatestPhase10MigrationId
    foreach ($databaseName in (Get-Phase10Databases)) {
        $appliedMigration = Get-Phase10SqlScalar -Database $databaseName -Query 'SELECT TOP (1) [MigrationId] FROM [__EFMigrationsHistory] ORDER BY [MigrationId] DESC;'
        if ($appliedMigration -ne $latestMigrationId) {
            throw "Database $databaseName is not on the latest EF migration. Expected '$latestMigrationId', found '$appliedMigration'."
        }

        Add-Content -Path $progressLogPath -Value "Verified latest migration for ${databaseName}: $appliedMigration"
    }

    $providerChecks = @(
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantA'; ProviderType = 'Razorpay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantA'; ProviderType = 'OpenPay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantB'; ProviderType = 'Razorpay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantB'; ProviderType = 'OpenPay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_TenantC_Dev'; TenantCode = 'TenantC'; ProviderType = 'Razorpay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_TenantC_Dev'; TenantCode = 'TenantC'; ProviderType = 'OpenPay' }
    )

    foreach ($check in $providerChecks) {
        $query = @"
SELECT COUNT_BIG(*)
FROM [payments].[PaymentProviders] pp
INNER JOIN [dbo].[Tenants] t ON t.[Id] = pp.[TenantId]
WHERE t.[Code] = '$($check.TenantCode)'
  AND pp.[ProviderType] = '$($check.ProviderType)'
  AND pp.[PrivateKeyConfigurationKey] = 'PaymentProviders:$($check.TenantCode):$($check.ProviderType):PrivateKey';
"@
        $countText = Get-Phase10SqlScalar -Database $check.Database -Query $query
        [long]$count = 0
        [void][long]::TryParse($countText, [ref]$count)
        if ($count -lt 1) {
            throw "Payment-provider baseline is missing in $($check.Database): tenant=$($check.TenantCode), provider=$($check.ProviderType). This would fail a clean Azure payment matrix run."
        }

        Add-Content -Path $progressLogPath -Value "Verified provider baseline: $($check.Database) / $($check.TenantCode) / $($check.ProviderType)"
    }

    $tenantRoutingChecks = @(
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantA'; ExpectedProvider = 'Razorpay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantB'; ExpectedProvider = 'Razorpay' },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_TenantC_Dev'; TenantCode = 'TenantC'; ExpectedProvider = 'OpenPay' }
    )

    foreach ($check in $tenantRoutingChecks) {
        $query = "SELECT TOP (1) ISNULL([PaymentProviderCode], '') FROM [dbo].[Tenants] WHERE [Code] = '$($check.TenantCode)';"
        $actualProvider = Get-Phase10SqlScalar -Database $check.Database -Query $query
        if ($actualProvider -ne $check.ExpectedProvider) {
            throw "Tenant payment routing mismatch in $($check.Database): tenant=$($check.TenantCode), expected=$($check.ExpectedProvider), actual=$actualProvider."
        }

        Add-Content -Path $progressLogPath -Value "Verified tenant payment route: $($check.Database) / $($check.TenantCode) -> $actualProvider"
    }
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
        if ($RemoveVolumes) {
            $downArguments += '--volumes'
        }
        & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs @downArguments 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Docker compose down failed with exit code $LASTEXITCODE"
        }

        $summary.status = 'passed'
        return
    }

    Assert-DockerAvailable
    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local container stack.'
    foreach ($port in @(8081, 1433, 6379, 5022)) {
        Stop-ContainersOnPort -Port $port
    }
    $composeProfileArgs = Get-ComposeProfileArguments
    $composeEnvArgs = Get-ComposeEnvArguments
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs config --quiet 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-config.log') | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose config validation failed with exit code $LASTEXITCODE"
    }

    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs down 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-preflight-down.log') | Out-Null
    if ($CleanImages) {
        $imageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG }
        Remove-Phase10LocalImages -ImageTag $imageTag
    }
    $platformServices = @('sql-server', 'redis', 'keycloak-local', 'azurite')
    if ($Profile -eq 'messaging' -or (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        $platformServices += @('servicebus-sql', 'servicebus-emulator')
    }

    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs up -d @platformServices 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-platform-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose platform dependency startup failed with exit code $LASTEXITCODE"
    }

    Ensure-Phase10Databases
    $localSqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($localSqlPassword)) {
        throw "LOCAL_SQL_PASSWORD was not found in $envFile."
    }

    Invoke-Phase10DatabaseBootstrap
    Assert-Phase10DatabaseAzureParity
    Assert-Phase10RedisAzureParity
    Wait-ForUrl -Url 'http://localhost:8081/' -TimeoutSec $HealthTimeoutSec
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
    & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs up -d --build orders payments inventory notifications gateway ui 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-apps-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose app startup failed with exit code $LASTEXITCODE"
    }
    if ((Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        Add-Content -Path $progressLogPath -Value 'Starting Functions service image startup.'
        & docker compose @composeEnvArgs -f $composeFile @composeProfileArgs --profile functions up -d --build functions 2>&1 |
            Tee-Object -FilePath (Join-Path $runDir 'docker-compose-functions-up.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Docker compose Functions startup failed with exit code $LASTEXITCODE"
        }
    }

    Add-Content -Path $progressLogPath -Value 'Waiting for application readiness URLs.'
    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5081/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5084/health/ready' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec $HealthTimeoutSec

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
    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
    Pop-Location
}
