#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'ExplicitSubscription')]
param(
    [Parameter(Mandatory)][ValidateSet('AuthPreflight','ProviderMatrix','NonAdminSandbox','Reconcile')][string]$Mode,
    [Parameter(Mandatory, ParameterSetName = 'ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory, ParameterSetName = 'PromptSubscription')][switch]$PromptForExpectedSubscriptionId,
    [string]$ExpectedUiOrigin = $env:IDENTITY_PUBLIC_WEB_ORIGIN,
    [string]$ResumeCheckpoint,
    [switch]$RequireSandboxConfirmation,
    [ValidateSet('guest','member')][string]$IdentityType = 'guest',
    [string]$ManifestPath,
    [switch]$NonAdminPreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ($Mode -ne 'Reconcile' -and (-not [Environment]::UserInteractive -or $env:CI -eq 'true')) { throw 'Run this headed operator command in your signed-in desktop terminal, not a hosted/non-interactive job.' }
if ($ResumeCheckpoint -and $Mode -notin @('ProviderMatrix','Reconcile')) { throw 'ResumeCheckpoint is available only for ProviderMatrix or Reconcile.' }
if ($Mode -eq 'Reconcile' -and -not $ResumeCheckpoint) { throw 'Reconcile requires an existing ResumeCheckpoint; it never creates orders/payments or opens a browser.' }
if ($RequireSandboxConfirmation -and $Mode -ne 'ProviderMatrix') { throw 'Sandbox confirmation applies only to ProviderMatrix.' }
if ($NonAdminPreflightOnly -and $Mode -ne 'NonAdminSandbox') { throw 'NonAdminPreflightOnly requires NonAdminSandbox mode.' }
if ($Mode -ne 'NonAdminSandbox' -and $IdentityType -ne 'guest') { throw 'IdentityType applies only to NonAdminSandbox mode.' }
if ($PromptForExpectedSubscriptionId -and $Mode -eq 'Reconcile') { throw 'Reconcile requires an explicit expected subscription ID.' }
if ($Mode -eq 'NonAdminSandbox' -and [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $manifestName = if ($IdentityType -eq 'member') { 'phase10-entra-member-test-users/phase10-entra-member-test-users.dev.json' } else { 'phase10-entra-test-users.dev.json' }
    $ManifestPath = Join-Path $env:LOCALAPPDATA (Join-Path 'XYDataLabs' $manifestName)
}
$targetCatalogPath = Join-Path $repoRoot 'automation/config/runtime-targets.json'
$targetCatalog = Get-Content -LiteralPath $targetCatalogPath -Raw | ConvertFrom-Json
$targets = @($targetCatalog.targets | Where-Object key -eq 'azure-dev')
if ($targets.Count -ne 1) { throw 'Runtime target catalog must contain exactly one azure-dev target.' }
$target = $targets[0]

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required; no browser or payment action was started.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'Node.js and npm are required; no browser or payment action was started.' }
function Get-ActiveAzureSubscription {
    $accountJson = & az account show --query '{id:id,state:state}' -o json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI is not logged in; run az login and select the approved subscription.' }
    $account = $accountJson | ConvertFrom-Json
    $activeId = [guid]::Empty
    if ($account.state -ne 'Enabled' -or -not [guid]::TryParse([string]$account.id, [ref]$activeId) -or $activeId -eq [guid]::Empty) {
        throw 'Azure CLI did not return an enabled active subscription with a valid GUID.'
    }
    return $activeId
}

$activeSubscription = Get-ActiveAzureSubscription
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $activeSubscription"
    $answer = Read-Host 'Verify the ID above against your approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Cancelled before querying Azure resources or launching the browser.' }
    $confirmedSubscriptionId = [guid]::Empty
    if (-not [guid]::TryParse($answer.Trim(), [ref]$confirmedSubscriptionId)) { throw 'Enter the approved Azure subscription GUID, not an Entra object ID or subscription name.' }
    $ExpectedSubscriptionId = $confirmedSubscriptionId
}
$expectedSubscription = $ExpectedSubscriptionId.ToString('D')
if ($activeSubscription -ne $ExpectedSubscriptionId) { throw 'The active Azure subscription does not match the explicitly supplied expected subscription ID.' }
if ($RequireSandboxConfirmation -or ($Mode -eq 'NonAdminSandbox' -and -not $NonAdminPreflightOnly) -or ($PromptForExpectedSubscriptionId -and $Mode -eq 'ProviderMatrix')) {
    $confirmation = Read-Host 'This task creates fresh Azure-dev orders and submits sandbox payments. Type RUN SANDBOX to continue'
    if ($confirmation -cne 'RUN SANDBOX') { throw 'Sandbox matrix cancelled before querying Azure resources or submitting payments.' }
}
if (($PromptForExpectedSubscriptionId -or $RequireSandboxConfirmation -or $Mode -eq 'NonAdminSandbox') -and (Get-ActiveAzureSubscription) -ne $ExpectedSubscriptionId) {
    throw 'The active Azure subscription changed during confirmation; no Azure resources were queried and the browser was not launched.'
}

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

# Hash live app templates/revisions locally. Never print environment values or secret references.
$deploymentParts = @()
foreach ($property in @('azureGatewayContainerAppName','azureOrdersContainerAppName','azurePaymentsContainerAppName','azureInventoryContainerAppName','azureNotificationsContainerAppName','azureUiContainerAppName')) {
    $appName = [string]$target.$property
    $identityJson = & az containerapp show --resource-group $resourceGroup --name $appName --query '{id:id,revision:properties.latestReadyRevisionName,template:properties.template,traffic:properties.configuration.ingress.traffic}' -o json --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $identityJson) { throw 'Could not establish live deployment identity; browser launch blocked.' }
    $identity = $identityJson | ConvertFrom-Json
    if ($ResumeCheckpoint -and @($identity.template.containers | Where-Object { $_.image -notmatch '@sha256:[a-f0-9]{64}$' }).Count -gt 0) { throw 'Resume requires immutable image digest references; mutable image tags cannot certify deployment continuity.' }
    $deploymentParts += ($identity | ConvertTo-Json -Depth 50 -Compress)
}
$deploymentBytes = [Text.Encoding]::UTF8.GetBytes(($deploymentParts -join "`n"))
$deploymentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($deploymentBytes))
$priorDeploymentIdentity = $env:XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY
$priorSettingsIdentity = $env:XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY
$priorNonAdminManifest = $env:XYDATALABS_NONADMIN_VERIFIED_MANIFEST
$priorNonAdminIdentityType = $env:XYDATALABS_NONADMIN_IDENTITY_TYPE
$verifiedManifest = $null
$settingsHash = $null

if ($Mode -eq 'AuthPreflight') {
    $matrixArgs = @('--target','azure-dev','--headed','--operator-assisted-entra','--auth-preflight-only')
    Write-Host 'Starting headed no-charge Entra preflight. Complete sign-in once; this mode creates no orders and submits no payments.'
}
elseif ($Mode -eq 'NonAdminSandbox') {
    $verifiedManifest = [IO.Path]::GetFullPath($ManifestPath)
    $verifierName = if ($IdentityType -eq 'member') { 'phase10-entra-member-test-users.ps1' } else { 'phase10-entra-test-users.ps1' }
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot $verifierName) -Mode Verify -ManifestPath $verifiedManifest -ExpectedSubscriptionId $ExpectedSubscriptionId
    if ($LASTEXITCODE -ne 0) { throw "$IdentityType identity or tenant-claim verification failed. No orders or payments were attempted." }
    $matrixArgs = @('--target','azure-dev','--headed','--operator-assisted-entra','--non-admin-sandbox',
        '--tenant','TenantA','--tenant','TenantB','--tenant','TenantC','--tenant-timeout-ms','600000')
    if ($NonAdminPreflightOnly) {
        $matrixArgs += '--auth-preflight-only'
        Write-Host "TenantA only: verify the assigned $IdentityType identity, access, sandbox settings and sign-out. No orders or payments."
    } else {
        Write-Host "One normal Entra sign-in per non-admin $IdentityType account. The assigned providers will not be changed."
    }
}
else {
    Write-Host 'Running no-charge Azure SQL/provider fixture preflight before opening the browser.'
    $inspectionLines = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-azure-payment-test-state.ps1') `
        -Action Inspect -Environment dev -ExpectedSubscriptionId $expectedSubscription
    )
    if ($LASTEXITCODE -ne 0) { throw 'Azure tenant/provider SQL preflight failed; no browser or payment was started.' }
    $inspection = $null
    for ($lineIndex = 0; $lineIndex -lt $inspectionLines.Count; $lineIndex++) {
        try {
            $parsed = ($inspectionLines[$lineIndex..($inspectionLines.Count-1)] -join "`n") | ConvertFrom-Json
            if ($parsed.status -eq 'PASS' -and $parsed.tenants -and $parsed.reportPath) { $inspection = $parsed; break }
        } catch { }
    }
    if (-not $inspection) { throw 'Fixture preflight did not return a valid baseline; no browser was launched.' }
    $baseline = @($inspection.tenants | Sort-Object tenantCode | ForEach-Object {
        [ordered]@{ tenant=$_.tenantCode; tier=$_.tier; route=$_.assignedProvider; providers=@($_.configuredProviders | Sort-Object provider) }
    }) | ConvertTo-Json -Depth 10 -Compress
    $settingsHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($baseline)))
    $matrixArgs = @('--target','azure-dev','--headed','--operator-assisted-entra','--all-active-tenants','--provider','Razorpay','--provider','OpenPay','--tenant-timeout-ms','420000')
    if ($ResumeCheckpoint) { $matrixArgs += @('--resume-checkpoint',$ResumeCheckpoint) }
    if($Mode -eq 'Reconcile'){Write-Host 'Read-only checkpoint recovery selected: no browser, new order or charge.'}
    else {Write-Warning 'This mode first performs a no-charge Entra tenant/access preflight in the same in-memory browser session, then creates fresh orders and submits serial sandbox payments for every active tenant/provider pair. Continue only after the hosted OIDC provider-secret preflight and local SQL fixture inspection have passed.'}
}

Push-Location $repoRoot
try {
    $env:XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY = $deploymentHash
    $env:XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY = $settingsHash
    $env:XYDATALABS_NONADMIN_VERIFIED_MANIFEST = $verifiedManifest
    $env:XYDATALABS_NONADMIN_IDENTITY_TYPE = if ($Mode -eq 'NonAdminSandbox') { $IdentityType } else { $null }
    if($Mode -eq 'Reconcile'){ & npm --prefix automation run reconcile:azure:checkpoint -- --checkpoint $ResumeCheckpoint }
    else { & npm --prefix automation run run:azure:matrix -- @matrixArgs }
    $matrixExit = $LASTEXITCODE
}
finally {
    Pop-Location
    $env:XYDATALABS_AZURE_DEV_DEPLOYMENT_IDENTITY = $priorDeploymentIdentity
    $env:XYDATALABS_AZURE_DEV_SETTINGS_IDENTITY = $priorSettingsIdentity
    $env:XYDATALABS_NONADMIN_VERIFIED_MANIFEST = $priorNonAdminManifest
    $env:XYDATALABS_NONADMIN_IDENTITY_TYPE = $priorNonAdminIdentityType
}
exit $matrixExit
