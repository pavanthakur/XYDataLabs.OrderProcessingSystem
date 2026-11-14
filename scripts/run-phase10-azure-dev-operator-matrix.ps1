#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('AuthPreflight','ProviderMatrix')][string]$Mode,
    [Parameter(Mandatory)][guid]$ExpectedSubscriptionId,
    [string]$ExpectedUiOrigin = $env:IDENTITY_PUBLIC_WEB_ORIGIN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$targetCatalogPath = Join-Path $repoRoot 'automation/config/runtime-targets.json'
$targetCatalog = Get-Content -LiteralPath $targetCatalogPath -Raw | ConvertFrom-Json
$targets = @($targetCatalog.targets | Where-Object key -eq 'azure-dev')
if ($targets.Count -ne 1) { throw 'Runtime target catalog must contain exactly one azure-dev target.' }
$target = $targets[0]

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required; no browser or payment action was started.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'Node.js and npm are required; no browser or payment action was started.' }
$accountJson = & az account show --query '{id:id,state:state}' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI is not logged in; run az login and select the approved subscription.' }
$account = $accountJson | ConvertFrom-Json
$expectedSubscription = $ExpectedSubscriptionId.ToString('D')
if ($account.state -ne 'Enabled' -or $account.id -ne $expectedSubscription) { throw 'The active Azure subscription does not match the explicitly supplied expected subscription ID.' }

$resourceGroup = [string]$target.azureResourceGroupName
$environmentName = [string]$target.azureManagedEnvironmentName
$gatewayName = [string]$target.azureGatewayContainerAppName
$uiName = [string]$target.azureUiContainerAppName
$defaultDomain = & az containerapp env show --resource-group $resourceGroup --name $environmentName --query properties.defaultDomain -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($defaultDomain)) { throw 'Could not resolve the live Azure Container Apps environment domain.' }
$gatewayFqdn = & az containerapp show --resource-group $resourceGroup --name $gatewayName --query properties.configuration.ingress.fqdn -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gatewayFqdn)) { throw 'Could not resolve the live Azure Gateway hostname.' }
$uiFqdn = & az containerapp show --resource-group $resourceGroup --name $uiName --query properties.configuration.ingress.fqdn -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($uiFqdn)) { throw 'Could not resolve the live Azure UI hostname.' }

$resolverArgs = @(
    (Join-Path $repoRoot 'scripts/resolve-phase10-azure-generated-urls.mjs'),
    '--target','azure-dev','--default-domain',[string]$defaultDomain,
    '--gateway-fqdn',[string]$gatewayFqdn,'--ui-fqdn',[string]$uiFqdn,'--require-live-apps'
)
if (-not [string]::IsNullOrWhiteSpace($ExpectedUiOrigin)) { $resolverArgs += @('--expected-ui-origin',$ExpectedUiOrigin) }
$resolvedJson = & node @resolverArgs
if ($LASTEXITCODE -ne 0) { throw 'Live Azure-dev generated URL validation failed.' }
$resolved = $resolvedJson | ConvertFrom-Json
$env:XYDATALABS_RUNTIME_TARGET_AZURE_DEV_BASE_URL = [string]$resolved.uiOrigin
$env:XYDATALABS_RUNTIME_TARGET_AZURE_DEV_API_BASE_URL = [string]$resolved.apiOrigin
$env:EXPECTED_AZURE_SUBSCRIPTION_ID = $expectedSubscription

if ($Mode -eq 'AuthPreflight') {
    $matrixArgs = @('--target','azure-dev','--headed','--operator-assisted-entra','--auth-preflight-only')
    Write-Host 'Starting headed no-charge Entra preflight. Complete sign-in once; this mode creates no orders and submits no payments.'
}
else {
    Write-Host 'Running no-charge Azure SQL/provider fixture preflight before opening the browser.'
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-azure-payment-test-state.ps1') `
        -Action Inspect -Environment dev -ExpectedSubscriptionId $expectedSubscription
    if ($LASTEXITCODE -ne 0) { throw 'Azure tenant/provider SQL preflight failed; no browser or payment was started.' }
    $matrixArgs = @('--target','azure-dev','--headed','--operator-assisted-entra','--all-active-tenants','--provider','Razorpay','--provider','OpenPay','--tenant-timeout-ms','420000')
    Write-Warning 'This mode first performs a no-charge Entra tenant/access preflight in the same in-memory browser session, then creates fresh orders and submits serial sandbox payments for every active tenant/provider pair. Continue only after the hosted OIDC provider-secret preflight and local SQL fixture inspection have passed.'
}

Push-Location $repoRoot
try {
    & npm --prefix automation run run:azure:matrix -- @matrixArgs
    $matrixExit = $LASTEXITCODE
}
finally { Pop-Location }
exit $matrixExit
