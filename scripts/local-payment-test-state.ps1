#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Prepare','Restore')][string]$Action = 'Prepare',
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$TenantCode,
    [ValidateSet('Razorpay','OpenPay')][string]$ProviderType,
    [ValidateSet('unchanged','true','false')][string]$ThreeDs = 'unchanged'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root=Split-Path -Parent $PSScriptRoot
$manifest=[IO.Path]::GetFullPath($ManifestPath)
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'
if(-not $manifest.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery manifest must be under project TestResults.'}
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
$lockPath=Join-Path $root 'TestResults/local-payment-test-state.lock'
$shared='OrderProcessingSystem_Dev'
$allowedDatabases=@($shared)+(Get-Phase10ComposeDedicatedTenantDatabaseMap).Values
function Invoke-Database([string]$database,[string]$sql,[hashtable]$parameters=@{}){
    if($database -notin $allowedDatabases -or $database -notmatch '^OrderProcessingSystem_[A-Za-z0-9_]+$'){throw 'Unapproved local test database.'}
    $cs=New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $cs
    $connection=[System.Data.SqlClient.SqlConnection]::new($cs)
    try{
        $connection.Open();$command=$connection.CreateCommand();$command.CommandText=$sql
        foreach($key in $parameters.Keys){[void]$command.Parameters.AddWithValue("@$key",$parameters[$key])}
        $reader=$command.ExecuteReader();$table=[System.Data.DataTable]::new();$table.Load($reader)
        return ,$table
    }finally{$connection.Dispose()}
}
function Get-Snapshot([string]$code){
    # Registry discovery must not join providers: dedicated providers do not live here.
    $registry=Invoke-Database $shared 'SELECT Id,Code,TenantTier,Status,PaymentProviderCode FROM dbo.Tenants WHERE Code=@code' @{code=$code}
    if($registry.Rows.Count-ne 1 -or $registry.Rows[0].Status-ne'Active'){throw 'Exactly one active tenant must exist in the shared registry.'}
    $entry=$registry.Rows[0];$business=$shared
    if($entry.TenantTier-eq'Dedicated'){
        $map=Get-Phase10ComposeDedicatedTenantDatabaseMap
        if(-not$map.ContainsKey($code)){throw 'Provision an explicit project-local dedicated database mapping before testing this tenant.'}
        $business=[string]$map[$code]
    }elseif($entry.TenantTier-ne'SharedPool'){throw 'Unsupported tenant tier.'}
    $mirror=Invoke-Database $business 'SELECT Id,PaymentProviderCode FROM dbo.Tenants WHERE Code=@code' @{code=$code}
    if($mirror.Rows.Count-ne 1 -or $mirror.Rows[0].Id-ne$entry.Id){throw 'Business tenant identity does not match the shared registry.'}
    $data=Invoke-Database $business 'SELECT Id,ProviderType,Use3DSecure,IsProduction FROM payments.PaymentProviders WHERE TenantId=@id ORDER BY ProviderType,Id' @{id=[int]$entry.Id}
    $providers=@(foreach($row in $data.Rows){
        [ordered]@{id=[int]$row.Id;provider=[string]$row.ProviderType;threeDs=[bool]$row.Use3DSecure;production=[bool]$row.IsProduction}
    })
    $providerTypes=@($providers|ForEach-Object{[string]$_.provider})
    if($providerTypes.Count -ne @($providerTypes|Sort-Object -Unique).Count){throw "Duplicate provider records require operator review: $($providerTypes -join ',')."}
    return [ordered]@{tenantCode=$code;tenantId=[int]$entry.Id;tier=[string]$entry.TenantTier;status=[string]$entry.Status;registryDatabase=$shared;registryRoute=[string]$entry.PaymentProviderCode;businessDatabase=$business;businessRoute=[string]$mirror.Rows[0].PaymentProviderCode;providers=$providers}
}
function Save-Manifest($snapshot){$snapshot|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $manifest -Encoding utf8}
function Restore-Snapshot($snapshot){
    $current=Get-Snapshot $snapshot.original.tenantCode
    foreach($field in @('tenantId','tier','status','registryDatabase','businessDatabase')){
        if($current[$field]-ne$snapshot.original.$field){throw 'Tenant topology changed; recovery requires review.'}
    }
    if(($current.providers.id-join',')-ne($snapshot.original.providers.id-join',')){throw 'Provider identities changed; recovery requires review.'}
    $null=Invoke-Database $shared 'UPDATE dbo.Tenants SET PaymentProviderCode=@route WHERE Id=@id AND Code=@code; SELECT 1 AS Restored' @{route=$snapshot.original.registryRoute;id=$snapshot.original.tenantId;code=$snapshot.original.tenantCode}
    foreach($row in $snapshot.original.providers){
        $null=Invoke-Database $snapshot.original.businessDatabase 'UPDATE payments.PaymentProviders SET Use3DSecure=@flag WHERE Id=@id AND TenantId=@tenant AND ProviderType=@provider; SELECT 1 AS Restored' @{flag=[bool]$row.threeDs;id=$row.id;tenant=$snapshot.original.tenantId;provider=$row.provider}
    }
    $actual=Get-Snapshot $snapshot.original.tenantCode
    if(($actual|ConvertTo-Json -Depth 8 -Compress)-ne($snapshot.original|ConvertTo-Json -Depth 8 -Compress)){throw 'Exact restoration failed; retain the recovery manifest and lock.'}
}
if($Action-eq'Restore'){
    if(-not(Test-Path -LiteralPath $lockPath)-or(Get-Content -LiteralPath $lockPath -Raw).Trim()-ne$manifest){throw 'Recovery manifest does not own the test-state lock.'}
    $snapshot=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    if($snapshot.version-ne 2){throw 'Legacy manifest lacks an independent shared-registry snapshot. Manual review is required.'}
    $identity=Invoke-Database $shared 'SELECT CONVERT(nvarchar(128),SERVERPROPERTY(''MachineName'')) AS Machine'
    if($snapshot.serverMachine-ne[string]$identity.Rows[0].Machine-or$snapshot.manifestPath-ne$manifest){throw 'Recovery ownership or SQL identity does not match.'}
    Restore-Snapshot $snapshot
    $snapshot.status='restored';Save-Manifest $snapshot
    Remove-Item -LiteralPath $lockPath
    @{status='restored';manifestPath=$manifest}|ConvertTo-Json -Compress
    return
}
if(-not$TenantCode-or-not$ProviderType){throw 'Prepare requires TenantCode and ProviderType.'}
if(Test-Path -LiteralPath $manifest){throw 'Use a new recovery manifest path for each test.'}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $manifest))
# Lock ownership precedes snapshot reads.
$lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$bytes=[Text.Encoding]::UTF8.GetBytes($manifest);$lock.Write($bytes,0,$bytes.Length)}finally{$lock.Dispose()}
$snapshot=$null
try{
    if(@(Get-ChildItem (Join-Path $root 'TestResults') -Filter 'integration-active-*.lock').Count){throw 'Integration execution or interrupted recovery is active; refuse provider mutation.'}
    $original=Get-Snapshot $TenantCode
    if(@($original.providers|Where-Object production).Count){throw 'Live provider settings are forbidden.'}
    $identity=Invoke-Database $shared 'SELECT CONVERT(nvarchar(128),SERVERPROPERTY(''MachineName'')) AS Machine'
    $snapshot=[ordered]@{version=2;runId=[guid]::NewGuid().ToString('N');manifestPath=$manifest;serverMachine=[string]$identity.Rows[0].Machine;status='prepared';requestedProvider=$ProviderType;requestedThreeDs=$ThreeDs;original=$original}
    Save-Manifest $snapshot
    $null=Invoke-Database $shared 'UPDATE dbo.Tenants SET PaymentProviderCode=@provider WHERE Id=@id AND Code=@code; SELECT 1 AS Updated' @{provider=$ProviderType;id=$original.tenantId;code=$TenantCode}
    if($ThreeDs-ne'unchanged'){
        $null=Invoke-Database $original.businessDatabase 'UPDATE payments.PaymentProviders SET Use3DSecure=@flag WHERE TenantId=@id AND ProviderType=@provider; SELECT 1 AS Updated' @{flag=($ThreeDs-eq'true');id=$original.tenantId;provider=$ProviderType}
    }
    $prepared=Get-Snapshot $TenantCode
    if($prepared.registryRoute-ne$ProviderType){throw 'Prepared shared registry route did not persist.'}
    if($original.businessDatabase-ne$shared-and$prepared.businessRoute-ne$original.businessRoute){throw 'Dedicated mirror was unexpectedly changed.'}
    $selected=$prepared.providers|Where-Object provider -eq $ProviderType
    if($ThreeDs-ne'unchanged'-and$selected.threeDs-ne($ThreeDs-eq'true')){throw 'Prepared business 3DS setting did not persist.'}
    @{status='prepared';manifestPath=$manifest}|ConvertTo-Json -Compress
}catch{
    if($null-eq$snapshot){Remove-Item -LiteralPath $lockPath}
    else{
        try{Restore-Snapshot $snapshot;$snapshot.status='restored';Save-Manifest $snapshot;Remove-Item -LiteralPath $lockPath}
        catch{throw 'Preparation and recovery failed. Retain the owned manifest/lock and review before further testing.'}
    }
    throw 'Payment fixture preparation failed; no test charge is permitted.'
}
