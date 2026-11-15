#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TenantCode,
    [Parameter(Mandatory)][string]$OrderId,
    [Parameter(Mandatory)][long]$ExpectedAmountMinor,
    [Parameter(Mandatory)][guid]$ExpectedSubscriptionId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-razorpay-order-lookup-core.ps1')
. (Join-Path $PSScriptRoot '../Resources/Azure-Deployment/phase10-keyvault-command-helpers.ps1')
if ($TenantCode -cnotmatch '^[A-Za-z0-9_-]{1,64}$' -or $OrderId -cnotmatch '^order_[A-Za-z0-9]{1,80}$' -or $ExpectedAmountMinor -le 0) { throw 'Invalid diagnostic parameters.' }
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REF -ne 'refs/heads/dev') { throw 'Run this diagnostic through the dev OIDC workflow; local-user secret access is not required or granted.' }
$target = (Get-Content (Join-Path $PSScriptRoot '../automation/config/runtime-targets.json') -Raw | ConvertFrom-Json).targets | Where-Object key -eq 'azure-dev'
$subscription = & az account show --query id -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or $subscription.Trim() -ne $ExpectedSubscriptionId.ToString('D')) { throw 'Subscription mismatch; no secrets or provider data were read.' }
$keyId = $null; $privateKey = $null
$root = Join-Path $PSScriptRoot '../TestResults/Playwright/azure-https/razorpay-order-lookup'
[void][IO.Directory]::CreateDirectory($root)
$report = [ordered]@{ tenant=$TenantCode; environment='azure-dev'; sourceRevision=$env:GITHUB_SHA; runId=$env:GITHUB_RUN_ID; observedUtc=[DateTime]::UtcNow.ToString('o'); status='BLOCKED'; limitation='Provider lookup only; not SQL reconciliation, payment submission or full acceptance. Never auto-retry this order.' }
try {
    $gatewayFqdn = & az containerapp show --resource-group $target.azureResourceGroupName --name $target.azureGatewayContainerAppName --query properties.configuration.ingress.fqdn -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or $gatewayFqdn.Trim() -cnotmatch '^[a-z0-9.-]+\.azurecontainerapps\.io$') { throw 'Live dev Gateway hostname unavailable.' }
    $registryResponse = Invoke-RestMethod -Uri "https://$($gatewayFqdn.Trim())/api/v1/Info/tenant-registry" -Method Get -MaximumRedirection 0 -TimeoutSec 30
    $registry = @($registryResponse)
    if (@($registry | Where-Object { $_.TenantCode -ceq $TenantCode }).Count -ne 1) { throw 'Requested tenant is not uniquely present in the active dev registry.' }
    $merchant = Get-Phase10KeyVaultSecret -KeyVaultName $target.azureKeyVaultName -SecretName 'Razorpay--MerchantId' -Attempts 1
    if ($merchant.State -ne 'Found') { throw 'Razorpay sandbox key ID unavailable; check existing OIDC access without broadening operator permissions.' }
    $keyId = $merchant.Value
    if ($keyId -cnotmatch '^rzp_test_[A-Za-z0-9]+$') { throw 'Non-sandbox key ID rejected before provider lookup.' }
    $secret = Get-Phase10KeyVaultSecret -KeyVaultName $target.azureKeyVaultName -SecretName "PaymentProviders--$TenantCode--Razorpay--PrivateKey" -Attempts 1 -SecretValues @($keyId)
    if ($secret.State -ne 'Found') { throw 'Tenant-scoped provider key unavailable; no fallback or access grant attempted.' }
    $privateKey = $secret.Value
    $evidence = Get-Phase10RazorpayOrderEvidence -OrderId $OrderId -KeyId $keyId -PrivateKey $privateKey -ExpectedAmountMinor $ExpectedAmountMinor -ExpectedCurrency INR
    $report.evidence = $evidence
    Write-Host "Read-only provider lookup complete: classification=$($evidence.classification); paymentCount=$($evidence.paymentCount). No charge submitted."
    if ($evidence.classification -in @('UNRESOLVED','AUTHORIZED_NOT_CAPTURED')) { throw 'Provider state still requires review; no automatic capture/retry is permitted.' }
    $report.status = 'LOOKUP_COMPLETE'
} catch {
    throw 'Read-only provider lookup blocked or unresolved; sanitized evidence retained. No charge/capture/refund was requested.'
} finally {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root "$TenantCode-$OrderId.json") -Encoding utf8
    $keyId=$null; $privateKey=$null; $merchant=$null; $secret=$null
}
