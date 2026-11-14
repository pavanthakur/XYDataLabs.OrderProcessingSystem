#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'phase10-azure-payment-test-state.ps1'
. $scriptPath -LibraryOnly -ExpectedSubscriptionId 'subscription-fixture'

$script:fixtureRoute = 'OpenPay'
$script:fixtureFlags = @{ OpenPay = $true; Razorpay = $false }
$script:fixtureCalls = [System.Collections.Generic.List[object]]::new()
$script:AzureFixtureSubscription = 'subscription-fixture'
$script:Action = 'Prepare'
$script:Environment = 'dev'
$script:TenantCode = 'Clinic-West-47'
$script:ProviderType = 'Razorpay'
$script:ThreeDs = 'false'
$script:ApiBaseUrl = 'https://fixture.azurecontainerapps.io'
$selfTestDirectory = Join-Path $repoRoot ('TestResults/Playwright/azure-https/fixture-selftest-' + [guid]::NewGuid().ToString('N'))
$script:ManifestPath = Join-Path $selfTestDirectory 'fixture.json'

function Get-AzureFixtureTarget {
    return [pscustomobject]@{
        azureResourceGroupName = 'rg-fixture-dev'
        azureSqlServerName = 'sql-fixture-dev'
        azureOperationsDatabaseName = 'OperationsFixture'
        azureKeyVaultName = 'kv-fixture-dev'
    }
}
function Initialize-AzureFixtureSql { $script:AzureFixtureSubscription = 'subscription-fixture' }
function Invoke-AzureFixtureCli {
    param([string[]]$Arguments)
    if ($Arguments[0] -ne 'sql' -or $Arguments[1] -ne 'db' -or $Arguments[2] -ne 'list') { throw 'Unexpected Azure CLI command in topology fixture test.' }
    return '[{"name":"BusinessFixture","tags":{"app":"orderprocessing","env":"dev","tenancy":"dedicated","tenant":"Clinic-West-47"}},{"name":"master","tags":null},{"name":"UnrelatedFixture","tags":{"tenant":"Clinic-West-47","env":"dev","tenancy":"shared","app":"other"}}]'
}
function Get-AzureFixtureTenant {
    param([string]$Code)
    return [ordered]@{
        tenantCode = $Code; tenantId = 71; tier = 'Dedicated'; status = 'Active'
        registryDatabase = 'OperationsFixture'; registryRoute = $script:fixtureRoute
        businessDatabase = 'BusinessFixture'
        providers = @(
            [ordered]@{ id = 8; provider = 'OpenPay'; threeDs = $script:fixtureFlags.OpenPay; production = $false }
            [ordered]@{ id = 9; provider = 'Razorpay'; threeDs = $script:fixtureFlags.Razorpay; production = $false }
        )
    }
}
function Invoke-AzureFixtureSql {
    param([string]$Database,[string]$Query,[hashtable]$Parameters,[switch]$NonQuery)
    $script:fixtureCalls.Add([pscustomobject]@{ Database = $Database; Query = $Query; Parameters = $Parameters })
    if ($Query -match 'CanUpdatePaymentProviderRoute;') { return @([pscustomobject]@{ TenantTableExists = 1; PaymentProviderCodeColumnExists = 1; CanUpdatePaymentProviderRoute = 1 }) }
    if ($Query -match 'CanUpdateThreeDsFlag;') { return @([pscustomobject]@{ PaymentProvidersTableExists = 1; Use3DSecureColumnExists = 1; CanUpdateThreeDsFlag = 1 }) }
    if ($Query -match 'UPDATE dbo\.Tenants SET PaymentProviderCode') {
        if ($Database -ne 'OperationsFixture') { throw 'Registry update used the wrong database.' }
        $script:fixtureRoute = [string]$Parameters.value
        return 1
    }
    if ($Query -match 'UPDATE payments\.PaymentProviders SET Use3DSecure') {
        if ($Database -ne 'BusinessFixture') { throw 'Provider flag update used the wrong business database.' }
        $script:fixtureFlags[[string]$Parameters.provider] = ([string]$Parameters.value -eq '1')
        return 1
    }
    throw 'Unexpected SQL in fixture test.'
}
function Invoke-RestMethod {
    param([string]$Uri,[string]$Method,[int]$TimeoutSec)
    if ($Uri -notmatch '/api/v1/Info/tenant-registry$' -or $Method -ne 'Get') {
        throw 'Unexpected runtime verification request in fixture test.'
    }
    # Match Invoke-RestMethod's behavior for a JSON array: it returns the array as
    # one object. An outer @(Invoke-RestMethod ...) would incorrectly nest it.
    return ,@([pscustomobject]@{tenantCode='Clinic-West-47';paymentProviderCode=$script:fixtureRoute})
}
function Start-Sleep {
    param([int]$Seconds)
}

try {
    Initialize-AzureFixtureTopology
    if ($script:AzureFixtureDedicatedDatabases['clinic-west-47'].Count -ne 1 -or $script:AzureFixtureDedicatedDatabases['clinic-west-47'][0] -ne 'BusinessFixture') {
        throw 'Dedicated-database discovery failed to ignore null-tag and unrelated databases while resolving the tagged tenant database.'
    }
    Invoke-AzurePaymentFixture
    if ($script:fixtureRoute -ne 'Razorpay' -or $script:fixtureFlags.Razorpay -or -not $script:fixtureFlags.OpenPay) { throw 'Prepare did not modify only the requested route and provider flag.' }
    $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.original.businessDatabase -ne 'BusinessFixture' -or $manifest.original.registryDatabase -ne 'OperationsFixture') { throw 'Manifest did not record independent registry and business database identities.' }
    if ($manifest | ConvertTo-Json -Depth 10 -Compress | Select-String -Pattern 'password|privatekey|accessToken|credential' -Quiet) { throw 'Manifest contains a forbidden credential-bearing field.' }

    $script:Action = 'Restore'
    Invoke-AzurePaymentFixture
    if ($script:fixtureRoute -ne 'OpenPay' -or -not $script:fixtureFlags.OpenPay -or $script:fixtureFlags.Razorpay) { throw 'Restore did not return the exact original route and flags.' }
    if ((Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json).status -ne 'restored') { throw 'Restoration evidence was not retained.' }
    if (Test-Path -LiteralPath (Join-Path $selfTestDirectory 'azure-payment-fixture.lock')) { throw 'Successful restore did not release its owned lock.' }

    $outside = Join-Path ([IO.Path]::GetTempPath()) ('phase10-fixture-' + [guid]::NewGuid().ToString('N') + '.json')
    $rejected = $false
    $script:ManifestPath = $outside
    try { Assert-AzureFixtureManifestPath | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Fixture path traversal/out-of-root manifest was accepted.' }
    Write-Host 'PASS Azure SQL tag discovery, fixture prepare/restore, shared registry vs dedicated business DB, exact restoration, lock release, and manifest boundary.'
}
finally {
    if (Test-Path -LiteralPath $selfTestDirectory) { Remove-Item -LiteralPath $selfTestDirectory -Recurse -Force }
}
