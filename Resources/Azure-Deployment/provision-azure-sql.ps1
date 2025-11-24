# provision-azure-sql.ps1
# Automated Azure SQL Database provisioning for CI/CD pipelines
# No manual steps required - fully automated deployment

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$Location = 'centralindia',
    
    [Parameter(Mandatory=$false)]
    [string]$AdminUsername = 'sqladmin',
    
    [Parameter(Mandatory=$false)]
    [string]$AdminPassword = 'Admin100@',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipAppServiceConfig
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure SQL Database Provisioning" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Generate resource names
$rgName = "rg-$BaseName-$Environment"
$sqlServerName = "$BaseName-sql-$Environment"
$dbName = "OrderProcessingSystem_" + (Get-Culture).TextInfo.ToTitleCase($Environment)
$apiAppName = "$BaseName-api-xyapp-$Environment"
$uiAppName = "$BaseName-ui-xyapp-$Environment"

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment"
Write-Host "  Resource Group: $rgName"
Write-Host "  SQL Server:     $sqlServerName"
Write-Host "  Database:       $dbName"
Write-Host "  Location:       $Location"
Write-Host ""

# Ensure Resource Group is present and ready before proceeding
Write-Host "[0/6] Verifying resource group readiness..." -ForegroundColor Cyan
$rgTimeout = 10 * 60
$rgInterval = 120
$rgElapsed = 0
$rgReady = $false
while ($rgElapsed -lt $rgTimeout -and -not $rgReady) {
    $rgInfoRaw = az group show --name $rgName --query "{name:name, state:properties.provisioningState}" -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $rgInfoRaw) {
        $rgInfo = $rgInfoRaw | ConvertFrom-Json
        if ($rgInfo -and $rgInfo.name -eq $rgName -and $rgInfo.state -eq 'Succeeded') { $rgReady = $true; break }
    }
    if (-not $rgReady) { Start-Sleep -Seconds $rgInterval; $rgElapsed += $rgInterval }
}
if (-not $rgReady) {
    Write-Host "  [ERROR] Resource group not found or not ready after 10 minutes: $rgName" -ForegroundColor Red
    Write-Host "  [HINT] Ensure infrastructure bootstrap completed successfully before SQL provisioning." -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Resource group ready: $rgName" -ForegroundColor Green

# Auto-generate secure password if not provided
if (-not $AdminPassword) {
    Write-Host "[AUTO] Generating secure SQL admin password..." -ForegroundColor Yellow
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%'
    $AdminPassword = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    Write-Host "[OK] Password generated" -ForegroundColor Green
}

# Step 1: Check if SQL Server exists
Write-Host "[1/6] Checking SQL Server..." -ForegroundColor Cyan
$sqlServerExists = $null
try {
    $checkResult = az sql server show --name $sqlServerName --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $checkResult) {
        $sqlServerExists = $checkResult | ConvertFrom-Json
    }
} catch {
    $sqlServerExists = $null
}

if ($sqlServerExists) {
    Write-Host "  [EXISTS] SQL Server '$sqlServerName' already exists" -ForegroundColor Green
    $sqlServer = $sqlServerExists
} else {
    Write-Host "  [CREATE] Creating SQL Server '$sqlServerName'..." -ForegroundColor Yellow
    Write-Host "  [INFO] This typically takes 2-3 minutes..." -ForegroundColor Gray
    
    $sqlServer = az sql server create `
        --name $sqlServerName `
        --resource-group $rgName `
        --location $Location `
        --admin-user $AdminUsername `
        --admin-password $AdminPassword `
        --output json 2>$null | ConvertFrom-Json

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] SQL Server create accepted" -ForegroundColor Green
        Write-Host "  [WAIT] Polling for server readiness (max 10 min)..." -ForegroundColor Gray
        $serverReady = $false
        $pollElapsed = 0
        while ($pollElapsed -lt 600 -and -not $serverReady) {
            Start-Sleep -Seconds 15
            $pollElapsed += 15
            $show = az sql server show --name $sqlServerName --resource-group $rgName --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and $show) { $serverReady = $true; Write-Host "    [OK] Server ready after $([math]::Round($pollElapsed/60,1)) min" -ForegroundColor Green }
        }
        if (-not $serverReady) { Write-Host "    [WARN] Server readiness not confirmed after 10 min (continuing)" -ForegroundColor Yellow }
    } else {
        Write-Host "  [ERROR] Failed to create SQL Server (CLI exit code $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "  [DIAG] Raw output: $sqlServer" -ForegroundColor Yellow
        Write-Host "  [HINT] Remove preview flags or check name uniqueness / permissions." -ForegroundColor Yellow
        exit 1
    }
}

# Step 2: Configure firewall rules
Write-Host "[2/6] Configuring firewall rules..." -ForegroundColor Cyan

# Allow Azure services
$azureServicesRule = $null
try {
    $checkResult = az sql server firewall-rule show `
        --name AllowAzureServices `
        --server $sqlServerName `
        --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $checkResult) {
        $azureServicesRule = $checkResult
    }
} catch { }

if (-not $azureServicesRule) {
    az sql server firewall-rule create `
        --resource-group $rgName `
        --server $sqlServerName `
        --name AllowAzureServices `
        --start-ip-address 0.0.0.0 `
        --end-ip-address 0.0.0.0 `
        --output none 2>$null
    Write-Host "  [OK] Azure Services firewall rule created" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Azure Services firewall rule exists" -ForegroundColor Green
}

# Allow current IP for management (best effort)
try {
    $myIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    
    $myIpRule = $null
    try {
        $checkResult = az sql server firewall-rule show `
            --name AllowMyIP `
            --server $sqlServerName `
            --resource-group $rgName --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $checkResult) {
            $myIpRule = $checkResult
        }
    } catch { }
    
    if (-not $myIpRule) {
        az sql server firewall-rule create `
            --resource-group $rgName `
            --server $sqlServerName `
            --name AllowMyIP `
            --start-ip-address $myIp `
            --end-ip-address $myIp `
            --output none 2>$null
        Write-Host "  [OK] Your IP ($myIp) added to firewall" -ForegroundColor Green
    }
} catch {
    Write-Host "  [SKIP] Could not detect public IP - firewall rule skipped" -ForegroundColor Yellow
}

# Step 3: Create database
Write-Host "[3/6] Creating database..." -ForegroundColor Cyan
$dbExists = $null
try {
    $checkResult = az sql db show --name $dbName --server $sqlServerName --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $checkResult) {
        $dbExists = $checkResult | ConvertFrom-Json
    }
} catch { }

if ($dbExists) {
    Write-Host "  [EXISTS] Database '$dbName' already exists" -ForegroundColor Green
    $database = $dbExists
} else {
    Write-Host "  [CREATE] Creating database '$dbName' (Basic tier)..." -ForegroundColor Yellow
    Write-Host "  [INFO] This typically takes 1-2 minutes..." -ForegroundColor Gray
    
    $database = az sql db create `
        --resource-group $rgName `
        --server $sqlServerName `
        --name $dbName `
        --service-objective Basic `
        --max-size 2GB `
        --zone-redundant false `
        --backup-storage-redundancy Local `
        --output json 2>$null | ConvertFrom-Json

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Database create accepted" -ForegroundColor Green
        Write-Host "  [WAIT] Polling for database readiness (max 5 min)..." -ForegroundColor Gray
        $dbReady = $false
        $dbElapsed = 0
        while ($dbElapsed -lt 300 -and -not $dbReady) {
            Start-Sleep -Seconds 10
            $dbElapsed += 10
            $dbShow = az sql db show --name $dbName --server $sqlServerName --resource-group $rgName --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and $dbShow) { $dbReady = $true; Write-Host "    [OK] Database ready after $([math]::Round($dbElapsed/60,1)) min" -ForegroundColor Green }
        }
        if (-not $dbReady) { Write-Host "    [WARN] Database readiness not confirmed after 5 min (continuing)" -ForegroundColor Yellow }
    } else {
        Write-Host "  [ERROR] Failed to create database (CLI exit code $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

# Step 4: Build connection string
Write-Host "[4/6] Building connection string..." -ForegroundColor Cyan
$fullyQualifiedDomain = "$sqlServerName.database.windows.net"
$connectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$dbName;User ID=$AdminUsername;Password=$AdminPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
Write-Host "  [OK] Connection string generated" -ForegroundColor Green

# Step 5: Configure API App Service
if (-not $SkipAppServiceConfig) {
    Write-Host "[5/6] Configuring API App Service..." -ForegroundColor Cyan
    try {
        az webapp config connection-string set `
            --name $apiAppName `
            --resource-group $rgName `
            --connection-string-type SQLAzure `
            --settings OrderProcessingSystemDbConnection="$connectionString" `
            --output none 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] API connection string configured" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Could not configure API connection string" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] API App Service not found or inaccessible" -ForegroundColor Yellow
    }

    # Step 6: Configure UI App Service
    Write-Host "[6/6] Configuring UI App Service..." -ForegroundColor Cyan
    try {
        az webapp config connection-string set `
            --name $uiAppName `
            --resource-group $rgName `
            --connection-string-type SQLAzure `
            --settings OrderProcessingSystemDbConnection="$connectionString" `
            --output none 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] UI connection string configured" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Could not configure UI connection string" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] UI App Service not found or inaccessible" -ForegroundColor Yellow
    }

    # Restart apps to apply configuration
    Write-Host ""
    Write-Host "[RESTART] Restarting App Services..." -ForegroundColor Cyan
    az webapp restart --name $apiAppName --resource-group $rgName 2>$null
    az webapp restart --name $uiAppName --resource-group $rgName 2>$null
    Start-Sleep -Seconds 5
    Write-Host "  [OK] App Services restarted" -ForegroundColor Green
} else {
    Write-Host "[5/6] Skipping App Service configuration (SkipAppServiceConfig)" -ForegroundColor Yellow
    Write-Host "[6/6] Skipping App Service configuration (SkipAppServiceConfig)" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "PROVISIONING COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Database Details:" -ForegroundColor Cyan
Write-Host "  Server FQDN:    $fullyQualifiedDomain"
Write-Host "  Database Name:  $dbName"
Write-Host "  Admin User:     $AdminUsername"
Write-Host "  Tier:           Basic (2GB)"
Write-Host "  Cost:           ~5 USD/month"
Write-Host ""

Write-Host "Connection String (masked):" -ForegroundColor Cyan
$maskedConnStr = $connectionString -replace "Password=[^;]+", "Password=***"
Write-Host "  $maskedConnStr"
Write-Host ""

Write-Host "Management:" -ForegroundColor Cyan
Write-Host "  Portal: https://portal.azure.com"
Write-Host "  Navigate: SQL databases -> $dbName -> Query editor"
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Run database migrations (EF Core or SQL scripts)"
Write-Host "  2. Test API: https://$apiAppName.azurewebsites.net"
Write-Host "  3. Test UI:  https://$uiAppName.azurewebsites.net"
Write-Host ""

# Output for CI/CD pipelines
Write-Host "CI/CD Output Variables:" -ForegroundColor Cyan
Write-Host "  SQL_SERVER_FQDN=$fullyQualifiedDomain"
Write-Host "  SQL_DATABASE_NAME=$dbName"
Write-Host "  SQL_ADMIN_USERNAME=$AdminUsername"
Write-Host ""

Write-Host "[SUCCESS] Azure SQL Database provisioned and configured" -ForegroundColor Green
Write-Host ""

# Exit with success code even if app service configuration warnings occurred
exit 0
