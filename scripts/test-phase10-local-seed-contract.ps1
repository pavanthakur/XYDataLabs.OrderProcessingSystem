#Requires -Version 7.0
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint

$root = Split-Path -Parent $PSScriptRoot
$output = [IO.Path]::GetFullPath($OutputPath)
$testRoot = [IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\') + '\'
if (-not $output.StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Reports must remain under TestResults.' }
$settings = Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
$contractPath = Join-Path $root 'Resources/Configuration/tenant-bootstrap.local.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ($contract.schemaVersion -ne 1 -or $contract.scope -ne 'docker-dev' -or $contract.seedPolicy -ne 'missing-only') { throw 'Local tenant bootstrap contract is invalid.' }
$providers = @($contract.supportedProviderTypes | ForEach-Object { [string]$_ })
if ($providers.Count -ne 2 -or @($providers | Sort-Object -Unique).Count -ne $providers.Count -or ($providers | Where-Object { $_ -notin @('Razorpay','OpenPay') }).Count) { throw 'Local bootstrap provider catalog is incomplete or unsupported.' }
foreach ($provider in $providers) { if (-not $contract.providerDefaults.$provider) { throw "Bootstrap defaults are missing provider '$provider'." } }

function Invoke-SeedContractQuery([string]$database, [string]$sql, [hashtable]$parameters = @{}) {
    if ($database -notmatch '^OrderProcessingSystem_[A-Za-z0-9_]+$') { throw 'Refusing an unapproved database name.' }
    $connectionString = New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand(); $command.CommandText = $sql
        foreach ($key in $parameters.Keys) { [void]$command.Parameters.AddWithValue("@$key", $parameters[$key]) }
        $reader = $command.ExecuteReader(); $table = [Data.DataTable]::new(); $table.Load($reader)
        return ,$table
    } finally { $connection.Dispose() }
}

$failures = [System.Collections.Generic.List[string]]::new()
$tenantResults = [System.Collections.Generic.List[object]]::new()
if (-not ([string]$settings.LOCAL_RAZORPAY_MERCHANT_ID).StartsWith('rzp_test_', [StringComparison]::Ordinal)) { $failures.Add('Razorpay key is not explicitly test-mode; configured values omitted.') }
if ([string]$settings.PHASE10_OPENPAY_3DS_DEFAULT -ne 'false') { $failures.Add('Effective local OpenPay 3DS default must be false.') }

$registryRows = Invoke-SeedContractQuery $contract.sharedBusinessDatabase @'
SELECT Id,Code,Status,TenantTier,PaymentProviderCode FROM dbo.Tenants WHERE Status='Active' ORDER BY Code;
'@
$activeCodes = @($registryRows.Rows | ForEach-Object { [string]$_.Code })
foreach ($required in $contract.requiredBaselineTenants) {
    if ($required -notin $activeCodes) { $failures.Add("Required baseline tenant '$required' is not active.") }
}
$baselineByCode = @{}
foreach ($baseline in $contract.tenantBaselines) { $baselineByCode[[string]$baseline.tenantCode] = $baseline }

foreach ($registry in $registryRows.Rows) {
    $code = [string]$registry.Code
    try {
        if ([string]$registry.PaymentProviderCode -notin $providers) { throw 'Registry route is missing or unsupported.' }
        $businessDatabase = Resolve-Phase10LocalTenantDatabase -TenantCode $code -Settings $settings
        $identity = Invoke-SeedContractQuery $businessDatabase 'SELECT Id,Code,TenantTier FROM dbo.Tenants WHERE Code=@code' @{ code = $code }
        if ($identity.Rows.Count -ne 1 -or [int]$identity.Rows[0].Id -ne [int]$registry.Id -or [string]$identity.Rows[0].TenantTier -ne [string]$registry.TenantTier) { throw 'Business tenant identity does not match the authoritative shared registry.' }
        $baseline = $baselineByCode[$code]
        if ($baseline -and ([string]$registry.Status -ne [string]$baseline.status -or [string]$registry.TenantTier -ne [string]$baseline.tenantTier -or [string]$registry.PaymentProviderCode -ne [string]$baseline.paymentProviderCode)) { throw 'Required baseline registry route/status/tier mismatch.' }

        $providerRows = Invoke-SeedContractQuery $businessDatabase @'
SELECT p.Id,p.ProviderType,p.Use3DSecure,p.IsProduction,
 CAST(CASE WHEN p.MerchantId=CASE WHEN p.ProviderType='Razorpay' THEN @razorpayMerchant ELSE @openPayMerchant END THEN 1 ELSE 0 END AS bit) MerchantMatchesLocal,
 CAST(CASE WHEN p.ProviderType='Razorpay' OR p.PublicKey=@openPayPublicKey THEN 1 ELSE 0 END AS bit) PublicKeyMatchesLocal,
 CAST(CASE WHEN p.PrivateKeyConfigurationKey=CONCAT('PaymentProviders:',@code,':',p.ProviderType,':PrivateKey') THEN 1 ELSE 0 END AS bit) PrivateKeyReferenceCorrect
FROM payments.PaymentProviders p JOIN dbo.Tenants t ON t.Id=p.TenantId WHERE t.Code=@code ORDER BY p.ProviderType,p.Id;
'@ @{ code=$code; razorpayMerchant=$settings.LOCAL_RAZORPAY_MERCHANT_ID; openPayMerchant=$settings.LOCAL_OPENPAY_MERCHANT_ID; openPayPublicKey=$settings.LOCAL_OPENPAY_PUBLIC_KEY }
        $providerTypes = @($providerRows.Rows | ForEach-Object { [string]$_.ProviderType })
        if (@($providerTypes | Sort-Object -Unique).Count -ne $providerTypes.Count) { throw 'Duplicate provider rows exist.' }
        foreach ($provider in $providers) { if ($provider -notin $providerTypes) { throw "Provider '$provider' is missing from the tenant business database." } }
        $providerEvidence = @()
        foreach ($row in $providerRows.Rows) {
            $expected3Ds = [bool]$contract.providerDefaults.PSObject.Properties[[string]$row.ProviderType].Value.use3DSecure
            if (-not [bool]$row.MerchantMatchesLocal -or -not [bool]$row.PublicKeyMatchesLocal -or -not [bool]$row.PrivateKeyReferenceCorrect -or [bool]$row.IsProduction -or [bool]$row.Use3DSecure -ne $expected3Ds) {
                throw "Provider '$($row.ProviderType)' metadata, sandbox flag, or configured 3DS baseline mismatch."
            }
            $providerEvidence += [ordered]@{ provider=[string]$row.ProviderType; threeDs=[bool]$row.Use3DSecure; merchantMatchesLocal=[bool]$row.MerchantMatchesLocal; publicKeyMatchesLocal=[bool]$row.PublicKeyMatchesLocal; privateKeyReferenceCorrect=[bool]$row.PrivateKeyReferenceCorrect; nonProduction=(-not [bool]$row.IsProduction) }
        }
        $counts = Invoke-SeedContractQuery $businessDatabase 'SELECT (SELECT COUNT(*) FROM orders.Customers WHERE TenantId=@id) Customers,(SELECT COUNT(*) FROM inventory.Products WHERE TenantId=@id) Products' @{ id=[int]$registry.Id }
        if ([int]$counts.Rows[0].Customers -lt 1 -or [int]$counts.Rows[0].Products -lt 1) { throw 'Tenant is missing customers or products.' }
        $tenantResults.Add([ordered]@{ tenant=$code; status=[string]$registry.Status; tier=[string]$registry.TenantTier; registryRoute=[string]$registry.PaymentProviderCode; businessDatabase=$businessDatabase; providers=$providerEvidence; customerCount=[int]$counts.Rows[0].Customers; productCount=[int]$counts.Rows[0].Products })
    } catch { $failures.Add("$code validation failed: $($_.Exception.Message)") }
}

[void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
$report = [ordered]@{ capturedUtc=[DateTime]::UtcNow.ToString('o'); scope='docker-dev'; contractPath='Resources/Configuration/tenant-bootstrap.local.json'; status=$(if ($failures.Count) {'failed'} else {'passed'}); activeTenantCount=$tenantResults.Count; supportedProviders=$providers; failures=@($failures); tenants=@($tenantResults) }
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $output -Encoding utf8
if ($failures.Count) { throw 'Read-only seed/provider contract failed. No reseeding or credential repair was performed; inspect the sanitized report.' }
Write-Host "Read-only seed/provider contract passed for $($tenantResults.Count) active tenant(s) and $($providers.Count) providers each."
