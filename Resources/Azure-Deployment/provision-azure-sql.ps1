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
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipAppServiceConfig,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = '',

    [Parameter(Mandatory=$false)]
    [string]$AadAdminLogin,

    [Parameter(Mandatory=$false)]
    [string]$AadAdminObjectId
)

$ErrorActionPreference = 'Stop'

function Resolve-GitHubOwner {
    param(
        [string]$Owner,
        [string]$DefaultOwner = 'pavanthakur'
    )

    if (-not [string]::IsNullOrWhiteSpace($Owner)) { return $Owner }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY) -and $env:GITHUB_REPOSITORY -match '^(?<owner>[^/]+)/.+$') { return $Matches.owner }

    try {
        $originUrl = git config --get remote.origin.url 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originUrl)) {
            $originUrl = $originUrl.Trim()
            if ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/[^/]+?(?:\.git)?$') { return $Matches.owner }
        }
    }
    catch { }

    return $DefaultOwner
}

$GitHubOwner = Resolve-GitHubOwner -Owner $GitHubOwner

function Convert-SecureStringToPlainText {
    param(
        [Parameter(Mandatory = $true)] [SecureString]$Value
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Resolve-AadAdminSettings {
    param(
        [string]$Environment,
        [string]$ExplicitLogin,
        [string]$ExplicitObjectId
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitLogin) -and -not [string]::IsNullOrWhiteSpace($ExplicitObjectId)) {
        return @{
            Login = $ExplicitLogin
            ObjectId = $ExplicitObjectId
            Source = 'script-parameters'
        }
    }

    $parameterFileName = switch ($Environment) {
        'dev' { 'dev.json' }
        'staging' { 'staging.json' }
        'prod' { 'prod.json' }
    }

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $parameterFilePath = Join-Path $repoRoot "infra/parameters/$parameterFileName"

    if (-not (Test-Path $parameterFilePath)) {
        throw "Could not find infrastructure parameter file: $parameterFilePath"
    }

    $parameterFile = Get-Content -Path $parameterFilePath -Raw | ConvertFrom-Json
    $resolvedLogin = $parameterFile.parameters.aadAdminLogin.value
    $resolvedObjectId = $parameterFile.parameters.aadAdminObjectId.value

    if ([string]::IsNullOrWhiteSpace($resolvedLogin) -or [string]::IsNullOrWhiteSpace($resolvedObjectId)) {
        throw "aadAdminLogin/aadAdminObjectId are required in $parameterFilePath for clean SQL provisioning."
    }

    return @{
        Login = $resolvedLogin
        ObjectId = $resolvedObjectId
        Source = $parameterFilePath
    }
}

function Wait-ForSqlFirewallAccess {
    param(
        [Parameter(Mandatory = $true)] [string]$SqlServerName,
        [Parameter(Mandatory = $true)] [string]$AdminUsername,
        [Parameter(Mandatory = $true)] [SecureString]$AdminPassword,
        [int]$TimeoutMinutes = 5,
        [int]$IntervalSeconds = 15
    )

    $serverFqdn = "$SqlServerName.database.windows.net"
    $timeoutSeconds = $TimeoutMinutes * 60
    $elapsed = 0

    Write-Host "  [WAIT] Polling SQL connectivity until firewall rule becomes active..." -ForegroundColor Yellow
    Write-Host "  [INFO] Continuing as soon as a real SQL login succeeds (max ${TimeoutMinutes} minutes)" -ForegroundColor Gray
    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan

    while ($elapsed -lt $timeoutSeconds) {
        $connection = $null
        $plainTextPassword = $null
        try {
            $plainTextPassword = Convert-SecureStringToPlainText -Value $AdminPassword
            $connectionString = "Server=tcp:$serverFqdn,1433;Initial Catalog=master;User ID=$AdminUsername;Password=$plainTextPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=5;"
            $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
            $connection.Open()
            Write-Host "]" -ForegroundColor Cyan
            Write-Host "  [OK] SQL firewall rule is active after $([math]::Round($elapsed / 60, 1)) minutes" -ForegroundColor Green
            return $true
        } catch {
            $message = $_.Exception.Message
            if ($message -match 'Login failed') {
                # Login failed means TCP connected — firewall IS open
                Write-Host "]" -ForegroundColor Cyan
                Write-Host "  [OK] SQL firewall rule is active after $([math]::Round($elapsed / 60, 1)) minutes (login rejected = port reachable)" -ForegroundColor Green
                return $true
            }
            if ($message -notmatch 'Client with IP address|Cannot open server|timed out|network-related') {
                Write-Host "]" -ForegroundColor Cyan
                Write-Host "  [WARN] Connectivity probe failed with unexpected error: $message" -ForegroundColor Yellow
                return $false
            }
        } finally {
            $plainTextPassword = $null
            $connectionString = $null
            if ($connection) {
                $connection.Dispose()
            }
        }

        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
        Write-Host "#" -NoNewline -ForegroundColor Green
    }

    Write-Host "]" -ForegroundColor Cyan
    Write-Host "  [WARN] SQL firewall rule was not confirmed active after ${TimeoutMinutes} minutes" -ForegroundColor Yellow
    return $false
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($BaseName)) {
    Write-Host "ERROR: BaseName parameter is required and cannot be empty" -ForegroundColor Red
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Location)) {
    Write-Host "ERROR: Location parameter is required and cannot be empty" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure SQL Database Provisioning" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Map environment name to Azure resource suffix (staging uses abbreviated 'stg' to match bootstrap)
$envSuffix = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }

# Generate resource names (must match bootstrap-enterprise-infra.ps1)
$rgName = "rg-$BaseName-$envSuffix"
$sqlServerName = "$BaseName-sql-$envSuffix"
$dbName = "OrderProcessingSystem_" + (Get-Culture).TextInfo.ToTitleCase($Environment)
# Prepend GitHub owner to webapp names for global uniqueness (matches bootstrap script)
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$envSuffix"
$uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$envSuffix"

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment"
Write-Host "  Resource Group: $rgName"
Write-Host "  SQL Server:     $sqlServerName"
Write-Host "  Database:       $dbName"
Write-Host "  Location:       $Location"
Write-Host ""

$aadAdmin = Resolve-AadAdminSettings -Environment $Environment -ExplicitLogin $AadAdminLogin -ExplicitObjectId $AadAdminObjectId
Write-Host "  SQL AAD Admin:  $($aadAdmin.Login)" -ForegroundColor Gray
Write-Host "  AAD Source:     $($aadAdmin.Source)" -ForegroundColor Gray
Write-Host ""

# Ensure Resource Group exists and is ready before proceeding
Write-Host "[0/7] Checking resource group..." -ForegroundColor Cyan

# Check if resource group exists
$rgExists = az group exists -n $rgName 2>&1
$existsCheckExitCode = $LASTEXITCODE

if ($existsCheckExitCode -ne 0) {
    Write-Host "  [ERROR] Failed to check resource group existence: $rgName" -ForegroundColor Red
    Write-Host "  [HINT] Verify Azure CLI authentication and subscription access" -ForegroundColor Yellow
    Write-Host "  [DETAIL] Exit code: $existsCheckExitCode, Output: $rgExists" -ForegroundColor Gray
    exit 1
}

if ($rgExists -eq 'false') {
    Write-Host "  [CREATE] Resource group does not exist, creating: $rgName" -ForegroundColor Yellow
    Write-Host "  [INFO] Location: $Location" -ForegroundColor Gray
    Write-Host "  [INFO] Tags: env=$Environment, app=$BaseName" -ForegroundColor Gray
    
    az group create -n $rgName -l $Location --tags "env=$Environment" "app=$BaseName" | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Failed to create resource group: $rgName" -ForegroundColor Red
        Write-Host "  [HINT] Check Azure subscription permissions and quotas" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  [OK] Resource group created: $rgName" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Resource group already exists: $rgName" -ForegroundColor Green
}

# Wait for resource group to be fully ready
Write-Host "  [WAIT] Verifying resource group readiness..." -ForegroundColor Cyan
$rgTimeout = 7 * 60  # Allow sufficient time for RG provisioning (reduced from 10 min)
$rgInterval = 30      # Check more frequently (every 30 seconds instead of 120)
$rgElapsed = 0
$rgReady = $false

while ($rgElapsed -lt $rgTimeout -and -not $rgReady) {
    # Suppress errors during polling - RG may not be ready yet (expected during provisioning)
    $rgInfoRaw = az group show -n $rgName --query "{name:name, state:properties.provisioningState}" -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $rgInfoRaw) {
        $rgInfo = $rgInfoRaw | ConvertFrom-Json
        if ($rgInfo -and $rgInfo.name -eq $rgName -and $rgInfo.state -eq 'Succeeded') { 
            $rgReady = $true
            break 
        }
    }
    if (-not $rgReady) { 
        Start-Sleep -Seconds $rgInterval
        $rgElapsed += $rgInterval 
    }
}

if (-not $rgReady) {
    Write-Host "  [ERROR] Resource group not ready after waiting $($rgTimeout/60) minutes: $rgName" -ForegroundColor Red
    Write-Host "  [HINT] Resource group may be in a transitioning state. Check Azure Portal." -ForegroundColor Yellow
    exit 1
}

Write-Host "  [OK] Resource group is ready: $rgName (state: Succeeded)" -ForegroundColor Green

# Retrieve SQL admin password from Key Vault if not provided
# Password is generated by bootstrap-enterprise-infra.ps1 and stored in KV — no human ever knows it
if (-not $AdminPassword) {
    $kvName = "kv-$BaseName-$envSuffix"
    Write-Host "[KV] AdminPassword not provided — retrieving from Key Vault '$kvName'..." -ForegroundColor Yellow
    $adminPasswordPlainText = az keyvault secret show --vault-name $kvName --name "sql-admin-password" --query value -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($adminPasswordPlainText)) {
        Write-Error "AdminPassword not provided and could not be retrieved from Key Vault '$kvName'. Run bootstrap-enterprise-infra.ps1 first to generate and store the password."
        exit 1
    }
    $AdminPassword = ConvertTo-SecureString $adminPasswordPlainText -AsPlainText -Force
    $adminPasswordPlainText = $null
    Write-Host "[OK] AdminPassword retrieved from Key Vault" -ForegroundColor Green
}

# Step 1: Check if SQL Server exists
Write-Host "[1/7] Checking SQL Server..." -ForegroundColor Cyan
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

    $adminPasswordPlainText = $null
    try {
        $adminPasswordPlainText = Convert-SecureStringToPlainText -Value $AdminPassword
        $sqlServer = az sql server create `
            --name $sqlServerName `
            --resource-group $rgName `
            --location $Location `
            --admin-user $AdminUsername `
            --admin-password $adminPasswordPlainText `
            --output json 2>$null | ConvertFrom-Json
    } finally {
        $adminPasswordPlainText = $null
    }

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

# Step 2: Configure Microsoft Entra admin
Write-Host "[2/7] Configuring SQL Microsoft Entra admin..." -ForegroundColor Cyan
$existingAadAdmin = $null
try {
    $aadAdminResult = az sql server ad-admin show `
        --server $sqlServerName `
        --resource-group $rgName `
        --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $aadAdminResult) {
        $existingAadAdmin = $aadAdminResult | ConvertFrom-Json
    }
} catch { }

$aadAdminNeedsUpdate = $true
if ($existingAadAdmin -and $existingAadAdmin.sid -eq $aadAdmin.ObjectId -and $existingAadAdmin.login -eq $aadAdmin.Login) {
    $aadAdminNeedsUpdate = $false
    Write-Host "  [EXISTS] SQL AAD admin already configured: $($aadAdmin.Login)" -ForegroundColor Green
}

if ($aadAdminNeedsUpdate) {
    if ($existingAadAdmin) {
        Write-Host "  [UPDATE] Updating SQL AAD admin to '$($aadAdmin.Login)'..." -ForegroundColor Yellow
        az sql server ad-admin update `
            --resource-group $rgName `
            --server $sqlServerName `
            --display-name $aadAdmin.Login `
            --object-id $aadAdmin.ObjectId `
            --output none 2>$null
    } else {
        Write-Host "  [CREATE] Creating SQL AAD admin '$($aadAdmin.Login)'..." -ForegroundColor Yellow
        az sql server ad-admin create `
            --resource-group $rgName `
            --server $sqlServerName `
            --display-name $aadAdmin.Login `
            --object-id $aadAdmin.ObjectId `
            --output none 2>$null
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Failed to configure SQL AAD admin for '$sqlServerName'" -ForegroundColor Red
        Write-Host "  [HINT] Verify the deployment identity can manage Microsoft Entra admins on Azure SQL" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  [OK] SQL AAD admin configured: $($aadAdmin.Login)" -ForegroundColor Green
}

# Step 3: Configure firewall rules
Write-Host "[3/7] Configuring firewall rules..." -ForegroundColor Cyan

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
# This handles dynamic IPs for GitHub Actions runners and local execution
try {
    $myIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    Write-Host "  [INFO] Detected current IP: $myIp" -ForegroundColor Gray
    
    # Use a timestamped rule name to handle dynamic IPs better
    # This allows multiple rules if IP changes across different runs
    $ruleName = "AllowIP-" + $myIp.Replace(".", "-")
    
    $myIpRule = $null
    try {
        $checkResult = az sql server firewall-rule show `
            --name $ruleName `
            --server $sqlServerName `
            --resource-group $rgName --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $checkResult) {
            $myIpRule = $checkResult | ConvertFrom-Json
        }
    } catch { }
    
    if (-not $myIpRule) {
        Write-Host "  [CREATE] Adding firewall rule for IP: $myIp" -ForegroundColor Yellow
        az sql server firewall-rule create `
            --resource-group $rgName `
            --server $sqlServerName `
            --name $ruleName `
            --start-ip-address $myIp `
            --end-ip-address $myIp `
            --output none 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Firewall rule '$ruleName' created for IP $myIp" -ForegroundColor Green

            $firewallReady = Wait-ForSqlFirewallAccess -SqlServerName $sqlServerName -AdminUsername $AdminUsername -AdminPassword $AdminPassword -TimeoutMinutes 5 -IntervalSeconds 15
            if (-not $firewallReady) {
                Write-Host "  [INFO] Proceeding anyway because control-plane operations can continue; later SQL-connection steps may still need retry time" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [WARN] Failed to create firewall rule (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [EXISTS] Firewall rule '$ruleName' already exists for IP $myIp" -ForegroundColor Green
        Write-Host "  [INFO] Skipping wait time as rule already exists" -ForegroundColor Gray
    }
    
    # Clean up old IP rules to avoid accumulation
    # Keep the 10 most recent rules to handle IP changes across multiple runs
    # while preventing unlimited growth of firewall rules
    $maxIpRules = 10
    try {
        $allRules = az sql server firewall-rule list `
            --server $sqlServerName `
            --resource-group $rgName --output json 2>$null | ConvertFrom-Json
        
        $ipRules = $allRules | Where-Object { $_.name -like "AllowIP-*" } | Sort-Object name -Descending
        $rulesToDelete = $ipRules | Select-Object -Skip $maxIpRules
        
        foreach ($rule in $rulesToDelete) {
            Write-Host "  [CLEANUP] Removing old firewall rule: $($rule.name)" -ForegroundColor Gray
            az sql server firewall-rule delete `
                --name $rule.name `
                --server $sqlServerName `
                --resource-group $rgName --output none 2>$null
        }
    } catch {
        # Cleanup is best effort, don't fail if it doesn't work
        Write-Host "  [INFO] Firewall rule cleanup skipped" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [WARN] Could not detect or configure firewall for current IP" -ForegroundColor Yellow
    Write-Host "  [INFO] Connection may fail if not running from Azure services" -ForegroundColor Gray
}

# Step 4: Create database
Write-Host "[4/7] Creating database..." -ForegroundColor Cyan
$dbExists = $null
try {
    $checkResult = az sql db show --name $dbName --server $sqlServerName --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $checkResult) {
        $dbExists = $checkResult | ConvertFrom-Json
    }
} catch { }

if ($dbExists) {
    Write-Host "  [EXISTS] Database '$dbName' already exists" -ForegroundColor Green
} else {
    Write-Host "  [CREATE] Creating database '$dbName' (Basic tier)..." -ForegroundColor Yellow
    Write-Host "  [INFO] This typically takes 1-2 minutes..." -ForegroundColor Gray
    
    az sql db create `
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

# Step 4b: Create TenantC dedicated database (ADR-009)
# TenantC is a Dedicated-tier tenant — it needs its own Azure SQL database on the same server.
# run-database-migrations.ps1 will apply EF Core migrations against this catalog after this script.
# setup-sql-managed-identity.ps1 Step 5 will grant managed identity access once the DB exists.
Write-Host "[4b/7] Creating TenantC dedicated database..." -ForegroundColor Cyan
$tenantCDbName = "OrderProcessingSystem_TenantC_" + (Get-Culture).TextInfo.ToTitleCase($Environment)
$tenantCDbExists = $null
try {
    $checkResult = az sql db show --name $tenantCDbName --server $sqlServerName --resource-group $rgName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $checkResult) {
        $tenantCDbExists = $checkResult | ConvertFrom-Json
    }
} catch { }

if ($tenantCDbExists) {
    Write-Host "  [EXISTS] TenantC database '$tenantCDbName' already exists" -ForegroundColor Green
} else {
    Write-Host "  [CREATE] Creating TenantC database '$tenantCDbName' (Basic tier)..." -ForegroundColor Yellow
    Write-Host "  [INFO] This typically takes 1-2 minutes..." -ForegroundColor Gray

    az sql db create `
        --resource-group $rgName `
        --server $sqlServerName `
        --name $tenantCDbName `
        --service-objective Basic `
        --max-size 2GB `
        --zone-redundant false `
        --backup-storage-redundancy Local `
        --output json 2>$null | ConvertFrom-Json

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] TenantC database create accepted" -ForegroundColor Green
        Write-Host "  [WAIT] Polling for TenantC database readiness (max 5 min)..." -ForegroundColor Gray
        $tcDbReady = $false
        $tcDbElapsed = 0
        while ($tcDbElapsed -lt 300 -and -not $tcDbReady) {
            Start-Sleep -Seconds 10
            $tcDbElapsed += 10
            $tcShow = az sql db show --name $tenantCDbName --server $sqlServerName --resource-group $rgName --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and $tcShow) { $tcDbReady = $true; Write-Host "    [OK] TenantC database ready after $([math]::Round($tcDbElapsed/60,1)) min" -ForegroundColor Green }
        }
        if (-not $tcDbReady) { Write-Host "    [WARN] TenantC database readiness not confirmed after 5 min (continuing)" -ForegroundColor Yellow }
    } else {
        Write-Host "  [ERROR] Failed to create TenantC database (CLI exit code $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

# Step 5: Build connection strings
Write-Host "[5/7] Building connection strings..." -ForegroundColor Cyan
$fullyQualifiedDomain = "$sqlServerName.database.windows.net"
$appConnectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$dbName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default;"
$maskedAdminConnectionString = "Server=tcp:$fullyQualifiedDomain,1433;Initial Catalog=$dbName;User ID=$AdminUsername;Password=***;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
Write-Host "  [OK] Passwordless app connection string generated" -ForegroundColor Green
Write-Host "  [OK] TenantC database: $tenantCDbName" -ForegroundColor Green

# Step 6: Configure API App Service
if (-not $SkipAppServiceConfig) {
    Write-Host "[6/7] Configuring API App Service..." -ForegroundColor Cyan
    
    # First verify the app exists
    $apiAppExists = $null
    try {
        $apiAppExists = az webapp show --name $apiAppName --resource-group $rgName --query "name" -o tsv 2>$null
    } catch { }
    
    if (-not $apiAppExists -or $apiAppExists -ne $apiAppName) {
        Write-Host "  [ERROR] API App Service not found: $apiAppName" -ForegroundColor Red
        Write-Host "  [ERROR] Expected app name: $apiAppName" -ForegroundColor Red
        Write-Host "  [ERROR] Resource group: $rgName" -ForegroundColor Red
        Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "  [HINT] Ensure bootstrap-enterprise-infra.ps1 has completed successfully" -ForegroundColor Yellow
        Write-Host "  [HINT] Verify the app was created with the correct name (should include GitHub owner prefix)" -ForegroundColor Yellow
        exit 1
    }
    
    try {
        # Suppress output to avoid logging sensitive connection string
        az webapp config connection-string set `
            --name $apiAppName `
            --resource-group $rgName `
            --connection-string-type SQLAzure `
            --settings OrderProcessingSystemDbConnection="$appConnectionString" `
            --output none 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] API connection string configured successfully" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Failed to configure API connection string (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "  [ERROR] Command failed - check app name and permissions" -ForegroundColor Red
            Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  [ERROR] Exception while configuring API connection string: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
        exit 1
    }

    # Step 7: Configure UI App Service
    Write-Host "[7/7] Configuring UI App Service..." -ForegroundColor Cyan
    
    # First verify the app exists
    $uiAppExists = $null
    try {
        $uiAppExists = az webapp show --name $uiAppName --resource-group $rgName --query "name" -o tsv 2>$null
    } catch { }
    
    if (-not $uiAppExists -or $uiAppExists -ne $uiAppName) {
        Write-Host "  [ERROR] UI App Service not found: $uiAppName" -ForegroundColor Red
        Write-Host "  [ERROR] Expected app name: $uiAppName" -ForegroundColor Red
        Write-Host "  [ERROR] Resource group: $rgName" -ForegroundColor Red
        Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "  [HINT] Ensure bootstrap-enterprise-infra.ps1 has completed successfully" -ForegroundColor Yellow
        Write-Host "  [HINT] Verify the app was created with the correct name (should include GitHub owner prefix)" -ForegroundColor Yellow
        exit 1
    }
    
    try {
        # Suppress output to avoid logging sensitive connection string
        az webapp config connection-string set `
            --name $uiAppName `
            --resource-group $rgName `
            --connection-string-type SQLAzure `
            --settings OrderProcessingSystemDbConnection="$appConnectionString" `
            --output none 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] UI connection string configured successfully" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Failed to configure UI connection string (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "  [ERROR] Command failed - check app name and permissions" -ForegroundColor Red
            Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  [ERROR] Exception while configuring UI connection string: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [CRITICAL] Connection string configuration is REQUIRED for the application to function" -ForegroundColor Red
        exit 1
    }

    # Restart apps to apply configuration
    Write-Host ""
    Write-Host "[RESTART] Restarting App Services..." -ForegroundColor Cyan
    az webapp restart --name $apiAppName --resource-group $rgName 2>$null
    az webapp restart --name $uiAppName --resource-group $rgName 2>$null
    Start-Sleep -Seconds 5
    Write-Host "  [OK] App Services restarted" -ForegroundColor Green
} else {
    Write-Host "[6/7] Skipping App Service configuration (SkipAppServiceConfig)" -ForegroundColor Yellow
    Write-Host "[7/7] Skipping App Service configuration (SkipAppServiceConfig)" -ForegroundColor Yellow
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

Write-Host "App Connection String:" -ForegroundColor Cyan
Write-Host "  $appConnectionString"
Write-Host ""

Write-Host "Admin Connection String (masked):" -ForegroundColor Cyan
Write-Host "  $maskedAdminConnectionString"
Write-Host ""

Write-Host "Management:" -ForegroundColor Cyan
Write-Host "  Portal: https://portal.azure.com"
Write-Host "  Navigate: SQL databases -> $dbName -> Query editor"
Write-Host ""

Write-Host "TenantC Dedicated Database:" -ForegroundColor Cyan
Write-Host "  Database Name:  $tenantCDbName"
Write-Host "  Tier:           Basic (2GB)"
Write-Host "  Cost:           ~5 USD/month"
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Run database migrations (EF Core or SQL scripts) — includes TenantC dedicated DB"
Write-Host "  2. Run setup-sql-managed-identity.ps1 to create the contained DB user for the App Service identity"
Write-Host "  3. Test API: https://$apiAppName.azurewebsites.net"
Write-Host "  4. Test UI:  https://$uiAppName.azurewebsites.net"
Write-Host ""

# Output for CI/CD pipelines
Write-Host "CI/CD Output Variables:" -ForegroundColor Cyan
Write-Host "  SQL_SERVER_FQDN=$fullyQualifiedDomain"
Write-Host "  SQL_DATABASE_NAME=$dbName"
Write-Host "  SQL_ADMIN_USERNAME=$AdminUsername"
Write-Host ""

Write-Host "[SUCCESS] Azure SQL Database provisioned and configured" -ForegroundColor Green
Write-Host ""

exit 0
