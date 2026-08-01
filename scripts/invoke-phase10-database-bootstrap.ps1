param(
    [ValidateSet('apps', 'infrastructure', 'messaging')]
    [string]$Profile = 'apps',

    [string]$RunDir = '',

    [string]$ProgressLogPath = ''
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'

function Write-ProgressMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    if (-not [string]::IsNullOrWhiteSpace($ProgressLogPath)) {
        $progressDirectory = Split-Path -Parent $ProgressLogPath
        if (-not [string]::IsNullOrWhiteSpace($progressDirectory)) {
            New-Item -ItemType Directory -Path $progressDirectory -Force | Out-Null
        }

        Add-Content -Path $ProgressLogPath -Value $Message
    }
}

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
    }

    if (-not (Test-Path -LiteralPath $envFile)) {
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
        [string]$ExpectedMigrationId
    )

    $logRoot = if ([string]::IsNullOrWhiteSpace($RunDir)) { Join-Path $workspaceRoot '.tmp\phase10-bootstrap' } else { $RunDir }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

    $arguments = @(
        'ef', 'migrations', 'script',
        '--idempotent',
        '--project', 'XYDataLabs.OrderProcessingSystem.Infrastructure',
        '--startup-project', 'XYDataLabs.OrderProcessingSystem.API',
        '--context', 'OrderProcessingSystemDbContext',
        '--verbose'
    )

    $databaseConnectionString = "Server=localhost,1433;Database=$DatabaseName;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
    $previousValues = @{
        'ASPNETCORE_ENVIRONMENT' = [Environment]::GetEnvironmentVariable('ASPNETCORE_ENVIRONMENT')
        'ConnectionStrings__OrderProcessingSystemDbConnection' = [Environment]::GetEnvironmentVariable('ConnectionStrings__OrderProcessingSystemDbConnection')
        'ConnectionStrings__TenantRegistryDbConnection' = [Environment]::GetEnvironmentVariable('ConnectionStrings__TenantRegistryDbConnection')
        'DedicatedTenantConnectionStrings__TenantC' = [Environment]::GetEnvironmentVariable('DedicatedTenantConnectionStrings__TenantC')
    }

    try {
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Development')
        [Environment]::SetEnvironmentVariable('ConnectionStrings__OrderProcessingSystemDbConnection', $databaseConnectionString)
        [Environment]::SetEnvironmentVariable('ConnectionStrings__TenantRegistryDbConnection', $databaseConnectionString)
        [Environment]::SetEnvironmentVariable('DedicatedTenantConnectionStrings__TenantC', "Server=localhost,1433;Database=OrderProcessingSystem_TenantC_Dev;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;")

        for ($attempt = 1; $attempt -le 5; $attempt++) {
            $attemptLogPath = Join-Path $logRoot "ef-update-$DatabaseName-attempt-$attempt.log"
            $scriptPath = Join-Path $logRoot "ef-update-$DatabaseName-attempt-$attempt.sql"
            Write-ProgressMessage "Starting EF migration script attempt $attempt for $DatabaseName. Log: $attemptLogPath"

            $output = & dotnet @arguments --output $scriptPath 2>&1
            $exitCode = $LASTEXITCODE
            $message = ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
            Set-Content -Path $attemptLogPath -Value $message -Encoding utf8

            if ($exitCode -eq 0) {
                try {
                    $applyOutput = @(Invoke-Phase10SqlScriptInComposeContainer -DatabaseName $DatabaseName -ScriptPath $scriptPath)
                    if ($applyOutput.Count -gt 0) {
                        Add-Content -Path $attemptLogPath -Value ([Environment]::NewLine + [string]::Join([Environment]::NewLine, $applyOutput))
                    }
                }
                catch {
                    $exitCode = 1
                    Add-Content -Path $attemptLogPath -Value ([Environment]::NewLine + $_.Exception.Message)
                }
            }

            if ($exitCode -eq 0 -and (Test-Phase10MigrationApplied -DatabaseName $DatabaseName -ExpectedMigrationId $ExpectedMigrationId)) {
                Write-ProgressMessage "EF migration verified for ${DatabaseName}: $ExpectedMigrationId"
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

            Write-ProgressMessage "EF migration bootstrap attempt $attempt did not verify for $DatabaseName. ExitCode=$exitCode Expected=$ExpectedMigrationId Actual=$appliedMigration Log=$attemptLogPath"
            if ($attempt -eq 5) {
                throw "EF migration failed to verify for $DatabaseName after $attempt attempt(s). Expected '$ExpectedMigrationId', actual '$appliedMigration'. See $attemptLogPath."
            }

            Start-Sleep -Seconds 10
        }
    }
    finally {
        foreach ($entry in $previousValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
    }
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
        Write-ProgressMessage "Ensured database exists: $databaseName"
    }
}

function Invoke-Phase10DatabaseBootstrap {
    Write-Host 'Applying Phase 10 local EF migrations...' -ForegroundColor Cyan
    Write-ProgressMessage 'Starting Phase 10 local EF migration bootstrap.'
    $latestMigrationId = Get-LatestPhase10MigrationId
    foreach ($databaseName in (Get-Phase10Databases)) {
        Write-ProgressMessage "Starting EF migration bootstrap for $databaseName."
        Write-Host "  Migrating $databaseName..." -ForegroundColor Yellow
        Invoke-Phase10EfDatabaseUpdate -DatabaseName $databaseName -ExpectedMigrationId $latestMigrationId
        Write-ProgressMessage "Completed EF migration bootstrap for $databaseName."
    }
    Write-ProgressMessage 'Completed Phase 10 local EF migration bootstrap.'
}

function Invoke-Phase10SampleDataSeed {
    Write-Host 'Applying Phase 10 local sample data seed...' -ForegroundColor Cyan
    Write-ProgressMessage 'Starting Phase 10 local sample data seed.'

    $logRoot = if ([string]::IsNullOrWhiteSpace($RunDir)) { Join-Path $workspaceRoot '.tmp\phase10-bootstrap' } else { $RunDir }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $seedLogPath = Join-Path $logRoot 'phase10-seed-bootstrap.log'

    $defaultConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
    $dedicatedTenantConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_TenantC_Dev;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
    $registryConnectionString = $defaultConnectionString

    $previousValues = @{
        'ASPNETCORE_ENVIRONMENT' = [Environment]::GetEnvironmentVariable('ASPNETCORE_ENVIRONMENT')
        'Phase10__BootstrapSeedOnly' = [Environment]::GetEnvironmentVariable('Phase10__BootstrapSeedOnly')
        'Phase10__DisableStartupDdl' = [Environment]::GetEnvironmentVariable('Phase10__DisableStartupDdl')
        'ConnectionStrings__OrderProcessingSystemDbConnection' = [Environment]::GetEnvironmentVariable('ConnectionStrings__OrderProcessingSystemDbConnection')
        'ConnectionStrings__TenantRegistryDbConnection' = [Environment]::GetEnvironmentVariable('ConnectionStrings__TenantRegistryDbConnection')
        'DedicatedTenantConnectionStrings__TenantC' = [Environment]::GetEnvironmentVariable('DedicatedTenantConnectionStrings__TenantC')
    }

    try {
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Development')
        [Environment]::SetEnvironmentVariable('Phase10__BootstrapSeedOnly', 'true')
        [Environment]::SetEnvironmentVariable('Phase10__DisableStartupDdl', 'true')
        [Environment]::SetEnvironmentVariable('ConnectionStrings__OrderProcessingSystemDbConnection', $defaultConnectionString)
        [Environment]::SetEnvironmentVariable('ConnectionStrings__TenantRegistryDbConnection', $registryConnectionString)
        [Environment]::SetEnvironmentVariable('DedicatedTenantConnectionStrings__TenantC', $dedicatedTenantConnectionString)

        $output = & dotnet run --project 'XYDataLabs.OrderProcessingSystem.API' --no-launch-profile -- --phase10-bootstrap-seed-only 2>&1
        $exitCode = $LASTEXITCODE
        $message = ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        Set-Content -Path $seedLogPath -Value $message -Encoding utf8

        if ($exitCode -ne 0) {
            throw "Phase 10 sample data seed failed with exit code $exitCode. See $seedLogPath."
        }

        Write-ProgressMessage "Completed Phase 10 local sample data seed. Log: $seedLogPath"
    }
    finally {
        foreach ($entry in $previousValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
    }
}

function Ensure-Phase10SqlSampleDataBaseline {
    Write-Host 'Ensuring Phase 10 SQL sample data baseline...' -ForegroundColor Cyan
    Write-ProgressMessage 'Ensuring Phase 10 SQL sample data baseline.'

    $sharedDatabaseQuery = @"
DECLARE @tenantId int;

SELECT @tenantId = [Id]
FROM [dbo].[Tenants]
WHERE [Code] = N'TenantA';

IF @tenantId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [orders].[Customers] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [orders].[Customers] ([Name], [Email], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantA Sample Customer 1', N'tenanta.sample.1@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantA Sample Customer 2', N'tenanta.sample.2@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantA Sample Customer 3', N'tenanta.sample.3@example.test', @tenantId, 1, SYSUTCDATETIME());
    END;

    IF NOT EXISTS (SELECT 1 FROM [inventory].[Products] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [inventory].[Products] ([Name], [Description], [Price], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantA Laptop', N'Sample laptop for TenantA', 500.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantA Phone', N'Sample phone for TenantA', 300.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantA Headphones', N'Sample headphones for TenantA', 200.00, @tenantId, 1, SYSUTCDATETIME());
    END;
END;

SET @tenantId = NULL;
SELECT @tenantId = [Id]
FROM [dbo].[Tenants]
WHERE [Code] = N'TenantB';

IF @tenantId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [orders].[Customers] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [orders].[Customers] ([Name], [Email], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantB Sample Customer 1', N'tenantb.sample.1@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantB Sample Customer 2', N'tenantb.sample.2@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantB Sample Customer 3', N'tenantb.sample.3@example.test', @tenantId, 1, SYSUTCDATETIME());
    END;

    IF NOT EXISTS (SELECT 1 FROM [inventory].[Products] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [inventory].[Products] ([Name], [Description], [Price], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantB Laptop', N'Sample laptop for TenantB', 500.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantB Phone', N'Sample phone for TenantB', 300.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantB Headphones', N'Sample headphones for TenantB', 200.00, @tenantId, 1, SYSUTCDATETIME());
    END;
END;
"@

    $dedicatedDatabaseQuery = @"
DECLARE @tenantId int;

SELECT @tenantId = [Id]
FROM [dbo].[Tenants]
WHERE [Code] = N'TenantC';

IF @tenantId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [orders].[Customers] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [orders].[Customers] ([Name], [Email], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantC Sample Customer 1', N'tenantc.sample.1@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantC Sample Customer 2', N'tenantc.sample.2@example.test', @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantC Sample Customer 3', N'tenantc.sample.3@example.test', @tenantId, 1, SYSUTCDATETIME());
    END;

    IF NOT EXISTS (SELECT 1 FROM [inventory].[Products] WHERE [TenantId] = @tenantId)
    BEGIN
        INSERT INTO [inventory].[Products] ([Name], [Description], [Price], [TenantId], [CreatedBy], [CreatedDate])
        VALUES
            (N'TenantC Laptop', N'Sample laptop for TenantC', 500.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantC Phone', N'Sample phone for TenantC', 300.00, @tenantId, 1, SYSUTCDATETIME()),
            (N'TenantC Headphones', N'Sample headphones for TenantC', 200.00, @tenantId, 1, SYSUTCDATETIME());
    END;
END;
"@

    Invoke-Phase10SqlCmdInComposeContainer -Database 'OrderProcessingSystem_Dev' -Query $sharedDatabaseQuery | Out-Null
    Invoke-Phase10SqlCmdInComposeContainer -Database 'OrderProcessingSystem_TenantC_Dev' -Query $dedicatedDatabaseQuery | Out-Null
    Write-ProgressMessage 'Completed Phase 10 SQL sample data baseline.'
}

function Assert-Phase10DatabaseAzureParity {
    Write-Host 'Validating Phase 10 local database parity with clean Azure deployment...' -ForegroundColor Cyan

    $latestMigrationId = Get-LatestPhase10MigrationId
    foreach ($databaseName in (Get-Phase10Databases)) {
        $appliedMigration = Get-Phase10SqlScalar -Database $databaseName -Query 'SELECT TOP (1) [MigrationId] FROM [__EFMigrationsHistory] ORDER BY [MigrationId] DESC;'
        if ($appliedMigration -ne $latestMigrationId) {
            throw "Database $databaseName is not on the latest EF migration. Expected '$latestMigrationId', found '$appliedMigration'."
        }

        Write-ProgressMessage "Verified latest migration for ${databaseName}: $appliedMigration"
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

        Write-ProgressMessage "Verified provider baseline: $($check.Database) / $($check.TenantCode) / $($check.ProviderType)"
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

        Write-ProgressMessage "Verified tenant payment route: $($check.Database) / $($check.TenantCode) -> $actualProvider"
    }

    $productSeedChecks = @(
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantA'; MinimumProductCount = 1 },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_Dev'; TenantCode = 'TenantB'; MinimumProductCount = 1 },
        [pscustomobject]@{ Database = 'OrderProcessingSystem_TenantC_Dev'; TenantCode = 'TenantC'; MinimumProductCount = 1 }
    )

    foreach ($check in $productSeedChecks) {
        $query = @"
SELECT COUNT_BIG(*)
FROM [inventory].[Products] p
INNER JOIN [dbo].[Tenants] t ON t.[Id] = p.[TenantId]
WHERE t.[Code] = '$($check.TenantCode)';
"@
        $countText = Get-Phase10SqlScalar -Database $check.Database -Query $query
        [long]$count = 0
        [void][long]::TryParse($countText, [ref]$count)
        if ($count -lt $check.MinimumProductCount) {
            throw "Product seed baseline is missing in $($check.Database): tenant=$($check.TenantCode), expected at least $($check.MinimumProductCount), actual=$count."
        }

        Write-ProgressMessage "Verified product seed baseline: $($check.Database) / $($check.TenantCode) -> $count"
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

    Write-ProgressMessage 'Verified Redis readiness: PONG'
}

if (-not (Test-Path -LiteralPath $composeFile)) {
    throw "Compose file not found: $composeFile"
}

$localSqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
if ([string]::IsNullOrWhiteSpace($localSqlPassword)) {
    throw "LOCAL_SQL_PASSWORD was not found in $envFile."
}

Ensure-Phase10Databases
Invoke-Phase10DatabaseBootstrap
Invoke-Phase10SampleDataSeed
Ensure-Phase10SqlSampleDataBaseline
Assert-Phase10DatabaseAzureParity
Assert-Phase10RedisAzureParity
