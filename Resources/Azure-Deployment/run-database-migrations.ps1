# run-database-migrations.ps1
# Apply EF Core migrations to Azure SQL Database
# Automated migration execution for CI/CD pipelines

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$AdminUsername = 'sqladmin',
    
    [Parameter(Mandatory=$false)]
    [string]$AdminPassword = '',
    
    [Parameter(Mandatory=$false)]
    [string]$Owner = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'branch-policy.ps1')
$branchPolicy = Get-GitHubBranchPolicy
$environmentDescriptor = Get-GitHubEnvironmentDescriptor -Policy $branchPolicy -EnvironmentKey $Environment

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

function Add-DotNetGlobalToolPath {
    $toolPath = if ($IsWindows) {
        Join-Path $env:USERPROFILE '.dotnet\tools'
    } else {
        Join-Path $HOME '.dotnet/tools'
    }

    if ((Test-Path $toolPath) -and (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $toolPath)) {
        $env:PATH = "$toolPath$([IO.Path]::PathSeparator)$env:PATH"
    }
}

function Ensure-DotNetEf8 {
    Add-DotNetGlobalToolPath

    try {
        $tools = dotnet tool list -g 2>$null
        $efLine = $tools | Where-Object { $_ -match '^dotnet-ef\s+' }
        if (-not $efLine) {
            Write-Info "Installing dotnet-ef 8.0.13..."
            dotnet tool install --global dotnet-ef --version 8.0.13 | Out-Null
            Add-DotNetGlobalToolPath
            return
        }
        $version = ($efLine -split '\s+')[1]
        if ($version -notmatch '^8\.') {
            Write-Info "Switching dotnet-ef to 8.0.13 (current: $version)..."
            dotnet tool uninstall --global dotnet-ef | Out-Null
            dotnet tool install --global dotnet-ef --version 8.0.13 | Out-Null
            Add-DotNetGlobalToolPath
        } else {
            Write-Info "dotnet-ef version $version meets requirements."
        }
    } catch {
        Write-Warn "Could not verify or install dotnet-ef. Proceeding and attempting EF commands..."
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Database Migrations - Azure SQL" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Resolve environment naming through the shared policy. Resource suffixes already use stg,
# while the live staging Azure SQL DB names keep the current Staging suffix until cutover.
$envSuffix = $environmentDescriptor.ResourceSuffix
$dbSuffix = $environmentDescriptor.AzureSqlDatabaseSuffix

# Generate resource names
$sqlServerName = "$BaseName-sql-$envSuffix"
$dbName = "OrderProcessingSystem_$dbSuffix"
$fullyQualifiedDomain = "$sqlServerName.database.windows.net"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment"
Write-Host "  SQL Server:     $fullyQualifiedDomain"
Write-Host "  Database:       $dbName"
Write-Host ""

# Retrieve password from Key Vault if not supplied
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $kvName = "kv-$BaseName-$envSuffix"
    Write-Info "AdminPassword not provided — retrieving from Key Vault '$kvName'..."
    $AdminPassword = az keyvault secret show --vault-name $kvName --name "sql-admin-password" --query value -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($AdminPassword)) {
        Write-Err "AdminPassword not provided and could not be retrieved from Key Vault '$kvName'. Ensure bootstrap has run and OIDC is configured."
        exit 1
    }
    Write-Ok "  Password retrieved from Key Vault."
}

# Build connection string for migrations
$connectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$dbName;User ID=$AdminUsername;Password=$AdminPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

function Ensure-TenantProducts {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [Parameter(Mandatory=$true)]
        [string[]]$TenantCodes
    )

    foreach ($tenantCode in $TenantCodes) {
        if ($tenantCode -notmatch '^[A-Za-z0-9_-]+$') {
            throw "Unsafe tenant code '$tenantCode' supplied to Azure product seed."
        }

        $seedQuery = @"
SET NOCOUNT ON;
DECLARE @tenantId int;

SELECT @tenantId = [Id]
FROM [dbo].[Tenants]
WHERE [Code] = N'$tenantCode';

IF @tenantId IS NULL
    THROW 51000, N'Tenant row missing for $tenantCode.', 1;

IF NOT EXISTS (SELECT 1 FROM [inventory].[Products] WHERE [TenantId] = @tenantId)
BEGIN
    INSERT INTO [inventory].[Products] ([Name], [Description], [Price], [TenantId], [CreatedBy], [CreatedDate])
    VALUES
        (N'$tenantCode Laptop', N'Sample laptop for $tenantCode', 500.00, @tenantId, 1, SYSUTCDATETIME()),
        (N'$tenantCode Phone', N'Sample phone for $tenantCode', 300.00, @tenantId, 1, SYSUTCDATETIME()),
        (N'$tenantCode Headphones', N'Sample headphones for $tenantCode', 200.00, @tenantId, 1, SYSUTCDATETIME());
END;

SELECT COUNT_BIG(*) AS ProductCount
FROM [inventory].[Products]
WHERE [TenantId] = @tenantId;
"@

        $seedOutput = sqlcmd -S $fullyQualifiedDomain -d $DatabaseName -U $AdminUsername -P $AdminPassword -b -Q $seedQuery -h -1 -W
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to ensure product baseline for tenant '$tenantCode' in '$DatabaseName'."
        }

        Write-Ok "  [OK] Product baseline ensured for $tenantCode in $DatabaseName ($([string]::Join(' ', @($seedOutput)).Trim()) rows)."
    }
}

# Navigate to solution root
$scriptDir = Split-Path -Parent $PSCommandPath
$solutionRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
Set-Location $solutionRoot

Write-Host "[1/3] Verifying EF Core tools..." -ForegroundColor Cyan
try {
    Ensure-DotNetEf8
    $efVersion = dotnet ef --version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] EF Core Tools: $efVersion" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] EF Core tools not found" -ForegroundColor Red
    Write-Host "  [INSTALL] Run: dotnet tool install --global dotnet-ef" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "[2/3] Applying migrations to Azure SQL Database..." -ForegroundColor Cyan
Write-Host "  [INFO] This may take 1-2 minutes..." -ForegroundColor Gray

try {
    # Apply migrations using EF Core CLI
    $migrationOutput = dotnet ef database update `
        --project XYDataLabs.OrderProcessingSystem.Infrastructure `
        --startup-project XYDataLabs.OrderProcessingSystem.API `
        --context OrderProcessingSystemDbContext `
        --connection "$connectionString" `
        --verbose 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Migrations applied successfully" -ForegroundColor Green
        
        # Show migration output
        Write-Host ""
        Write-Host "Migration Details:" -ForegroundColor Gray
        $migrationOutput | Select-Object -Last 10 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
    } else {
        Write-Warn "EF CLI migration failed. Falling back to SQL script application..."
        throw "ef-cli-failed"
    }
} catch {
    # Fallback: generate idempotent SQL script and apply via sqlcmd
    Write-Info "Generating idempotent migration script via dotnet ef..."
    $env:MIGRATION_CONNECTION_STRING = $connectionString
    $scriptOut = Join-Path $PSScriptRoot ("generated-migrations-{0}.sql" -f $Environment)
    $genOut = dotnet ef migrations script `
        --project XYDataLabs.OrderProcessingSystem.Infrastructure `
        --context OrderProcessingSystemDbContext `
        --idempotent `
        --output $scriptOut `
        --verbose 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $scriptOut)) {
        Write-Err "Failed to generate migration script."
        $genOut | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Ok "Script generated: $scriptOut"

    Write-Info "Applying script with sqlcmd..."
    $serverName = "$sqlServerName.database.windows.net"
    sqlcmd -S $serverName -d $dbName -U $AdminUsername -P $AdminPassword -b -i $scriptOut
    if ($LASTEXITCODE -ne 0) {
        Write-Err "sqlcmd failed applying script."
        exit 1
    }
    Write-Ok "Migrations applied via script."
}

Write-Info "Ensuring shared-database product baselines for TenantA and TenantB..."
Ensure-TenantProducts -DatabaseName $dbName -TenantCodes @('TenantA', 'TenantB')

Write-Host ""
Write-Host "[3/3] Verifying database schema..." -ForegroundColor Cyan

# List applied migrations
try {
    Write-Host "  [INFO] Listing applied migrations..." -ForegroundColor Gray
    $appliedMigrations = dotnet ef migrations list `
        --project XYDataLabs.OrderProcessingSystem.Infrastructure `
        --startup-project XYDataLabs.OrderProcessingSystem.API `
        --context OrderProcessingSystemDbContext `
        --connection "$connectionString" `
        --no-build 2>&1
    
    Write-Host "  [OK] Applied migrations:" -ForegroundColor Green
    $appliedMigrations | Select-Object -Last 10 | ForEach-Object {
        if ($_ -match '^\s*\d') {
            Write-Host "    $_" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [WARN] Could not list migrations" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "MIGRATION COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Database Status:" -ForegroundColor Cyan
Write-Host "  Server:   $fullyQualifiedDomain"
Write-Host "  Database: $dbName"
Write-Host "  Status:   Schema created with sample data"
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
$appPrefix = if ($Owner) { "$Owner-$BaseName" } else { $BaseName }
Write-Host "  1. Test API: https://$appPrefix-api-xyapp-$envSuffix.azurewebsites.net/swagger"
Write-Host "  2. Test UI:  https://$appPrefix-ui-xyapp-$envSuffix.azurewebsites.net"
Write-Host "  3. Query database in Azure Portal -> Query editor"
Write-Host ""

Write-Host "[SUCCESS] Database migrations completed" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# TenantC dedicated database migration status (ADR-009)
# TenantC is a Dedicated-tier tenant with its own database on the same SQL
# server. Azure deployment owns schema migration for that dedicated database
# because Program.cs disables applyMigrations in Azure (applyMigrations: !isAzure).
# Runtime startup can seed dedicated-tenant data only after this separate
# database exists and has the required schema.
# ─────────────────────────────────────────────────────────────────────────────
$tenantCDbName = "OrderProcessingSystem_TenantC_$dbSuffix"

Write-Host "" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TenantC Dedicated Database Migration Status" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Server:   $fullyQualifiedDomain"
Write-Host "  Database: $tenantCDbName"
Write-Host "  Tenant:   TenantC (Dedicated tier)"
Write-Host ""

# Check TenantC DB exists before attempting migrations
$tenantCDbExists = az sql db show --server $sqlServerName --resource-group "rg-$BaseName-$envSuffix" --name $tenantCDbName --query name -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tenantCDbExists)) {
    Write-Warn "  [MISSING] Dedicated database '$tenantCDbName' was not found on server '$sqlServerName'."
    Write-Warn "  [ACTION] Run provision-azure-sql.ps1 first to create the TenantC dedicated database."
    Write-Warn "  [STATUS] Dedicated TenantC migration status is incomplete — downstream deployment validation should fail closed."
} else {
    Write-Ok "  [FOUND] Dedicated TenantC database '$tenantCDbName' exists — running dedicated migrations..."

    $tenantCConnectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$tenantCDbName;User ID=$AdminUsername;Password=$AdminPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

    try {
        $tcMigrationOutput = dotnet ef database update `
            --project XYDataLabs.OrderProcessingSystem.Infrastructure `
            --startup-project XYDataLabs.OrderProcessingSystem.API `
            --context OrderProcessingSystemDbContext `
            --connection "$tenantCConnectionString" `
            --verbose 2>&1

        if ($LASTEXITCODE -eq 0) {
                Write-Ok "  [OK] TenantC dedicated database migrations applied successfully"
            $tcMigrationOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        } else {
                Write-Err "  [ERROR] TenantC dedicated database migrations failed (EF CLI exit code $LASTEXITCODE)"
            $tcMigrationOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
            exit 1
        }
    } catch {
            Write-Err "  [ERROR] TenantC dedicated database migration exception: $($_.Exception.Message)"
        exit 1
    }

    Write-Info "  [INFO] Ensuring TenantC dedicated product baseline..."
    Ensure-TenantProducts -DatabaseName $tenantCDbName -TenantCodes @('TenantC')

    # Verify TenantC migrations
    try {
            Write-Info "  [INFO] Verifying TenantC dedicated database applied migrations..."
        $tcApplied = dotnet ef migrations list `
            --project XYDataLabs.OrderProcessingSystem.Infrastructure `
            --startup-project XYDataLabs.OrderProcessingSystem.API `
            --context OrderProcessingSystemDbContext `
            --connection "$tenantCConnectionString" `
            --no-build 2>&1

            Write-Ok "  [OK] TenantC dedicated database applied migrations:"
        $tcApplied | Select-Object -Last 6 | ForEach-Object {
            if ($_ -match '\d') { Write-Host "    $_" -ForegroundColor Green }
        }
    } catch {
            Write-Warn "  [WARN] Could not list TenantC dedicated database migrations (non-fatal)"
    }

        Write-Ok "  [SUCCESS] TenantC dedicated database migration status complete"
}

Write-Host ""
