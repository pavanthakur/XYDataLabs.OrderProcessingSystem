#Requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('Apply','Restore')][string]$Action='Apply',[Parameter(Mandatory)][string]$ArtifactPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root = Split-Path -Parent $PSScriptRoot
$artifact = [IO.Path]::GetFullPath($ArtifactPath)
$testRoot = [IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\') + '\'
if (-not $artifact.StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Settings evidence must remain under TestResults.' }
if (Test-Path (Join-Path $root 'TestResults/local-payment-test-state.lock')) { throw 'A payment fixture is active or requires recovery.' }
if (@(Get-ChildItem (Join-Path $root 'TestResults') -Filter 'integration-active-*.lock').Count) { throw 'Integration execution is active or requires review.' }
$settings = Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
$lockPath = Join-Path $root 'TestResults/local-payment-test-state.lock'
$contract = Get-Content (Join-Path $root 'Resources/Configuration/tenant-bootstrap.local.json') -Raw | ConvertFrom-Json
$shared = [string]$contract.sharedBusinessDatabase
$dedicatedMap = Get-Phase10ComposeDedicatedTenantDatabaseMap

function Invoke-BaselineSql([string]$database, [string]$sql, [hashtable]$parameters = @{}) {
    if ($database -notmatch '^OrderProcessingSystem_[A-Za-z0-9_]+$') { throw 'Refusing an unapproved SQL database.' }
    $connectionString = New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        $connection.Open(); $command = $connection.CreateCommand(); $command.CommandText = $sql
        foreach ($key in $parameters.Keys) { [void]$command.Parameters.AddWithValue("@$key", $parameters[$key]) }
        if ($sql -match '(?is)\bSELECT\b') {
            $reader = $command.ExecuteReader(); $table = [Data.DataTable]::new(); $table.Load($reader); return ,$table
        }
        [void]$command.ExecuteNonQuery()
    } finally { $connection.Dispose() }
}

if ($Action -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $lockPath) -or (Get-Content -LiteralPath $lockPath -Raw).Trim() -ne $artifact) { throw 'The recovery lock must name this exact settings snapshot.' }
    $recoveryGuard = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $snapshot = Get-Content -LiteralPath $artifact -Raw | ConvertFrom-Json
        if ($snapshot.version -ne 1 -or $snapshot.scope -ne 'docker-dev' -or $snapshot.status -notin @('snapshot','rollback-incomplete')) { throw 'Snapshot is not eligible for interrupted-baseline recovery.' }
        $identity = Invoke-BaselineSql $shared "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS Machine"
        if ([string]$identity.Rows[0].Machine -ne [string]$snapshot.sqlMachine) { throw 'Recovery SQL identity differs from the captured server.' }
        foreach ($entry in $snapshot.entries) {
            $current = Invoke-BaselineSql $entry.database 'SELECT t.Id,t.TenantTier,p.Id ProviderId,p.IsProduction FROM dbo.Tenants t JOIN payments.PaymentProviders p ON p.TenantId=t.Id WHERE t.Code=@code AND p.ProviderType=''OpenPay''' @{ code=$entry.tenantCode }
            if ($current.Rows.Count -ne 1 -or [int]$current.Rows[0].Id -ne [int]$entry.tenantId -or [string]$current.Rows[0].TenantTier -ne [string]$entry.tier -or [int]$current.Rows[0].ProviderId -ne [int]$entry.providerId -or [bool]$current.Rows[0].IsProduction) { throw "Recovery identity mismatch for tenant '$($entry.tenantCode)'." }
            [void](Invoke-BaselineSql $entry.database 'UPDATE payments.PaymentProviders SET Use3DSecure=@flag WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay'' AND IsProduction=0' @{ flag=[bool]$entry.originalUse3DSecure; providerId=[int]$entry.providerId; tenantId=[int]$entry.tenantId })
        }
        foreach ($entry in $snapshot.entries) {
            $current = Invoke-BaselineSql $entry.database 'SELECT Use3DSecure FROM payments.PaymentProviders WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay''' @{ providerId=[int]$entry.providerId; tenantId=[int]$entry.tenantId }
            if ($current.Rows.Count -ne 1 -or [bool]$current.Rows[0].Use3DSecure -ne [bool]$entry.originalUse3DSecure) { throw "Recovery verification failed for tenant '$($entry.tenantCode)'." }
        }
        $snapshot.status='restored-original-pre-baseline'; $snapshot.restoredUtc=[DateTime]::UtcNow.ToString('o')
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifact -Encoding utf8
    } finally { $recoveryGuard.Dispose() }
    Remove-Item -LiteralPath $lockPath
    Write-Host "Restored original OpenPay 3DS settings from $artifact"
    return
}

if (Test-Path -LiteralPath $artifact) { throw 'Use a new unique artifact path; existing evidence will not be overwritten.' }
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$lockBytes = [Text.Encoding]::UTF8.GetBytes($artifact)
$lock.Write($lockBytes, 0, $lockBytes.Length)
$lock.Dispose()
$snapshot = $null
try {
    $machineRows = Invoke-BaselineSql $shared "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS Machine"
    $registryRows = Invoke-BaselineSql $shared "SELECT Id,Code,Status,TenantTier,PaymentProviderCode FROM dbo.Tenants WHERE Status='Active' ORDER BY Code"
    $entries = @()
    foreach ($tenant in $registryRows.Rows) {
        $code = [string]$tenant.Code
        if ($tenant.TenantTier -eq 'SharedPool') { $database = $shared }
        elseif ($tenant.TenantTier -eq 'Dedicated' -and $dedicatedMap.ContainsKey($code)) { $database = [string]$dedicatedMap[$code] }
        else { throw "Active tenant '$code' has no valid project-local business-database mapping." }
        $businessIdentity = Invoke-BaselineSql $database 'SELECT Id,Code,TenantTier FROM dbo.Tenants WHERE Code=@code' @{ code=$code }
        if ($businessIdentity.Rows.Count -ne 1 -or [int]$businessIdentity.Rows[0].Id -ne [int]$tenant.Id -or [string]$businessIdentity.Rows[0].TenantTier -ne [string]$tenant.TenantTier) { throw "Tenant '$code' business-database identity does not match its authoritative registry entry." }
        $allProviders = Invoke-BaselineSql $database 'SELECT ProviderType,IsProduction FROM payments.PaymentProviders WHERE TenantId=@tenantId ORDER BY ProviderType' @{ tenantId=[int]$tenant.Id }
        $actualProviderTypes = @($allProviders.Rows | ForEach-Object { [string]$_.ProviderType })
        $expectedProviderTypes = @($contract.supportedProviderTypes | ForEach-Object { [string]$_ } | Sort-Object)
        if ($actualProviderTypes.Count -ne $expectedProviderTypes.Count -or @($actualProviderTypes | Sort-Object -Unique).Count -ne $expectedProviderTypes.Count -or (Compare-Object $expectedProviderTypes @($actualProviderTypes | Sort-Object)).Count) { throw "Tenant '$code' must have exactly one record for each supported provider before the baseline can be applied." }
        if (@($allProviders.Rows | Where-Object { [bool]$_.IsProduction }).Count) { throw "Tenant '$code' has a live provider record; no 3DS setting was changed." }
        $providers = Invoke-BaselineSql $database 'SELECT Id,Use3DSecure,IsProduction FROM payments.PaymentProviders WHERE TenantId=@tenantId AND ProviderType=''OpenPay''' @{ tenantId=[int]$tenant.Id }
        if ($providers.Rows.Count -ne 1 -or [bool]$providers.Rows[0].IsProduction) { throw "Tenant '$code' must have exactly one non-production OpenPay provider row; no credentials or routing were changed." }
        $entries += [ordered]@{ tenantCode=$code; tenantId=[int]$tenant.Id; tier=[string]$tenant.TenantTier; database=$database; providerId=[int]$providers.Rows[0].Id; originalUse3DSecure=[bool]$providers.Rows[0].Use3DSecure; approvedUse3DSecure=$false }
    }
    foreach ($required in $contract.requiredBaselineTenants) { if ($required -notin @($entries | ForEach-Object tenantCode)) { throw "Required tenant '$required' is not active; no settings were changed." } }
    $snapshot = [ordered]@{ version=1; scope='docker-dev'; capturedUtc=[DateTime]::UtcNow.ToString('o'); sqlMachine=[string]$machineRows.Rows[0].Machine; policy='OpenPay.Use3DSecure=false for every active tenant; provider routes and all other fields unchanged'; status='snapshot'; entries=$entries }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $artifact))
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifact -Encoding utf8

    foreach ($entry in $entries) {
        if (-not $entry.originalUse3DSecure) { continue }
        [void](Invoke-BaselineSql $entry.database 'UPDATE payments.PaymentProviders SET Use3DSecure=0 WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay'' AND IsProduction=0' @{ providerId=$entry.providerId; tenantId=$entry.tenantId })
        $table = Invoke-BaselineSql $entry.database 'SELECT Use3DSecure FROM payments.PaymentProviders WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay''' @{ providerId=$entry.providerId; tenantId=$entry.tenantId }
        if ($table.Rows.Count -ne 1 -or [bool]$table.Rows[0].Use3DSecure) { throw "OpenPay 3DS baseline read-back failed for '$($entry.tenantCode)'." }
    }
    foreach ($entry in $entries) {
        $table = Invoke-BaselineSql $entry.database 'SELECT Use3DSecure FROM payments.PaymentProviders WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay''' @{ providerId=$entry.providerId; tenantId=$entry.tenantId }
        if ($table.Rows.Count -ne 1 -or [bool]$table.Rows[0].Use3DSecure) { throw "OpenPay 3DS baseline verification failed for '$($entry.tenantCode)'." }
    }
    $snapshot.status = 'applied-and-verified'; $snapshot.appliedUtc = [DateTime]::UtcNow.ToString('o')
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifact -Encoding utf8
    Remove-Item -LiteralPath $lockPath
    Write-Host "Applied and verified OpenPay 3DS-off baseline for $($entries.Count) active tenant(s). Evidence: $artifact"
} catch {
    if ($null -ne $snapshot) {
        $rollbackFailures = @()
        foreach ($entry in @($snapshot.entries)) {
            try {
                [void](Invoke-BaselineSql $entry.database 'UPDATE payments.PaymentProviders SET Use3DSecure=@flag WHERE Id=@providerId AND TenantId=@tenantId AND ProviderType=''OpenPay'' AND IsProduction=0' @{ flag=[bool]$entry.originalUse3DSecure; providerId=[int]$entry.providerId; tenantId=[int]$entry.tenantId })
            } catch { $rollbackFailures += $entry.tenantCode }
        }
        if ($rollbackFailures.Count) { $snapshot.status='rollback-incomplete'; $snapshot.rollbackFailures=$rollbackFailures; $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifact -Encoding utf8; throw 'OpenPay baseline application failed and rollback is incomplete; retain the lock and stop all payment tests.' }
        $snapshot.status='failed-rolled-back'; $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifact -Encoding utf8
    }
    Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue
    throw
}
