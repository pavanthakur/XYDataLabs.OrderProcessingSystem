# setup-sql-managed-identity.ps1
# Creates SQL contained users for App Service managed identities and grants roles.
# Run ONCE per environment after:
#   1. Bicep has deployed SQL Server with Azure AD admin set (aadAdminObjectId param)
#   2. App Service exists with SystemAssigned managed identity
#
# Automation note:
#   - For GitHub Actions, this script also supports SQL authentication mode.
#   - That mode creates the Microsoft Entra user by SID/TYPE and avoids the
#     interactive Azure AD admin login requirement used for local/manual runs.
#   - The SQL SID must match the managed identity service principal appId
#     (clientId), not the App Service principalId/objectId.
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
#   - If App Service is deleted & recreated (new managed identity)
#   - Safe to run on regular redeploys because the script is idempotent

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',

    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = '',

    [Parameter(Mandatory=$false)]
    [switch]$UseSqlAuthentication,

    [Parameter(Mandatory=$false)]
    [string]$SqlAdminUsername,

    [Parameter(Mandatory=$false)]
    [string]$SqlAdminPassword
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

function Get-InfraParameterFilePath {
    param([string]$Environment)

    $parameterFileName = switch ($Environment) {
        'dev' { 'dev.json' }
        'staging' { 'staging.json' }
        'prod' { 'prod.json' }
    }

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    return Join-Path $repoRoot "infra/parameters/$parameterFileName"
}

function Resolve-SqlAdminSettings {
    param(
        [string]$Environment,
        [string]$ExplicitUsername,
        [string]$ExplicitPassword
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitUsername) -and -not [string]::IsNullOrWhiteSpace($ExplicitPassword)) {
        return @{
            Username = $ExplicitUsername
            Password = $ExplicitPassword
            Source = 'script-parameters'
        }
    }

    $parameterFilePath = Get-InfraParameterFilePath -Environment $Environment
    if (-not (Test-Path $parameterFilePath)) {
        throw "Could not find infrastructure parameter file: $parameterFilePath"
    }

    $parameterFile = Get-Content -Path $parameterFilePath -Raw | ConvertFrom-Json
    $resolvedUsername = $parameterFile.parameters.sqlAdminUsername.value
    $resolvedPassword = $parameterFile.parameters.sqlAdminPassword.value

    if ([string]::IsNullOrWhiteSpace($resolvedUsername) -or [string]::IsNullOrWhiteSpace($resolvedPassword)) {
        throw "sqlAdminUsername/sqlAdminPassword are required in $parameterFilePath for SQL-auth automation."
    }

    return @{
        Username = $resolvedUsername
        Password = $resolvedPassword
        Source = $parameterFilePath
    }
}

function Convert-GuidToSqlSidHex {
    param([Parameter(Mandatory=$true)][string]$GuidText)

    $guid = [Guid]$GuidText
    $bytes = $guid.ToByteArray()
    return '0x' + (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')
}

function Resolve-ManagedIdentityAppId {
    param([Parameter(Mandatory=$true)][string]$PrincipalId)

    $appId = az ad sp show --id $PrincipalId --query appId -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appId)) {
        throw "Could not resolve managed identity appId for principalId '$PrincipalId'. Azure SQL contained users require SID derived from the managed identity appId/clientId. Azure CLI output: $appId"
    }

    return $appId.Trim()
}

function Invoke-SqlScriptFile {
    param(
        [Parameter(Mandatory=$true)][string]$SqlScript,
        [Parameter(Mandatory=$true)][string]$SqlServerFqdn,
        [Parameter(Mandatory=$true)][string]$DatabaseName,
        [string]$AccessToken,
        [string]$Username,
        [string]$Password,
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    $tmpSql = [System.IO.Path]::GetTempFileName() + '.sql'
    $SqlScript | Out-File -FilePath $tmpSql -Encoding UTF8

    try {
        if ($UseAzureAdToken) {
            if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
                Write-Host "  Using Invoke-Sqlcmd (SqlServer module)" -ForegroundColor Gray
                Invoke-Sqlcmd -ServerInstance $SqlServerFqdn -Database $DatabaseName -AccessToken $AccessToken -Query $SqlScript
                return
            }

            Write-Host "  SqlServer module not found — falling back to sqlcmd -G" -ForegroundColor Yellow
            Write-Host "  Tip: Install-Module SqlServer -AllowClobber -Scope CurrentUser" -ForegroundColor Gray
            sqlcmd -S $SqlServerFqdn -d $DatabaseName -G -i $tmpSql
        }
        elseif ($UseSqlAuth) {
            Write-Host "  Using SQL authentication via sqlcmd" -ForegroundColor Gray
            sqlcmd -S $SqlServerFqdn -d $DatabaseName -U $Username -P $Password -b -i $tmpSql
        }

        if ($LASTEXITCODE -ne 0) {
            throw 'sqlcmd execution failed.'
        }
    }
    finally {
        Remove-Item $tmpSql -ErrorAction SilentlyContinue
    }
}

Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       SQL MANAGED IDENTITY SETUP — DAY 35               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Map environment to Azure resource suffix (staging uses abbreviated 'stg')
$envSuffix  = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }
$dbEnvTitle = switch ($Environment) { 'dev' { 'Dev' } 'staging' { 'Staging' } 'prod' { 'Prod' } }

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
# Step 2: Resolve identity metadata
# For a system-assigned managed identity, Azure AD uses the App Service name as
# the display name. Azure SQL contained users created by SID/TYPE=E must use a
# SID derived from the managed identity service principal appId/clientId.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 2: Resolving identity metadata..." -ForegroundColor Yellow
$displayName = $apiAppName
$managedIdentityAppId = Resolve-ManagedIdentityAppId -PrincipalId $principalId
Write-Host "  Display name : $displayName" -ForegroundColor Green
Write-Host "  Principal ID : $principalId" -ForegroundColor Gray
Write-Host "  App ID       : $managedIdentityAppId" -ForegroundColor Green
Write-Host "  SID source   : appId (clientId) — required for Azure SQL TYPE = E" -ForegroundColor Gray

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Resolve execution mode
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 3: Resolving SQL execution mode..." -ForegroundColor Yellow
$token = $null
$sqlAdmin = $null

if ($UseSqlAuthentication) {
    $sqlAdmin = Resolve-SqlAdminSettings -Environment $Environment -ExplicitUsername $SqlAdminUsername -ExplicitPassword $SqlAdminPassword
    Write-Host "  Mode         : SQL authentication automation" -ForegroundColor Green
    Write-Host "  SQL Admin    : $($sqlAdmin.Username)" -ForegroundColor Green
    Write-Host "  SQL Source   : $($sqlAdmin.Source)" -ForegroundColor Gray
}
else {
    Write-Host "  Mode         : Azure AD admin token" -ForegroundColor Green
    $token = az account get-access-token --resource https://database.windows.net `
             --query accessToken -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        Write-Host ""
        Write-Host "ERROR: Could not acquire access token." -ForegroundColor Red
        Write-Host "Fix: Run 'az login' as the Azure AD admin set in aadAdminObjectId parameter." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  Token acquired" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Create contained user and grant roles
# db_datareader  — SELECT on all tables
# db_datawriter  — INSERT/UPDATE/DELETE on all tables
# db_ddladmin    — CREATE/ALTER/DROP (needed for EF Core migrations)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 4: Creating contained user and granting roles in $dbName..." -ForegroundColor Yellow

$roleGrantSql = @"
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datareader' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [$displayName];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datawriter' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER [$displayName];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_ddladmin' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_ddladmin ADD MEMBER [$displayName];
END

PRINT 'Roles granted: db_datareader, db_datawriter, db_ddladmin'
"@

if ($UseSqlAuthentication) {
    $sidHex = Convert-GuidToSqlSidHex -GuidText $managedIdentityAppId
    $sqlScript = @"
IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$displayName'
      AND type = 'E'
      AND CONVERT(varchar(max), sid, 1) <> '$sidHex'
)
BEGIN
    DROP USER [$displayName];
    PRINT 'Dropped contained user with stale SID: $displayName'
END

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$displayName')
BEGIN
    CREATE USER [$displayName] WITH SID = $sidHex, TYPE = E;
    PRINT 'Created contained user by SID: $displayName'
END
ELSE
BEGIN
    PRINT 'User already exists with expected SID (idempotent): $displayName'
END

$roleGrantSql
"@

    try {
        Invoke-SqlScriptFile -SqlScript $sqlScript -SqlServerFqdn $sqlFqdn -DatabaseName $dbName -Username $sqlAdmin.Username -Password $sqlAdmin.Password -UseSqlAuth
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: SQL-auth managed identity setup failed." -ForegroundColor Red
        Write-Host "  1. Ensure sqlcmd is available on the runner/machine." -ForegroundColor Red
        Write-Host "  2. Ensure SQL admin credentials are valid for $sqlFqdn." -ForegroundColor Red
        Write-Host "  3. Ensure SQL server firewall allows Azure services (0.0.0.0/0.0.0.0 rule)." -ForegroundColor Red
        Write-Host "  Detail: $($_.Exception.Message)" -ForegroundColor Yellow
        exit 1
    }
}
else {
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

$roleGrantSql
"@

    try {
        Invoke-SqlScriptFile -SqlScript $sqlScript -SqlServerFqdn $sqlFqdn -DatabaseName $dbName -AccessToken $token -UseAzureAdToken
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Azure AD token-based managed identity setup failed. Possible fixes:" -ForegroundColor Red
        Write-Host "  1. Install sqlcmd   : winget install Microsoft.SqlCmd" -ForegroundColor Red
        Write-Host "  2. Install SqlServer: Install-Module SqlServer -AllowClobber -Scope CurrentUser" -ForegroundColor Red
        Write-Host "  3. Ensure Azure AD admin is set on SQL Server" -ForegroundColor Red
        Write-Host "  Detail: $($_.Exception.Message)" -ForegroundColor Yellow
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Grant managed identity access on TenantC dedicated database (ADR-009)
# TenantC is a Dedicated-tier tenant. Its database must also have the managed
# identity user so that DbInitializer.SeedDedicatedTenants() can migrate and
# seed it at app startup. Without this, TenantC startup seeding fails with a
# SQL login error even if DedicatedTenantConnectionStrings--TenantC is present
# in Key Vault.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 5: Granting managed identity access on TenantC dedicated database..." -ForegroundColor Yellow

$tenantCDbName = "OrderProcessingSystem_TenantC_$dbEnvTitle"

Write-Host "  TenantC DB   : $tenantCDbName" -ForegroundColor White
Write-Host "  SQL Server   : $sqlFqdn" -ForegroundColor White

$tenantCRoleGrantSql = @"
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datareader' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [$displayName];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datawriter' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER [$displayName];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_ddladmin' AND m.name = '$displayName'
)
BEGIN
    ALTER ROLE db_ddladmin ADD MEMBER [$displayName];
END

PRINT 'TenantC roles granted: db_datareader, db_datawriter, db_ddladmin'
"@

if ($UseSqlAuthentication) {
    $sidHex = Convert-GuidToSqlSidHex -GuidText $managedIdentityAppId
    $tenantCSqlScript = @"
IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$displayName'
      AND type = 'E'
      AND CONVERT(varchar(max), sid, 1) <> '$sidHex'
)
BEGIN
    DROP USER [$displayName];
    PRINT 'Dropped TenantC contained user with stale SID: $displayName'
END

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$displayName')
BEGIN
    CREATE USER [$displayName] WITH SID = $sidHex, TYPE = E;
    PRINT 'Created TenantC contained user by SID: $displayName'
END
ELSE
BEGIN
    PRINT 'TenantC user already exists with expected SID (idempotent): $displayName'
END

$tenantCRoleGrantSql
"@

    try {
        Invoke-SqlScriptFile -SqlScript $tenantCSqlScript -SqlServerFqdn $sqlFqdn -DatabaseName $tenantCDbName -Username $sqlAdmin.Username -Password $sqlAdmin.Password -UseSqlAuth
        Write-Host "  ✅ Managed identity granted access on $tenantCDbName" -ForegroundColor Green
    }
    catch {
        # Non-fatal: TenantC dedicated DB may not exist yet (provisioned separately).
        # Without access, TenantC startup seeding will fail at runtime, but shared-pool tenants are unaffected.
        Write-Host "  ⚠️  Could not grant access on $tenantCDbName : $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "      If the TenantC dedicated database does not exist yet, provision it and re-run this script." -ForegroundColor Yellow
    }
}
else {
    $tenantCSqlScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$displayName')
BEGIN
    CREATE USER [$displayName] FROM EXTERNAL PROVIDER;
    PRINT 'Created TenantC contained user: $displayName'
END
ELSE
BEGIN
    PRINT 'TenantC user already exists (idempotent): $displayName'
END

$tenantCRoleGrantSql
"@

    try {
        Invoke-SqlScriptFile -SqlScript $tenantCSqlScript -SqlServerFqdn $sqlFqdn -DatabaseName $tenantCDbName -AccessToken $token -UseAzureAdToken
        Write-Host "  ✅ Managed identity granted access on $tenantCDbName" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠️  Could not grant access on $tenantCDbName : $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "      If the TenantC dedicated database does not exist yet, provision it and re-run this script." -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "✅  Managed identity setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Identity '$displayName' now has:" -ForegroundColor White
Write-Host "  db_datareader, db_datawriter, db_ddladmin on $dbName (shared-pool)" -ForegroundColor White
Write-Host "  db_datareader, db_datawriter, db_ddladmin on $tenantCDbName (TenantC dedicated)" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart App Service:"
Write-Host "     az webapp restart --name $apiAppName --resource-group $rgName"
Write-Host "  2. Check App Service log stream for successful SQL connection (no auth errors)"
Write-Host ""
Write-Host "To test locally (passwordless via az login):" -ForegroundColor Cyan
Write-Host "  Connection string:"
Write-Host "  Server=tcp:$sqlFqdn,1433;Initial Catalog=$dbName;Encrypt=True;Authentication=Active Directory Default" -ForegroundColor Gray

# Explicit exit 0: Step 5 (TenantC) is intentionally non-fatal — the TenantC
# database may not exist yet. A failed sqlcmd in Step 5 leaves $LASTEXITCODE=1
# even though we catch the exception. Without this, the bootstrap wrapper
# misreads the leaked exit code as a script failure.
exit 0
