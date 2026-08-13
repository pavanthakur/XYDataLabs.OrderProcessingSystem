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
        [Parameter(Mandatory = $true)][string]$Operation,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3,
        [ValidateRange(1, 30)][int]$InitialDelaySeconds = 2
    )

    $lastOutput = ''
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = & az @Arguments -o tsv 2>&1
        $exitCode = $LASTEXITCODE
        $lastOutput = [string]::Join([Environment]::NewLine, @($result | ForEach-Object { $_.ToString() })).Trim()

        if ($exitCode -eq 0) {
            return $lastOutput
        }

        if ($attempt -lt $MaxAttempts) {
            $delaySeconds = [int]($InitialDelaySeconds * [Math]::Pow(2, $attempt - 1))
            Write-Host "$Operation attempt $attempt/$MaxAttempts failed; retrying in $delaySeconds second(s). Azure CLI output: $lastOutput" -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
        }
    }

    throw "$Operation failed after $MaxAttempts attempt(s). Azure CLI output: $lastOutput"
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

        # PowerShell 7 can throw "Argument types do not match" when @() attempts
        # to materialize a generic List[object] containing PSCustomObject values.
        return $rows.ToArray()
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

function Resolve-UserAssignedIdentityPrincipalId {
    param(
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$IdentityName
    )

    $principalId = az identity show `
        --resource-group $ResourceGroupName `
        --name $IdentityName `
        --query principalId `
        -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
        throw "Could not resolve principalId for user-assigned identity '$IdentityName'. Azure CLI output: $principalId"
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

function Get-Phase10FailureClassification {
    param([Parameter(Mandatory = $true)][string]$Message)

    $classification = switch -Regex ($Message) {
        'AADSTS700024|Client assertion is not within its valid time range' { 'AzureOidcTokenExpired'; break }
        'SecretNotFound|was not found in this key vault|missing or empty' { 'ConfigurationContract.MissingSecret'; break }
        'Forbidden|AuthorizationFailed|AccessDenied|does not have secrets (get|list) permission' { 'AzureAuthorization'; break }
        'Login failed for user|SqlException.*18456' { 'SqlAuthentication'; break }
        'Client with IP address|firewall|network-related or instance-specific' { 'SqlNetwork'; break }
        'ManagedIdentity|principalId|service principal' { 'ManagedIdentityResolution'; break }
        'Argument types do not match' { 'PowerShellRuntime'; break }
        default { 'Unhandled' }
    }

    return $classification
}

function Write-Phase10FailureDiagnostics {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Stage
    )

    $message = [string]$ErrorRecord.Exception.Message
    $classification = Get-Phase10FailureClassification -Message $message
    $location = if ($null -ne $ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage)) {
        ($ErrorRecord.InvocationInfo.PositionMessage -replace "`r?`n", ' ' -replace '\s+', ' ').Trim()
    }
    else {
        'Unavailable'
    }

    Write-Host ''
    Write-Host 'Phase 10 SQL identity setup failed.' -ForegroundColor Red
    Write-Host "  Stage          : $Stage" -ForegroundColor Red
    Write-Host "  Classification : $classification" -ForegroundColor Red
    Write-Host "  Error type     : $($ErrorRecord.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "  Error id       : $($ErrorRecord.FullyQualifiedErrorId)" -ForegroundColor Red
    Write-Host "  Location       : $location" -ForegroundColor Red
    Write-Host "  Message        : $message" -ForegroundColor Red

    if ($classification -eq 'AzureOidcTokenExpired') {
        Write-Host '  Guidance       : Refresh Azure OIDC login in the workflow immediately before this step or before any post-failure diagnostics that still need Azure CLI access.' -ForegroundColor Yellow
    }

    $annotationMessage = $message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ACTIONS)) {
        Write-Host "::error title=Phase 10 SQL identity setup [$classification]::$annotationMessage"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        $summaryMessage = $message.Replace('|', '\|').Replace("`r", '').Replace("`n", '<br>')
        try {
            @"
### Phase 10 SQL identity setup failure

| Field | Value |
|---|---|
| Stage | $Stage |
| Classification | $classification |
| Environment | $Environment |
| Resource group | $resourceGroupName |
| SQL server | $sqlFqdn |
| Shared database | $sharedDatabaseName |
| Key Vault | $keyVaultName |
| Error type | $($ErrorRecord.Exception.GetType().FullName) |
| Error | $summaryMessage |

No secret values or connection-string credentials are included in this diagnostic.
"@ | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
        }
        catch {
            Write-Host "Could not append failure diagnostics to GITHUB_STEP_SUMMARY: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
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

    if ($UseSqlAuth) {
        $tenants = @(Invoke-SqlQueryRows `
            -SqlServerFqdn $SqlServerFqdn `
            -DatabaseName $SharedDatabaseName `
            -SqlQuery $query `
            -Username $SqlUsername `
            -Password $SqlPassword `
            -UseSqlAuth)
    }
    elseif ($UseAzureAdToken) {
        $tenants = @(Invoke-SqlQueryRows `
            -SqlServerFqdn $SqlServerFqdn `
            -DatabaseName $SharedDatabaseName `
            -SqlQuery $query `
            -AccessToken $AccessToken `
            -Username $SqlUsername `
            -Password $SqlPassword `
            -UseAzureAdToken)
    }
    else {
        $tenants = @(Invoke-SqlQueryRows `
            -SqlServerFqdn $SqlServerFqdn `
            -DatabaseName $SharedDatabaseName `
            -SqlQuery $query `
            -AccessToken $AccessToken `
            -Username $SqlUsername `
            -Password $SqlPassword)
    }

    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($tenant in $tenants) {
        $tenantCode = [string]$tenant.TenantCode
        $secretName = "DedicatedTenantConnectionStrings--$tenantCode"
        Write-Host "Validating dedicated topology contract: tenant '$tenantCode', secret '$secretName'." -ForegroundColor Gray

        try {
            $connectionString = Invoke-AzText `
                -Arguments @('keyvault', 'secret', 'show', '--vault-name', $KeyVaultName, '--name', $secretName, '--query', 'value') `
                -Operation "Resolve Key Vault secret '$secretName'"
        }
        catch {
            $cause = $_.Exception.Message
            throw "Dedicated tenant topology contract validation failed for tenant '$tenantCode'. Registry tier is Dedicated, so Key Vault '$KeyVaultName' must contain secret '$secretName'. Discovery came from the registry; this secret validates the provisioned database contract. Cause: $cause"
        }

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

    return $results.ToArray()
}

function Grant-IdentityAccessToDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$ManagedIdentityPrincipalId,
        [Parameter(Mandatory = $true)][string]$SqlServerFqdn,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [string]$AccessToken,
        [string]$SqlUsername,
        [string]$SqlPassword,
        [switch]$UseAzureAdToken,
        [switch]$UseSqlAuth
    )

    # Azure SQL maps the token's oid claim to the canonical Microsoft Entra
    # object/principal GUID bytes. Guid.ToByteArray() uses CLR mixed-endian
    # layout and creates a valid external principal that cannot match the token.
    $managedIdentitySid = '0x' + ([System.Guid]::Parse($ManagedIdentityPrincipalId)).ToString('N').ToUpperInvariant()

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
        $sqlScript = @"
IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$DisplayName'
      AND type = 'E'
      AND sid <> $managedIdentitySid
)
BEGIN
    DROP USER [$DisplayName];
    PRINT 'Dropped contained external user whose SID did not match: $DisplayName'
END

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$DisplayName')
BEGIN
    CREATE USER [$DisplayName] WITH SID = $managedIdentitySid, TYPE = E;
    PRINT 'Created contained external user with explicit object SID: $DisplayName'
END
ELSE
BEGIN
    PRINT 'User already exists with the expected object SID: $DisplayName'
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

$script:CurrentStage = 'Initialize SQL identity setup'
trap {
    Write-Phase10FailureDiagnostics -ErrorRecord $_ -Stage $script:CurrentStage
    exit 1
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
    @{
        Kind = 'UserAssignedIdentity'
        ResourceGroupName = 'rg-orderprocessing-platform'
        ResourceName = 'id-orderprocessing-acr-pull-platform'
        FriendlyName = 'Shared Container Apps user-assigned identity'
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
    $script:CurrentStage = 'Resolve SQL administrator settings'
    $sqlAdmin = Resolve-SqlAdminSettings -Environment $Environment -ExplicitUsername $SqlAdminUsername -ExplicitPassword $SqlAdminPassword
    Write-Host "Execution mode   : SQL authentication automation" -ForegroundColor Green
    Write-Host "SQL Admin        : $($sqlAdmin.Username)" -ForegroundColor Green
}
else {
    $script:CurrentStage = 'Acquire Azure SQL access token'
    Write-Host "Execution mode   : Azure AD admin token" -ForegroundColor Green
    $token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not acquire Azure SQL access token. Run 'az login' as the Azure AD admin set on the SQL server."
    }
}

$resolvedSqlUsername = if ($null -ne $sqlAdmin) { [string]$sqlAdmin.Username } else { '' }
$resolvedSqlPassword = if ($null -ne $sqlAdmin) { [string]$sqlAdmin.Password } else { '' }

if ($UseSqlAuthentication) {
    $script:CurrentStage = 'Discover and validate dedicated tenant topology'
    $dedicatedTenantDatabases = @(Get-ActiveDedicatedTenantDatabases `
        -SqlServerFqdn $sqlFqdn `
        -SharedDatabaseName $sharedDatabaseName `
        -KeyVaultName $keyVaultName `
        -AccessToken $token `
        -SqlUsername $resolvedSqlUsername `
        -SqlPassword $resolvedSqlPassword `
        -UseSqlAuth)
}
else {
    $script:CurrentStage = 'Discover and validate dedicated tenant topology'
    $dedicatedTenantDatabases = @(Get-ActiveDedicatedTenantDatabases `
        -SqlServerFqdn $sqlFqdn `
        -SharedDatabaseName $sharedDatabaseName `
        -KeyVaultName $keyVaultName `
        -AccessToken $token `
        -SqlUsername $resolvedSqlUsername `
        -SqlPassword $resolvedSqlPassword `
        -UseAzureAdToken)
}

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
    $script:CurrentStage = "Resolve managed identity for $friendlyName ($resourceName)"

    $principalId = switch ($kind) {
        'ContainerApp' { Resolve-ContainerAppPrincipalId -ResourceGroupName $resourceGroupName -ContainerAppName $resourceName }
        'FunctionApp' { Resolve-FunctionAppPrincipalId -ResourceGroupName $resourceGroupName -FunctionAppName $resourceName }
        'UserAssignedIdentity' { Resolve-UserAssignedIdentityPrincipalId -ResourceGroupName ([string]$identity.ResourceGroupName) -IdentityName $resourceName }
        default { throw "Unsupported runtime identity kind '$kind'." }
    }

    $appId = Resolve-ManagedIdentityAppId -PrincipalId $principalId

    Write-Host "  Principal ID : $principalId" -ForegroundColor Gray
    Write-Host "  App ID       : $appId" -ForegroundColor Gray

    if ($UseSqlAuthentication) {
        $script:CurrentStage = "Grant $friendlyName access to shared database '$sharedDatabaseName'"
        Grant-IdentityAccessToDatabase `
            -DisplayName $resourceName `
            -ManagedIdentityPrincipalId $principalId `
            -SqlServerFqdn $sqlFqdn `
            -DatabaseName $sharedDatabaseName `
            -AccessToken $token `
            -SqlUsername $resolvedSqlUsername `
            -SqlPassword $resolvedSqlPassword `
            -UseSqlAuth
    }
    else {
        $script:CurrentStage = "Grant $friendlyName access to shared database '$sharedDatabaseName'"
        Grant-IdentityAccessToDatabase `
            -DisplayName $resourceName `
            -ManagedIdentityPrincipalId $principalId `
            -SqlServerFqdn $sqlFqdn `
            -DatabaseName $sharedDatabaseName `
            -AccessToken $token `
            -SqlUsername $resolvedSqlUsername `
            -SqlPassword $resolvedSqlPassword `
            -UseAzureAdToken
    }

    foreach ($dedicatedDatabase in $dedicatedTenantDatabases) {
        $script:CurrentStage = "Grant $friendlyName access to dedicated database '$($dedicatedDatabase.DatabaseName)' for tenant '$($dedicatedDatabase.TenantCode)'"
        if ($UseSqlAuthentication) {
            Grant-IdentityAccessToDatabase `
                -DisplayName $resourceName `
                -ManagedIdentityPrincipalId $principalId `
                -SqlServerFqdn $sqlFqdn `
                -DatabaseName $dedicatedDatabase.DatabaseName `
                -AccessToken $token `
                -SqlUsername $resolvedSqlUsername `
                -SqlPassword $resolvedSqlPassword `
                -UseSqlAuth
        }
        else {
            Grant-IdentityAccessToDatabase `
                -DisplayName $resourceName `
                -ManagedIdentityPrincipalId $principalId `
                -SqlServerFqdn $sqlFqdn `
                -DatabaseName $dedicatedDatabase.DatabaseName `
                -AccessToken $token `
                -SqlUsername $resolvedSqlUsername `
                -SqlPassword $resolvedSqlPassword `
                -UseAzureAdToken
        }
    }

    if ($dedicatedTenantDatabases.Count -eq 0) {
        Write-Host '  Granted shared database access.' -ForegroundColor Green
    }
    else {
        Write-Host '  Granted shared + dedicated database access.' -ForegroundColor Green
    }
}

Write-Host ''
$script:CurrentStage = 'Complete'
Write-Host 'Phase 10 runtime SQL identity setup complete.' -ForegroundColor Green
exit 0
