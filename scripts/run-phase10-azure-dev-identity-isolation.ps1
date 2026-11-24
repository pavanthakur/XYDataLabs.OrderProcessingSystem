#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName='ExplicitSubscription')]
param(
    [Parameter(Mandatory,ParameterSetName='ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory,ParameterSetName='PromptSubscription')][switch]$PromptForExpectedSubscriptionId,
    [string]$ManifestPath = (Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-entra-test-users.dev.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not [Environment]::UserInteractive -or $env:CI -eq 'true') { throw 'Regular-user sign-in tests require a headed local desktop; hosted CI is not supported.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command az -ErrorAction SilentlyContinue) -or -not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI, Node.js, and npm are required; no browser was launched.'
}
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private Entra test-user manifest is missing; run the provisioning Plan task first.' }
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
$directoryId = [guid]::Empty
if (-not [guid]::TryParse([string]$manifest.directoryId,[ref]$directoryId)) { throw 'Private manifest has no valid Entra directory ID.' }

$accountJson = & az account show --query '{id:id,tenantId:tenantId,state:state}' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI is not signed in; run az login first.' }
$account = $accountJson | ConvertFrom-Json
if ($account.state -ne 'Enabled' -or [guid]$account.tenantId -ne $directoryId) { throw 'Active Azure CLI account is not in the manifest Entra directory.' }
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify the ID above against your approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Cancelled before any runtime or Graph query.' }
    $ExpectedSubscriptionId = [guid]::Empty
    if (-not [guid]::TryParse($answer.Trim(),[ref]$ExpectedSubscriptionId)) { throw 'Enter the approved subscription GUID, not an Entra object ID.' }
}
if ([guid]$account.id -ne $ExpectedSubscriptionId) { throw 'Active Azure CLI subscription does not match the explicitly approved dev subscription.' }

$catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
$targets = @($catalog.targets | Where-Object key -eq 'azure-dev')
if ($targets.Count -ne 1) { throw 'Runtime-target catalog must contain exactly one azure-dev target.' }
$target = $targets[0]
$resourceGroup = [string]$target.azureResourceGroupName
$envName = [string]$target.azureManagedEnvironmentName
$defaultDomain = & az containerapp env show --resource-group $resourceGroup --name $envName --query properties.defaultDomain -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$defaultDomain)) { throw 'Could not resolve the live Azure-dev generated domain.' }
$gateway = & az containerapp show --resource-group $resourceGroup --name ([string]$target.azureGatewayContainerAppName) --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$gateway)) { throw 'Could not resolve the live Azure-dev API hostname.' }
$ui = & az containerapp show --resource-group $resourceGroup --name ([string]$target.azureUiContainerAppName) --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$ui)) { throw 'Could not resolve the live Azure-dev UI hostname.' }
$origins = & node (Join-Path $PSScriptRoot 'resolve-phase10-azure-generated-urls.mjs') --target azure-dev --default-domain ([string]$defaultDomain) --gateway-fqdn ([string]$gateway) --ui-fqdn ([string]$ui) --require-live-apps
if ($LASTEXITCODE -ne 0) { throw 'Generated dev UI/API origin validation failed.' }
$resolved = $origins | ConvertFrom-Json

# A read-only verification gate proves the guest/claim baseline before opening a browser.
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-entra-test-users.ps1') -Mode Verify -ManifestPath $manifestFullPath -ExpectedDirectoryId $directoryId -ExpectedSubscriptionId $ExpectedSubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Entra test-user verification failed; no browser was launched.' }

function Get-DeploymentFingerprint {
    $parts = @()
    foreach ($property in @('azureGatewayContainerAppName','azureOrdersContainerAppName','azurePaymentsContainerAppName','azureInventoryContainerAppName','azureNotificationsContainerAppName','azureUiContainerAppName')) {
        $name = [string]$target.$property
        $json = & az containerapp show --resource-group $resourceGroup --name $name --query '{id:id,revision:properties.latestReadyRevisionName,template:properties.template,traffic:properties.configuration.ingress.traffic}' -o json --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { throw 'Could not capture deployed image/revision identity; browser was not launched.' }
        $parts += ($json | ConvertFrom-Json | ConvertTo-Json -Depth 50 -Compress)
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

$priorUi = $env:PHASE10_AZURE_UI_ORIGIN
$priorApi = $env:PHASE10_AZURE_API_ORIGIN
$priorManifest = $env:PHASE10_ENTRA_TEST_USERS_MANIFEST
$priorDeployment = $env:PHASE10_AZURE_DEPLOYMENT_IDENTITY_SHA256
$priorSourceRevision = $env:PHASE10_RUNNER_SOURCE_REVISION
$priorSourceDirty = $env:PHASE10_RUNNER_SOURCE_DIRTY
$priorRunnerSource = $env:PHASE10_RUNNER_SOURCE_SHA256
try {
    $sourceRevision = (& git -C $repoRoot rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceRevision -notmatch '^[0-9a-f]{40}$') { throw 'Could not identify the runner source revision.' }
    $sourceStatus = & git -C $repoRoot status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine whether the runner worktree is dirty.' }
    $runnerFiles = @('scripts/phase10-entra-test-users.ps1','scripts/phase10-entra-test-users.module.psm1',
        'scripts/run-phase10-azure-dev-identity-isolation.ps1','automation/src/browser/entra-regular-user-isolation.browser.test.ts')
    $sourceContent = foreach ($file in $runnerFiles) {
        $path = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'A required identity runner source file is missing.' }
        "$file`n" + (Get-Content -LiteralPath $path -Raw)
    }
    $runnerBytes = [Text.Encoding]::UTF8.GetBytes(($sourceContent -join "`n"))
    $env:PHASE10_RUNNER_SOURCE_REVISION = $sourceRevision
    $env:PHASE10_RUNNER_SOURCE_DIRTY = if (@($sourceStatus).Count -gt 0) { 'true' } else { 'false' }
    $env:PHASE10_RUNNER_SOURCE_SHA256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($runnerBytes)).ToLowerInvariant()
    $env:PHASE10_AZURE_UI_ORIGIN = [string]$resolved.uiOrigin
    $env:PHASE10_AZURE_API_ORIGIN = [string]$resolved.apiOrigin
    $env:PHASE10_ENTRA_TEST_USERS_MANIFEST = $manifestFullPath
    $env:PHASE10_AZURE_DEPLOYMENT_IDENTITY_SHA256 = Get-DeploymentFingerprint
    Push-Location $repoRoot
    try { & npm --prefix automation run test:azure:regular-user-isolation; $testExit = $LASTEXITCODE }
    finally { Pop-Location }
    if ($testExit -ne 0) { exit $testExit }
    $after = Get-DeploymentFingerprint
    if ($after -ne $env:PHASE10_AZURE_DEPLOYMENT_IDENTITY_SHA256) { throw 'Deployment identity changed during the browser run; evidence is invalidated.' }
}
finally {
    $env:PHASE10_AZURE_UI_ORIGIN = $priorUi
    $env:PHASE10_AZURE_API_ORIGIN = $priorApi
    $env:PHASE10_ENTRA_TEST_USERS_MANIFEST = $priorManifest
    $env:PHASE10_AZURE_DEPLOYMENT_IDENTITY_SHA256 = $priorDeployment
    $env:PHASE10_RUNNER_SOURCE_REVISION = $priorSourceRevision
    $env:PHASE10_RUNNER_SOURCE_DIRTY = $priorSourceDirty
    $env:PHASE10_RUNNER_SOURCE_SHA256 = $priorRunnerSource
}
