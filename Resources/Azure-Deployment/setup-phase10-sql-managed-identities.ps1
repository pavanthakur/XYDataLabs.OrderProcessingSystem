# setup-phase10-sql-managed-identities.ps1
# Grants Azure SQL contained users and runtime roles to the actual Phase 10
# managed identities used by Container Apps and the Function App.
#
# This script is intended for the Phase 10 Azure deploy path where the runtime
# uses:
#   - Azure Container Apps for gateway/orders/payments/inventory/notifications/ui
#   - Azure Functions App for DLQ/replay processing
#
# The legacy setup-sql-managed-identity.ps1 script targets the old App Service
# API identity and is not sufficient for the Phase 10 runtime hosts.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$BaseName = 'orderprocessing',

    [Parameter(Mandatory = $false)]
    [switch]$UseSqlAuthentication,

    [Parameter(Mandatory = $false)]
    [string]$SqlAdminUsername,

    [Parameter(Mandatory = $false)]
    [string]$SqlAdminPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'branch-policy.ps1')
$environmentDescriptor = Get-GitHubEnvironmentDescriptor -Policy (Get-GitHubBranchPolicy) -EnvironmentKey $Environment

function Get-InfraParameterFilePath {
    param([string]$Environment)

    $parameterFileName = switch ($Environment) {
        'dev' { 'phase10-dev.json' }
        'staging' { 'phase10-staging.json' }
        'prod' { 'phase10-prod.json' }
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
            Source   = 'script-parameters'
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
        Source   = $parameterFilePath
    }
}

function Convert-GuidToSqlSidHex {
    param([Parameter(Mandatory = $true)][string]$GuidText)

    $guid = [Guid]$GuidText
    $bytes = $guid.ToByteArray()
    return '0x' + (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')
}

function Resolve-ManagedIdentityAppId {
    param([Parameter(Mandatory = $true)][string]$PrincipalId)

    $appId = az ad sp show --id $PrincipalId --query appId -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appId)) {
        throw "Could not resolve managed identity appId for principalId '$PrincipalId'. Azure CLI output: $appId"
    }

    return $appId.Trim()
}

function Invoke-SqlScriptFile {
    param(
        [Parameter(Mandatory = $true)][string]$SqlScript,
        [Parameter(Mandatory = $true)][string]$SqlServerFqdn,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
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
                Invoke-Sqlcmd -ServerInstance $SqlServerFqdn -Database $DatabaseName -AccessToken $AccessToken -Query $SqlScript
                return
            }

            sqlcmd -S $SqlServerFqdn -d $DatabaseName -G -i $tmpSql
        }
        elseif ($UseSqlAuth) {
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

function Resolve-ContainerAppPrincipalId {
    param(
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$ContainerAppName
    )

    $principalId = az containerapp identity show `
        --resource-group $ResourceGroupName `
        --name $ContainerAppName `
        --query principalId `
        -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
        throw "Could not resolve managed identity principalId for Container App '$ContainerAppName'. Azure CLI output: $principalId"
    }

    return $principalId.Trim()
}

function Resolve-FunctionAppPrincipalId {
    param(
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$FunctionAppName
    )

    $principalId = az functionapp identity show `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --query principalId `
        -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
        throw "Could not resolve managed identity principalId for Function App '$FunctionAppName'. Azure CLI output: $principalId"
    }

    return $principalId.Trim()
}

function Grant-IdentityAccessToDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$ManagedIdentityAppId,
        [Parameter(Mandatory = $true)][string]$SqlServerFqdn,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [string]$AccessToken,
        [string]$SqlUsername,
        [string]$SqlPassword,
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    $roleGrantSql = @"
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datareader' AND m.name = '$DisplayName'
)
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [$DisplayName];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = 'db_datawriter' AND m.name = '$DisplayName'
)
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER [$DisplayName];
END

PRINT 'Roles granted: db_datareader, db_datawriter'
"@

    if ($UseSqlAuth) {
        $sidHex = Convert-GuidToSqlSidHex -GuidText $ManagedIdentityAppId
        $sqlScript = @"
IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$DisplayName'
      AND type = 'E'
      AND CONVERT(varchar(max), sid, 1) <> '$sidHex'
)
BEGIN
    DROP USER [$DisplayName];
    PRINT 'Dropped contained user with stale SID: $DisplayName'
END

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$DisplayName')
BEGIN
    CREATE USER [$DisplayName] WITH SID = $sidHex, TYPE = E;
    PRINT 'Created contained user by SID: $DisplayName'
END
ELSE
BEGIN
    PRINT 'User already exists with expected SID (idempotent): $DisplayName'
END

$roleGrantSql
"@

        Invoke-SqlScriptFile `
            -SqlScript $sqlScript `
            -SqlServerFqdn $SqlServerFqdn `
            -DatabaseName $DatabaseName `
            -Username $SqlUsername `
            -Password $SqlPassword `
            -UseSqlAuth
        return
    }

    $sqlScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$DisplayName')
BEGIN
    CREATE USER [$DisplayName] FROM EXTERNAL PROVIDER;
    PRINT 'Created contained user: $DisplayName'
END
ELSE
BEGIN
    PRINT 'User already exists (idempotent): $DisplayName'
END

$roleGrantSql
"@

    Invoke-SqlScriptFile `
        -SqlScript $sqlScript `
        -SqlServerFqdn $SqlServerFqdn `
        -DatabaseName $DatabaseName `
        -AccessToken $AccessToken `
        -UseAzureAdToken
}

$envSuffix = $environmentDescriptor.ResourceSuffix
$dbEnvTitle = $environmentDescriptor.AzureSqlDatabaseSuffix
$resourceGroupName = "rg-$BaseName-$envSuffix"
$sqlFqdn = "$BaseName-sql-$envSuffix.database.windows.net"
$sharedDatabaseName = "OrderProcessingSystem_$dbEnvTitle"
$tenantCDatabaseName = "OrderProcessingSystem_TenantC_$dbEnvTitle"

$runtimeIdentities = @(
    @{
        Kind = 'ContainerApp'
        ResourceName = "$BaseName-ord-$envSuffix"
        FriendlyName = 'Orders'
    }
    @{
        Kind = 'ContainerApp'
        ResourceName = "$BaseName-pay-$envSuffix"
        FriendlyName = 'Payments'
    }
    @{
        Kind = 'ContainerApp'
        ResourceName = "$BaseName-inv-$envSuffix"
        FriendlyName = 'Inventory'
    }
    @{
        Kind = 'ContainerApp'
        ResourceName = "$BaseName-notif-$envSuffix"
        FriendlyName = 'Notifications'
    }
    @{
        Kind = 'FunctionApp'
        ResourceName = "$BaseName-functions-$envSuffix"
        FriendlyName = 'Functions'
    }
)

Write-Host "Configuring Phase 10 SQL access for runtime identities..." -ForegroundColor Cyan
Write-Host "Environment      : $Environment ($envSuffix)" -ForegroundColor White
Write-Host "Resource Group   : $resourceGroupName" -ForegroundColor White
Write-Host "SQL Server       : $sqlFqdn" -ForegroundColor White
Write-Host "Shared Database  : $sharedDatabaseName" -ForegroundColor White
Write-Host "TenantC Database : $tenantCDatabaseName" -ForegroundColor White
Write-Host ''

$token = $null
$sqlAdmin = $null

if ($UseSqlAuthentication) {
    $sqlAdmin = Resolve-SqlAdminSettings -Environment $Environment -ExplicitUsername $SqlAdminUsername -ExplicitPassword $SqlAdminPassword
    Write-Host "Execution mode   : SQL authentication automation" -ForegroundColor Green
    Write-Host "SQL Admin        : $($sqlAdmin.Username)" -ForegroundColor Green
}
else {
    Write-Host "Execution mode   : Azure AD admin token" -ForegroundColor Green
    $token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not acquire Azure SQL access token. Run 'az login' as the Azure AD admin set on the SQL server."
    }
}

$resolvedSqlUsername = if ($null -ne $sqlAdmin) { [string]$sqlAdmin.Username } else { '' }
$resolvedSqlPassword = if ($null -ne $sqlAdmin) { [string]$sqlAdmin.Password } else { '' }

foreach ($identity in $runtimeIdentities) {
    $resourceName = [string]$identity.ResourceName
    $friendlyName = [string]$identity.FriendlyName
    $kind = [string]$identity.Kind

    Write-Host ''
    Write-Host "Granting SQL access for $friendlyName ($resourceName)..." -ForegroundColor Yellow

    $principalId = if ($kind -eq 'ContainerApp') {
        Resolve-ContainerAppPrincipalId -ResourceGroupName $resourceGroupName -ContainerAppName $resourceName
    }
    else {
        Resolve-FunctionAppPrincipalId -ResourceGroupName $resourceGroupName -FunctionAppName $resourceName
    }

    $appId = Resolve-ManagedIdentityAppId -PrincipalId $principalId

    Write-Host "  Principal ID : $principalId" -ForegroundColor Gray
    Write-Host "  App ID       : $appId" -ForegroundColor Gray

    Grant-IdentityAccessToDatabase `
        -DisplayName $resourceName `
        -ManagedIdentityAppId $appId `
        -SqlServerFqdn $sqlFqdn `
        -DatabaseName $sharedDatabaseName `
        -AccessToken $token `
        -SqlUsername $resolvedSqlUsername `
        -SqlPassword $resolvedSqlPassword `
        -UseAzureAdToken:(!$UseSqlAuthentication) `
        -UseSqlAuth:$UseSqlAuthentication

    Grant-IdentityAccessToDatabase `
        -DisplayName $resourceName `
        -ManagedIdentityAppId $appId `
        -SqlServerFqdn $sqlFqdn `
        -DatabaseName $tenantCDatabaseName `
        -AccessToken $token `
        -SqlUsername $resolvedSqlUsername `
        -SqlPassword $resolvedSqlPassword `
        -UseAzureAdToken:(!$UseSqlAuthentication) `
        -UseSqlAuth:$UseSqlAuthentication

    Write-Host "  Granted shared + TenantC database access." -ForegroundColor Green
}

Write-Host ''
Write-Host 'Phase 10 runtime SQL identity setup complete.' -ForegroundColor Green
exit 0
