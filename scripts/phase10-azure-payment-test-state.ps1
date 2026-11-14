#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Inspect','Prepare','Restore')][string]$Action = 'Inspect',
    [ValidateSet('dev')][string]$Environment = 'dev',
    [string]$TenantCode,
    [ValidateSet('OpenPay','Razorpay')][string]$ProviderType,
    [ValidateSet('false','true')][string]$ThreeDs = 'false',
    [string]$ManifestPath,
    [string]$ApiBaseUrl,
    [string]$ExpectedSubscriptionId = $env:EXPECTED_AZURE_SUBSCRIPTION_ID,
    [switch]$LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-azure-firewall-lease.ps1')
$script:AzureFixtureSqlToken = $null
$script:AzureFixtureTarget = $null
$script:AzureFixtureSubscription = $null
$script:AzureFixtureFirewallLease = $null

function Get-AzureFixtureTarget {
    if ($null -ne $script:AzureFixtureTarget) { return $script:AzureFixtureTarget }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
    $target = @($catalog.targets | Where-Object key -eq 'azure-dev')
    if ($target.Count -ne 1) { throw 'Runtime-target catalog must contain exactly one azure-dev entry.' }
    foreach ($field in @('azureResourceGroupName','azureSqlServerName','azureOperationsDatabaseName','azureKeyVaultName')) {
        if ([string]::IsNullOrWhiteSpace([string]$target[0].$field)) { throw "azure-dev runtime target is missing $field." }
    }
    $script:AzureFixtureTarget = $target[0]
    return $script:AzureFixtureTarget
}

function Invoke-AzureFixtureCli {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI operation failed; no secret-bearing command output is included.' }
    return ((@($result | ForEach-Object { [string]$_ }) -join "`n").Trim())
}

function Initialize-AzureFixtureSql {
    $target = Get-AzureFixtureTarget
    $account = Invoke-AzureFixtureCli -Arguments @('account','show','--query','{id:id,state:state}','-o','json') | ConvertFrom-Json
    if ($account.state -ne 'Enabled') { throw 'Azure subscription is not enabled.' }
    if ([string]::IsNullOrWhiteSpace($ExpectedSubscriptionId)) { throw 'Expected subscription ID is required; set EXPECTED_AZURE_SUBSCRIPTION_ID.' }
    if ($account.id -ne $ExpectedSubscriptionId) { throw 'Signed-in Azure subscription does not match the expected subscription.' }
    $script:AzureFixtureSubscription = [string]$account.id
    $script:AzureFixtureSqlToken = Invoke-AzureFixtureCli -Arguments @('account','get-access-token','--resource','https://database.windows.net/','--query','accessToken','-o','tsv')
    if ([string]::IsNullOrWhiteSpace($script:AzureFixtureSqlToken)) { throw 'Azure SQL access token was unavailable.' }
}

function Invoke-AzureFixtureFirewallCli {
    param([string[]]$Arguments)
    & az @Arguments 2>&1
    $global:LASTEXITCODE = $LASTEXITCODE
}

function Open-AzureFixtureFirewall {
    $target = Get-AzureFixtureTarget
    $account = Invoke-AzureFixtureCli -Arguments @('account','show','--query','{id:id,state:state}','-o','json') | ConvertFrom-Json
    if ($account.state -ne 'Enabled') { throw 'Azure subscription is not enabled.' }
    if ([string]::IsNullOrWhiteSpace($ExpectedSubscriptionId) -or $account.id -ne $ExpectedSubscriptionId) { throw 'Signed-in Azure subscription does not match the required EXPECTED_AZURE_SUBSCRIPTION_ID.' }
    $ip = $null
    foreach ($endpoint in @('https://api.ipify.org?format=json','https://ifconfig.me/ip')) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Get -TimeoutSec 10
            $candidate = if ($response -is [string]) { $response.Trim() } else { [string]$response.ip }
            if ($candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$') { $ip = $candidate; break }
        }
        catch { }
    }
    if (-not $ip) { throw 'Could not resolve the current public IP; Azure SQL firewall was not changed.' }
    $root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults/Playwright/azure-https/payment-fixtures'))
    [void][IO.Directory]::CreateDirectory($root)
    $leasePath = if ($ManifestPath) { "$([IO.Path]::GetFullPath($ManifestPath)).firewall.json" } else { Join-Path $root ('inspect-firewall-' + [guid]::NewGuid().ToString('N') + '.json') }
    $script:AzureFixtureFirewallLease = New-Phase10FirewallLease -Environment 'dev' -SubscriptionId ([string]$account.id) -ResourceGroup ([string]$target.azureResourceGroupName) -Server ([string]$target.azureSqlServerName) -PublicIp $ip -RunId "local-$([guid]::NewGuid().ToString('N'))" -Attempt '1' -InvocationId ([guid]::NewGuid().ToString('N')) -ManifestPath $leasePath -InvokeAz ${function:Invoke-AzureFixtureFirewallCli}
}

function Close-AzureFixtureFirewall {
    if ($null -eq $script:AzureFixtureFirewallLease) { return }
    Remove-Phase10FirewallLease -ManifestPath $script:AzureFixtureFirewallLease.ManifestPath -InvokeAz ${function:Invoke-AzureFixtureFirewallCli}
    $script:AzureFixtureFirewallLease = $null
}

function Invoke-AzureFixtureSql {
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters = @{},
        [switch]$NonQuery
    )
    if ($Database -notmatch '^[A-Za-z0-9_]+$') { throw 'Rejected unsafe Azure SQL database name.' }
    $dedicatedNames = @($script:AzureFixtureDedicatedDatabases.Values | ForEach-Object { $_ })
    if ($Database -ne $script:AzureFixtureTarget.azureOperationsDatabaseName -and $Database -notin $dedicatedNames) {
        throw 'Azure SQL database is not present in the validated runtime-target topology.'
    }
    $connectionString = "Server=tcp:$($script:AzureFixtureTarget.azureSqlServerName).database.windows.net,1433;Initial Catalog=$Database;Persist Security Info=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        $connection.AccessToken = $script:AzureFixtureSqlToken
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 60
        foreach ($name in $Parameters.Keys) {
            $parameter = $command.Parameters.Add("@$name", [System.Data.SqlDbType]::NVarChar, 256)
            $parameter.Value = $Parameters[$name]
        }
        if ($NonQuery) { return $command.ExecuteNonQuery() }
        $reader = $command.ExecuteReader()
        try {
            $table = [System.Data.DataTable]::new()
            $table.Load($reader)
            return @($table.Rows | ForEach-Object {
                $row = [ordered]@{}
                foreach ($column in $table.Columns) { $row[$column.ColumnName] = $_[$column.ColumnName] }
                [pscustomobject]$row
            })
        }
        finally { $reader.Dispose() }
    }
    finally { $connection.Dispose() }
}

function Initialize-AzureFixtureTopology {
    $target = Get-AzureFixtureTarget
    $script:AzureFixtureDedicatedDatabases = @{}
    $databases = Invoke-AzureFixtureCli -Arguments @('sql','db','list','--resource-group',$target.azureResourceGroupName,'--server',$target.azureSqlServerName,'--query','[].{name:name,tags:tags}','-o','json') | ConvertFrom-Json
    foreach ($database in @($databases)) {
        $tags = $database.tags
        if ($null -eq $tags) { continue }
        $tenantTag = $tags.PSObject.Properties['tenant']
        if ($null -eq $tenantTag) { continue }
        $tag = [string]$tenantTag.Value
        $isProjectDedicatedDb = [string]$tags.app -eq 'orderprocessing' -and [string]$tags.env -eq 'dev' -and [string]$tags.tenancy -eq 'dedicated'
        if ($isProjectDedicatedDb -and -not [string]::IsNullOrWhiteSpace($tag) -and [string]$database.name -match '^[A-Za-z0-9_]+$') {
            $key = $tag.ToLowerInvariant()
            if (-not $script:AzureFixtureDedicatedDatabases.ContainsKey($key)) { $script:AzureFixtureDedicatedDatabases[$key] = @() }
            $script:AzureFixtureDedicatedDatabases[$key] += [string]$database.name
        }
    }
}

function Get-AzureFixtureDedicatedDatabase {
    param([Parameter(Mandatory)][string]$Code)
    $matches = @($script:AzureFixtureDedicatedDatabases[$Code.ToLowerInvariant()])
    if ($matches.Count -ne 1) { throw "Dedicated tenant '$Code' must have exactly one Azure SQL database with a matching tenant tag." }
    return [string]$matches[0]
}

function Get-AzureFixtureTenant {
    param([Parameter(Mandatory)][string]$Code)
    if ($Code -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Tenant code is not a valid registry key.' }
    $registryDatabase = [string](Get-AzureFixtureTarget).azureOperationsDatabaseName
    $tenants = @(Invoke-AzureFixtureSql -Database $registryDatabase -Query @'
SELECT Id AS TenantId, Code AS TenantCode, Status AS TenantStatus, TenantTier, PaymentProviderCode
FROM dbo.Tenants WHERE Code=@code;
'@ -Parameters @{code=$Code})
    if ($tenants.Count -ne 1 -or $tenants[0].TenantStatus -ne 'Active') { throw 'Tenant must resolve to exactly one active registry row.' }
    $businessDatabase = if ($tenants[0].TenantTier -eq 'SharedPool') { $registryDatabase } elseif ($tenants[0].TenantTier -eq 'Dedicated') { Get-AzureFixtureDedicatedDatabase -Code $Code } else { throw 'Tenant tier is not supported by the Azure fixture.' }
    $businessTenant = @(Invoke-AzureFixtureSql -Database $businessDatabase -Query @'
SELECT Id AS TenantId, Code AS TenantCode FROM dbo.Tenants WHERE Code=@code;
'@ -Parameters @{code=$Code})
    if ($businessTenant.Count -ne 1 -or [int]$businessTenant[0].TenantId -ne [int]$tenants[0].TenantId) { throw 'Business-database tenant identity does not match the shared registry.' }
    $providers = @(Invoke-AzureFixtureSql -Database $businessDatabase -Query @'
SELECT Id AS ProviderId, ProviderType, Use3DSecure, IsProduction
FROM payments.PaymentProviders WHERE TenantId=@tenantId ORDER BY ProviderType, Id;
'@ -Parameters @{tenantId=[string]$tenants[0].TenantId})
    $types = @($providers | ForEach-Object ProviderType)
    if (@($types | Sort-Object -Unique).Count -ne $types.Count) { throw 'Duplicate tenant provider records require operator review.' }
    foreach ($requiredProvider in @('OpenPay','Razorpay')) {
        if (@($providers | Where-Object ProviderType -eq $requiredProvider).Count -ne 1) { throw "Tenant '$Code' must have exactly one $requiredProvider record in its business database." }
    }
    if (@($providers | Where-Object { [bool]$_.IsProduction }).Count -gt 0) { throw "Tenant '$Code' has production provider records; sandbox fixture mutations are refused." }
    return [ordered]@{
        tenantCode = $Code
        tenantId = [int]$tenants[0].TenantId
        tier = [string]$tenants[0].TenantTier
        status = [string]$tenants[0].TenantStatus
        registryDatabase = $registryDatabase
        registryRoute = [string]$tenants[0].PaymentProviderCode
        businessDatabase = $businessDatabase
        providers = @($providers | ForEach-Object { [ordered]@{ id=[int]$_.ProviderId; provider=[string]$_.ProviderType; threeDs=[bool]$_.Use3DSecure; production=[bool]$_.IsProduction } })
    }
}

function Get-AzureFixtureWritePermissions {
    param([Parameter(Mandatory)]$Tenant)
    $registry = @(Invoke-AzureFixtureSql -Database $Tenant.registryDatabase -Query @'
SELECT CASE WHEN OBJECT_ID(N'dbo.Tenants', N'U') IS NULL THEN 0 ELSE 1 END AS TenantTableExists,
       CASE WHEN COL_LENGTH(N'dbo.Tenants', N'PaymentProviderCode') IS NULL THEN 0 ELSE 1 END AS PaymentProviderCodeColumnExists,
       HAS_PERMS_BY_NAME(N'dbo.Tenants', N'OBJECT', N'UPDATE', N'PaymentProviderCode', N'COLUMN') AS CanUpdatePaymentProviderRoute;
'@)
    $business = @(Invoke-AzureFixtureSql -Database $Tenant.businessDatabase -Query @'
SELECT CASE WHEN OBJECT_ID(N'payments.PaymentProviders', N'U') IS NULL THEN 0 ELSE 1 END AS PaymentProvidersTableExists,
       CASE WHEN COL_LENGTH(N'payments.PaymentProviders', N'Use3DSecure') IS NULL THEN 0 ELSE 1 END AS Use3DSecureColumnExists,
       HAS_PERMS_BY_NAME(N'payments.PaymentProviders', N'OBJECT', N'UPDATE', N'Use3DSecure', N'COLUMN') AS CanUpdateThreeDsFlag;
'@)
    if ($registry.Count -ne 1 -or $business.Count -ne 1) { throw "Could not establish column-level fixture permissions for '$($Tenant.tenantCode)'." }
    $routePermissionState = if ($registry[0].CanUpdatePaymentProviderRoute -is [DBNull]) { 'unknown' } elseif ([string]$registry[0].CanUpdatePaymentProviderRoute -eq '1') { 'granted' } else { 'denied' }
    $threeDsPermissionState = if ($business[0].CanUpdateThreeDsFlag -is [DBNull]) { 'unknown' } elseif ([string]$business[0].CanUpdateThreeDsFlag -eq '1') { 'granted' } else { 'denied' }
    return [pscustomobject]@{
        canUpdatePaymentProviderRoute = ($routePermissionState -eq 'granted')
        routePermissionState = $routePermissionState
        tenantTableExists = ([int]$registry[0].TenantTableExists -eq 1)
        paymentProviderCodeColumnExists = ([int]$registry[0].PaymentProviderCodeColumnExists -eq 1)
        canUpdateThreeDsFlag = ($threeDsPermissionState -eq 'granted')
        threeDsPermissionState = $threeDsPermissionState
        paymentProvidersTableExists = ([int]$business[0].PaymentProvidersTableExists -eq 1)
        use3dsColumnExists = ([int]$business[0].Use3DSecureColumnExists -eq 1)
    }
}

function Save-AzureFixtureManifest {
    param([Parameter(Mandatory)]$Snapshot)
    $Snapshot.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
}

function Assert-AzureFixtureManifestPath {
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) { throw 'A per-case manifest path is required.' }
    $root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults/Playwright/azure-https')).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($ManifestPath)
    if (-not $fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Azure payment fixture manifests must remain under TestResults/Playwright/azure-https.' }
    if ([IO.Path]::GetFileName($fullPath) -notmatch '^[A-Za-z0-9_.-]+\.json$') { throw 'Fixture manifest filename is invalid.' }
    return $fullPath
}

function Restore-AzureFixtureSnapshot {
    param([Parameter(Mandatory)]$Snapshot)
    if ($Snapshot.schemaVersion -ne 1 -or $Snapshot.environment -ne 'dev') { throw 'Fixture manifest schema/environment is unsupported.' }
    if ($Snapshot.subscriptionId -ne $script:AzureFixtureSubscription -or $Snapshot.resourceGroup -ne (Get-AzureFixtureTarget).azureResourceGroupName -or $Snapshot.sqlServer -ne (Get-AzureFixtureTarget).azureSqlServerName) { throw 'Azure subscription/resource ownership no longer matches the recovery manifest.' }
    $current = Get-AzureFixtureTenant -Code $Snapshot.original.tenantCode
    foreach ($field in @('tenantId','tier','status','registryDatabase','businessDatabase')) {
        if ([string]$current[$field] -ne [string]$Snapshot.original.$field) { throw 'Tenant/database topology changed; automatic fixture restore is unsafe.' }
    }
    if (($current.providers.id -join ',') -ne ($Snapshot.original.providers.id -join ',')) { throw 'Provider row identity changed; automatic fixture restore is unsafe.' }
    $routeSql = 'UPDATE dbo.Tenants SET PaymentProviderCode=@value WHERE Id=@id AND Code=@code;'
    [void](Invoke-AzureFixtureSql -Database $Snapshot.original.registryDatabase -Query $routeSql -Parameters @{value=[string]$Snapshot.original.registryRoute;id=[string]$Snapshot.original.tenantId;code=[string]$Snapshot.original.tenantCode} -NonQuery)
    foreach ($provider in $Snapshot.original.providers) {
        $flagSql = 'UPDATE payments.PaymentProviders SET Use3DSecure=@value WHERE Id=@id AND TenantId=@tenantId AND ProviderType=@provider;'
        [void](Invoke-AzureFixtureSql -Database $Snapshot.original.businessDatabase -Query $flagSql -Parameters @{value=$(if ([bool]$provider.threeDs) { '1' } else { '0' });id=[string]$provider.id;tenantId=[string]$Snapshot.original.tenantId;provider=[string]$provider.provider} -NonQuery)
    }
    $actual = Get-AzureFixtureTenant -Code $Snapshot.original.tenantCode
    if (($actual | ConvertTo-Json -Depth 8 -Compress) -ne ($Snapshot.original | ConvertTo-Json -Depth 8 -Compress)) { throw 'Exact Azure fixture restoration could not be proven; retain the recovery manifest and lock.' }
    Wait-AzureFixtureRuntimeRoute -Code $Snapshot.original.tenantCode -ExpectedProvider $Snapshot.original.registryRoute
}

function Wait-AzureFixtureRuntimeRoute {
    param([Parameter(Mandatory)][string]$Code,[Parameter(Mandatory)][string]$ExpectedProvider)
    if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { throw 'API base URL is required to verify the runtime route before payment testing.' }
    $uri = [Uri]$ApiBaseUrl
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https') { throw 'Azure payment fixture requires the resolved HTTPS API origin.' }
    $endpoint = "$($uri.ToString().TrimEnd('/'))/api/v1/Info/tenant-registry"
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        try {
            # Invoke-RestMethod can emit a JSON array as one System.Object[] object.
            # Wrapping the command in @() nests that array and makes Where-Object
            # compare the tenant fields on the array itself instead of its rows.
            $rows = Invoke-RestMethod -Uri $endpoint -Method Get -TimeoutSec 10
            $tenant = @($rows | Where-Object { [string]$_.tenantCode -eq $Code })
            if ($tenant.Count -eq 1 -and [string]$tenant[0].paymentProviderCode -eq $ExpectedProvider) { return }
        }
        catch { }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Runtime tenant registry did not report the expected provider route for '$Code' within 30 seconds."
}

function Invoke-AzurePaymentFixture {
    Initialize-AzureFixtureSql
    Initialize-AzureFixtureTopology
    if ($Action -eq 'Inspect') {
        $fixtureLock = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults/Playwright/azure-https/payment-fixtures') 'azure-payment-fixture.lock'
        if (Test-Path -LiteralPath $fixtureLock) { throw 'An Azure payment fixture lock already exists. Review its manifest and recover it before starting another run.' }
        $registry = [string](Get-AzureFixtureTarget).azureOperationsDatabaseName
        $active = @(Invoke-AzureFixtureSql -Database $registry -Query "SELECT Code AS TenantCode FROM dbo.Tenants WHERE Status='Active' ORDER BY Code;")
        $inspection = foreach ($tenant in $active) {
            $snapshot = Get-AzureFixtureTenant -Code ([string]$tenant.TenantCode)
            $permissions = Get-AzureFixtureWritePermissions -Tenant $snapshot
            [pscustomobject]@{
                tenantCode = $snapshot.tenantCode
                tier = $snapshot.tier
                assignedProvider = $snapshot.registryRoute
                configuredProviders = @($snapshot.providers | ForEach-Object { [pscustomobject]@{ provider=$_.provider; threeDs=$_.threeDs; sandbox= -not $_.production } })
                permissions = $permissions
            }
        }
        $inspection = @($inspection)
        $blocked = @($inspection | Where-Object { -not $_.permissions.canUpdatePaymentProviderRoute -or -not $_.permissions.canUpdateThreeDsFlag -or -not $_.permissions.tenantTableExists -or -not $_.permissions.paymentProviderCodeColumnExists -or -not $_.permissions.paymentProvidersTableExists -or -not $_.permissions.use3dsColumnExists })
        $inspectionRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults/Playwright/azure-https/payment-fixtures'
        [void][IO.Directory]::CreateDirectory($inspectionRoot)
        $inspectionPath = Join-Path $inspectionRoot ('inspection-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N') + '.json')
        $inspectionReport = [ordered]@{
            schemaVersion = 1
            environment = 'dev'
            subscriptionId = $script:AzureFixtureSubscription
            resourceGroup = [string](Get-AzureFixtureTarget).azureResourceGroupName
            sqlServer = [string](Get-AzureFixtureTarget).azureSqlServerName
            completedAtUtc = [DateTime]::UtcNow.ToString('o')
            status = if ($blocked.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
            tenants = $inspection
        }
        $inspectionReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inspectionPath -Encoding utf8
        [pscustomobject]@{ reportPath=$inspectionPath;status=$inspectionReport.status;tenantCount=$inspection.Count;tenants=$inspection } | ConvertTo-Json -Depth 8
        if ($blocked.Count -gt 0) { throw "Azure dev fixture preflight is blocked for $($blocked.Count) active tenant(s): required fixture tables, columns, or column-scoped UPDATE permissions are missing or could not be determined. No application data was changed. See '$inspectionPath'." }
        return
    }
    $fullManifestPath = Assert-AzureFixtureManifestPath
    $script:ManifestPath = $fullManifestPath
    $lockPath = Join-Path (Split-Path -Parent $fullManifestPath) 'azure-payment-fixture.lock'
    if ($Action -eq 'Prepare') {
        if (-not $TenantCode -or -not $ProviderType) { throw 'Prepare requires tenant code and provider type.' }
        if (Test-Path -LiteralPath $fullManifestPath) { throw 'Manifest already exists; use a unique per-case path.' }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fullManifestPath))
        $lock = [IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=[Text.Encoding]::UTF8.GetBytes($fullManifestPath);$lock.Write($bytes,0,$bytes.Length) } finally { $lock.Dispose() }
        $snapshot = $null
        try {
            $original = Get-AzureFixtureTenant -Code $TenantCode
            $permissions = Get-AzureFixtureWritePermissions -Tenant $original
            if (-not $permissions.canUpdatePaymentProviderRoute -or -not $permissions.canUpdateThreeDsFlag) {
                throw 'Current Entra SQL principal lacks the column-scoped UPDATE permissions required by the fixture; no fixture changes were made.'
            }
            $snapshot = [ordered]@{ schemaVersion=1; runId=[guid]::NewGuid().ToString('N'); manifestPath=$fullManifestPath; environment='dev'; subscriptionId=$script:AzureFixtureSubscription; resourceGroup=(Get-AzureFixtureTarget).azureResourceGroupName; sqlServer=(Get-AzureFixtureTarget).azureSqlServerName; status='prepared'; requestedProvider=$ProviderType; requestedThreeDs=[bool]::Parse($ThreeDs); original=$original; createdAtUtc=[DateTime]::UtcNow.ToString('o') }
            Save-AzureFixtureManifest $snapshot
            $routeSql = 'UPDATE dbo.Tenants SET PaymentProviderCode=@value WHERE Id=@id AND Code=@code;'
            [void](Invoke-AzureFixtureSql -Database $snapshot.original.registryDatabase -Query $routeSql -Parameters @{value=$ProviderType;id=[string]$snapshot.original.tenantId;code=$TenantCode} -NonQuery)
            $flagSql = 'UPDATE payments.PaymentProviders SET Use3DSecure=@value WHERE Id=@id AND TenantId=@tenantId AND ProviderType=@provider;'
            [void](Invoke-AzureFixtureSql -Database $snapshot.original.businessDatabase -Query $flagSql -Parameters @{value=$(if ([bool]::Parse($ThreeDs)) { '1' } else { '0' });id=[string](($snapshot.original.providers | Where-Object provider -eq $ProviderType).id);tenantId=[string]$snapshot.original.tenantId;provider=$ProviderType} -NonQuery)
            $prepared = Get-AzureFixtureTenant -Code $TenantCode
            $selected = @($prepared.providers | Where-Object provider -eq $ProviderType)
            if ($prepared.registryRoute -ne $ProviderType -or $selected.Count -ne 1 -or $selected[0].threeDs -ne [bool]::Parse($ThreeDs)) { throw 'Azure runtime fixture SQL read-back did not match the requested route/3DS state.' }
            Wait-AzureFixtureRuntimeRoute -Code $TenantCode -ExpectedProvider $ProviderType
            $snapshot.status='prepared-and-verified';Save-AzureFixtureManifest $snapshot
            [pscustomobject]@{ status='prepared';manifestPath=$fullManifestPath;tenantCode=$TenantCode;provider=$ProviderType;threeDs=[bool]::Parse($ThreeDs) } | ConvertTo-Json -Compress
        }
        catch {
            if ($null -eq $snapshot) { Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue }
            else {
                try { Restore-AzureFixtureSnapshot $snapshot;$snapshot.status='restored-after-prepare-failure';Save-AzureFixtureManifest $snapshot;Remove-Item -LiteralPath $lockPath }
                catch { throw 'Azure payment fixture preparation and recovery both failed. Preserve the manifest and lock; do not submit a charge.' }
            }
            throw 'Azure fixture preparation failed; payment submission is prohibited.'
        }
        return
    }
    if (-not (Test-Path -LiteralPath $lockPath) -or (Get-Content -LiteralPath $lockPath -Raw).Trim() -ne $fullManifestPath) { throw 'Recovery manifest does not own the Azure payment fixture lock.' }
    $snapshot = Get-Content -LiteralPath $fullManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    Restore-AzureFixtureSnapshot $snapshot
    $snapshot.status='restored';Save-AzureFixtureManifest $snapshot
    Remove-Item -LiteralPath $lockPath
    [pscustomobject]@{ status='restored';manifestPath=$fullManifestPath;tenantCode=$snapshot.original.tenantCode } | ConvertTo-Json -Compress
}

if (-not $LibraryOnly) {
    try {
        Open-AzureFixtureFirewall
        Invoke-AzurePaymentFixture
    }
    finally {
        Close-AzureFixtureFirewall
    }
}
