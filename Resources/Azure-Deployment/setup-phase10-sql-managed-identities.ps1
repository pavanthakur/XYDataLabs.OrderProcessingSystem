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

function Invoke-AzText {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $result = & az @Arguments -o tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed. Azure CLI output: $result"
    }

    return [string]::Join([Environment]::NewLine, @($result | ForEach-Object { $_.ToString() })).Trim()
}

function Invoke-SqlQueryRows {
    param(
        [Parameter(Mandatory = $true)][string]$SqlServerFqdn,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [Parameter(Mandatory = $true)][string]$SqlQuery,
        [string]$AccessToken,
        [string]$Username,
        [string]$Password,
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    Add-Type -AssemblyName System.Data | Out-Null

    $connectionString = if ($UseSqlAuth) {
        "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$DatabaseName;Persist Security Info=False;User ID=$Username;Password=$Password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    }
    else {
        "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$DatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    }

    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    if ($UseAzureAdToken) {
        $connection.AccessToken = $AccessToken
    }

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $SqlQuery
        $command.CommandTimeout = 60

        $reader = $command.ExecuteReader()
        $rows = New-Object 'System.Collections.Generic.List[object]'

        try {
            while ($reader.Read()) {
                $row = [ordered]@{}
                for ($index = 0; $index -lt $reader.FieldCount; $index++) {
                    $row[$reader.GetName($index)] = if ($reader.IsDBNull($index)) { $null } else { $reader.GetValue($index) }
                }

                $rows.Add([pscustomobject]$row)
            }
        }
        finally {
            $reader.Dispose()
        }

        return @($rows)
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
    }
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

    Add-Type -AssemblyName System.Data | Out-Null

    $connectionString = if ($UseSqlAuth) {
        "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$DatabaseName;Persist Security Info=False;User ID=$Username;Password=$Password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    }
    else {
        "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$DatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    }

    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    if ($UseAzureAdToken) {
        $connection.AccessToken = $AccessToken
    }

    $batches = [regex]::Split($SqlScript, '(?im)^\s*GO\s*(?:--.*)?$') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    try {
        $connection.Open()
        foreach ($batch in $batches) {
            $command = $connection.CreateCommand()
            $command.CommandText = $batch
            $command.CommandTimeout = 120
            try {
                [void]$command.ExecuteNonQuery()
            }
            finally {
                $command.Dispose()
            }
        }
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
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

function Get-KeyVaultName {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentBaseName,
        [Parameter(Mandatory = $true)][string]$CurrentEnvironmentSuffix
    )

    $shortBaseName = $CurrentBaseName.Substring(0, [Math]::Min(15, $CurrentBaseName.Length))
    return "kv-$shortBaseName-$CurrentEnvironmentSuffix"
}

function Resolve-DedicatedDatabaseNameFromConnectionString {
    param([Parameter(Mandatory = $true)][string]$ConnectionString)

    $match = [regex]::Match($ConnectionString, '(?i)(?:Initial\s+Catalog|Database)\s*=\s*([^;]+)')
    if (-not $match.Success) {
        throw "Dedicated tenant connection string does not contain an Initial Catalog/Database segment."
    }

    return $match.Groups[1].Value.Trim()
}

function Get-SqlExecutionModeSplat {
    param(
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    $mode = @{}
    if ($UseSqlAuth.IsPresent) {
        $mode.UseSqlAuth = $true
    }
    elseif ($UseAzureAdToken.IsPresent) {
        $mode.UseAzureAdToken = $true
    }

    return $mode
}

function Get-ActiveDedicatedTenantDatabases {
    param(
        [Parameter(Mandatory = $true)][string]$SqlServerFqdn,
        [Parameter(Mandatory = $true)][string]$SharedDatabaseName,
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [string]$AccessToken,
        [string]$SqlUsername,
        [string]$SqlPassword,
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    $query = @"
SELECT
    [Code] AS TenantCode,
    [Name] AS TenantName,
    [PaymentProviderCode]
FROM [dbo].[Tenants]
WHERE [Status] = N'Active'
  AND [TenantTier] = N'Dedicated'
ORDER BY [Code];
"@

    $authMode = Get-SqlExecutionModeSplat -UseAzureAdToken:$UseAzureAdToken -UseSqlAuth:$UseSqlAuth
    $tenants = @(Invoke-SqlQueryRows `
        -SqlServerFqdn $SqlServerFqdn `
        -DatabaseName $SharedDatabaseName `
        -SqlQuery $query `
        -AccessToken $AccessToken `
        -Username $SqlUsername `
        -Password $SqlPassword `
        @authMode)

    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($tenant in $tenants) {
        $tenantCode = [string]$tenant.TenantCode
        $secretName = "DedicatedTenantConnectionStrings--$tenantCode"
        $connectionString = Invoke-AzText `
            -Arguments @('keyvault', 'secret', 'show', '--vault-name', $KeyVaultName, '--name', $secretName, '--query', 'value') `
            -Operation "Resolve Key Vault secret '$secretName'"

        if ([string]::IsNullOrWhiteSpace($connectionString)) {
            throw "Dedicated tenant '$tenantCode' is active in the tenant registry, but Key Vault secret '$secretName' is missing or empty."
        }

        $results.Add([pscustomobject]@{
                TenantCode = $tenantCode
                TenantName = [string]$tenant.TenantName
                PaymentProviderCode = [string]$tenant.PaymentProviderCode
                SecretName = $secretName
                DatabaseName = Resolve-DedicatedDatabaseNameFromConnectionString -ConnectionString $connectionString
            })
    }

    return @($results)
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
$keyVaultName = Get-KeyVaultName -CurrentBaseName $BaseName -CurrentEnvironmentSuffix $envSuffix

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
Write-Host "Key Vault        : $keyVaultName" -ForegroundColor White
Write-Host "Shared Database  : $sharedDatabaseName" -ForegroundColor White
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
$topologyAuthMode = if ($UseSqlAuthentication) {
    Get-SqlExecutionModeSplat -UseSqlAuth
}
else {
    Get-SqlExecutionModeSplat -UseAzureAdToken
}

$dedicatedTenantDatabases = @(Get-ActiveDedicatedTenantDatabases `
    -SqlServerFqdn $sqlFqdn `
    -SharedDatabaseName $sharedDatabaseName `
    -KeyVaultName $keyVaultName `
    -AccessToken $token `
    -SqlUsername $resolvedSqlUsername `
    -SqlPassword $resolvedSqlPassword `
    @topologyAuthMode)

if ($dedicatedTenantDatabases.Count -eq 0) {
    Write-Host 'Dedicated Databases: none active in tenant registry' -ForegroundColor Yellow
}
else {
    Write-Host 'Dedicated Databases discovered from tenant registry + Key Vault:' -ForegroundColor White
    foreach ($dedicatedDatabase in $dedicatedTenantDatabases) {
        Write-Host "  - $($dedicatedDatabase.TenantCode) -> $($dedicatedDatabase.DatabaseName) [$($dedicatedDatabase.PaymentProviderCode)]" -ForegroundColor Gray
    }
}
Write-Host ''

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
        @topologyAuthMode

    foreach ($dedicatedDatabase in $dedicatedTenantDatabases) {
        Grant-IdentityAccessToDatabase `
            -DisplayName $resourceName `
            -ManagedIdentityAppId $appId `
            -SqlServerFqdn $sqlFqdn `
            -DatabaseName $dedicatedDatabase.DatabaseName `
            -AccessToken $token `
            -SqlUsername $resolvedSqlUsername `
            -SqlPassword $resolvedSqlPassword `
            @topologyAuthMode
    }

    if ($dedicatedTenantDatabases.Count -eq 0) {
        Write-Host '  Granted shared database access.' -ForegroundColor Green
    }
    else {
        Write-Host '  Granted shared + dedicated database access.' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Phase 10 runtime SQL identity setup complete.' -ForegroundColor Green
exit 0
