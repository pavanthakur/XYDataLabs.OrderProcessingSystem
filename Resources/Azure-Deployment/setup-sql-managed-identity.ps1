# setup-sql-managed-identity.ps1
# Creates SQL contained users for App Service managed identities and grants roles.
# Run ONCE per environment after:
#   1. Bicep has deployed SQL Server with Azure AD admin set (aadAdminObjectId param)
#   2. App Service exists with SystemAssigned managed identity
#
# Prerequisites:
#   - az login (logged in as the Azure AD admin set in aadAdminObjectId parameter file)
#   - SqlServer PowerShell module (preferred):
#       Install-Module -Name SqlServer -AllowClobber -Scope CurrentUser
#   - OR: sqlcmd installed: winget install Microsoft.SqlCmd
#
# Usage:
#   .\setup-sql-managed-identity.ps1 -Environment dev
#   .\setup-sql-managed-identity.ps1 -Environment staging
#   .\setup-sql-managed-identity.ps1 -Environment prod
#
# When to re-run:
#   - First time per environment (one-off setup)
#   - If App Service is deleted & recreated (new managed identity principal ID)
#   - Never needed on regular redeploys

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',

    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur'
)

$ErrorActionPreference = 'Stop'

Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       SQL MANAGED IDENTITY SETUP — DAY 35               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Map environment to Azure resource suffix (staging uses abbreviated 'stg')
$envSuffix  = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }
$dbEnvTitle = $envSuffix.Substring(0,1).ToUpper() + $envSuffix.Substring(1)

$rgName     = "rg-$BaseName-$envSuffix"
$sqlFqdn    = "$BaseName-sql-$envSuffix.database.windows.net"
$dbName     = "OrderProcessingSystem_$dbEnvTitle"
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$envSuffix"

Write-Host "Environment  : $Environment  ($envSuffix)" -ForegroundColor White
Write-Host "Resource Grp : $rgName"         -ForegroundColor White
Write-Host "SQL Server   : $sqlFqdn"        -ForegroundColor White
Write-Host "Database     : $dbName"         -ForegroundColor White
Write-Host "API App      : $apiAppName"     -ForegroundColor White
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Get App Service managed identity principal ID
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 1: Getting App Service managed identity..." -ForegroundColor Yellow
$principalId = az webapp identity show --name $apiAppName --resource-group $rgName `
               --query principalId -o tsv 2>&1

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
    Write-Host ""
    Write-Host "ERROR: Could not retrieve managed identity for $apiAppName" -ForegroundColor Red
    Write-Host "Possible causes:" -ForegroundColor Red
    Write-Host "  - App Service $apiAppName does not exist in $rgName" -ForegroundColor Red
    Write-Host "  - App Service does not have SystemAssigned identity enabled" -ForegroundColor Red
    Write-Host "Fix: Re-run Bicep deployment — hosting.bicep enables identity: { type: 'SystemAssigned' }" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Principal ID : $principalId" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Resolve App Service display name in Azure AD
# System-assigned managed identity display name = App Service name
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 2: Resolving identity display name in Azure AD..." -ForegroundColor Yellow
$displayName = az ad sp show --id $principalId --query displayName -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($displayName)) {
    $displayName = $apiAppName
    Write-Host "  Display name : $displayName (using app name as fallback)" -ForegroundColor Yellow
} else {
    Write-Host "  Display name : $displayName" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Get Azure AD access token for Azure SQL
# Must be called as the Azure AD admin configured in aadAdminObjectId param
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 3: Acquiring Azure AD access token for SQL..." -ForegroundColor Yellow
$token = az account get-access-token --resource https://database.windows.net `
         --query accessToken -o tsv 2>&1

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    Write-Host ""
    Write-Host "ERROR: Could not acquire access token." -ForegroundColor Red
    Write-Host "Fix: Run 'az login' as the Azure AD admin set in aadAdminObjectId parameter." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Token acquired" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Create contained user and grant roles
# db_datareader  — SELECT on all tables
# db_datawriter  — INSERT/UPDATE/DELETE on all tables
# db_ddladmin    — CREATE/ALTER/DROP (needed for EF Core migrations)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 4: Creating contained user and granting roles in $dbName..." -ForegroundColor Yellow

$sqlScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$displayName')
BEGIN
    CREATE USER [$displayName] FROM EXTERNAL PROVIDER;
    PRINT 'Created contained user: $displayName'
END
ELSE
BEGIN
    PRINT 'User already exists (idempotent): $displayName'
END

ALTER ROLE db_datareader ADD MEMBER [$displayName];
ALTER ROLE db_datawriter ADD MEMBER [$displayName];
ALTER ROLE db_ddladmin   ADD MEMBER [$displayName];

PRINT 'Roles granted: db_datareader, db_datawriter, db_ddladmin'
"@

# Try Invoke-Sqlcmd (SqlServer module) first — cleaner Azure AD token auth
if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
    Write-Host "  Using Invoke-Sqlcmd (SqlServer module)" -ForegroundColor Gray
    Invoke-Sqlcmd -ServerInstance $sqlFqdn -Database $dbName -AccessToken $token -Query $sqlScript
} else {
    # Fallback: sqlcmd CLI with Azure AD Default auth (-G flag)
    Write-Host "  SqlServer module not found — falling back to sqlcmd -G" -ForegroundColor Yellow
    Write-Host "  Tip: Install-Module SqlServer -AllowClobber -Scope CurrentUser" -ForegroundColor Gray

    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    $sqlScript | Out-File -FilePath $tmpSql -Encoding UTF8
    try {
        sqlcmd -S $sqlFqdn -d $dbName -G -i $tmpSql
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "ERROR: sqlcmd failed. Possible fixes:" -ForegroundColor Red
            Write-Host "  1. Install sqlcmd   : winget install Microsoft.SqlCmd" -ForegroundColor Red
            Write-Host "  2. Install SqlServer: Install-Module SqlServer -AllowClobber -Scope CurrentUser" -ForegroundColor Red
            Write-Host "  3. Ensure Azure AD admin is set on SQL Server (re-run Bicep with aadAdminObjectId filled in)" -ForegroundColor Red
            exit 1
        }
    } finally {
        Remove-Item $tmpSql -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "✅  Managed identity setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Identity '$displayName' now has:" -ForegroundColor White
Write-Host "  db_datareader, db_datawriter, db_ddladmin on $dbName" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Fill in aadAdminLogin + aadAdminObjectId in infra/parameters/$Environment.json"
Write-Host "  2. Re-deploy Bicep (hosting.bicep now sends passwordless connection string to App Service):"
Write-Host "     az deployment sub create --location centralindia --template-file infra/main.bicep --parameters @infra/parameters/$Environment.json"
Write-Host "  3. Restart App Service:"
Write-Host "     az webapp restart --name $apiAppName --resource-group $rgName"
Write-Host "  4. Check App Service log stream for successful SQL connection (no auth errors)"
Write-Host ""
Write-Host "To test locally (passwordless via az login):" -ForegroundColor Cyan
Write-Host "  Connection string:"
Write-Host "  Server=tcp:$sqlFqdn,1433;Initial Catalog=$dbName;Encrypt=True;Authentication=Active Directory Default" -ForegroundColor Gray
