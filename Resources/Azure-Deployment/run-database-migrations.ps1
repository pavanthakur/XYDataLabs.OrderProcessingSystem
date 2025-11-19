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
    [string]$AdminPassword = 'Admin100@'
)

$ErrorActionPreference = 'Stop'

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

function Ensure-DotNetEf8 {
    try {
        $tools = dotnet tool list -g 2>$null
        $efLine = $tools | Where-Object { $_ -match '^dotnet-ef\s+' }
        if (-not $efLine) {
            Write-Info "Installing dotnet-ef 8.0.13..."
            dotnet tool install --global dotnet-ef --version 8.0.13 | Out-Null
            return
        }
        $version = ($efLine -split '\s+')[1]
        if ($version -notmatch '^8\.') {
            Write-Info "Switching dotnet-ef to 8.0.13 (current: $version)..."
            dotnet tool uninstall --global dotnet-ef | Out-Null
            dotnet tool install --global dotnet-ef --version 8.0.13 | Out-Null
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

# Generate resource names
$sqlServerName = "$BaseName-sql-$Environment"
$dbName = "OrderProcessingSystem_" + (Get-Culture).TextInfo.ToTitleCase($Environment)
$fullyQualifiedDomain = "$sqlServerName.database.windows.net"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment"
Write-Host "  SQL Server:     $fullyQualifiedDomain"
Write-Host "  Database:       $dbName"
Write-Host ""

# Build connection string for migrations
$connectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$dbName;User ID=$AdminUsername;Password=$AdminPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

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

Write-Host ""
Write-Host "[3/3] Verifying database schema..." -ForegroundColor Cyan

# List applied migrations
try {
    Write-Host "  [INFO] Listing applied migrations..." -ForegroundColor Gray
    $appliedMigrations = dotnet ef migrations list `
        --project XYDataLabs.OrderProcessingSystem.Infrastructure `
        --startup-project XYDataLabs.OrderProcessingSystem.API `
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
Write-Host "  1. Test API: https://$BaseName-api-xyapp-$Environment.azurewebsites.net/swagger"
Write-Host "  2. Test UI:  https://$BaseName-ui-xyapp-$Environment.azurewebsites.net"
Write-Host "  3. Query database in Azure Portal -> Query editor"
Write-Host ""

Write-Host "[SUCCESS] Database migrations completed" -ForegroundColor Green
Write-Host ""
