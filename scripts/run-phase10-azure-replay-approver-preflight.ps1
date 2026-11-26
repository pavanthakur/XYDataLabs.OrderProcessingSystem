#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'ExplicitSubscription')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory, ParameterSetName = 'PromptSubscription')][switch]$PromptForExpectedSubscriptionId,
    [string]$ManifestPath = (Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-replay-approver/phase10-replay-approver.dev.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $IsWindows -or -not [Environment]::UserInteractive -or $env:CI -eq 'true') { throw 'Run this no-mutation preflight in an interactive Windows desktop terminal.' }
foreach ($tool in @('az','node','npm','pwsh')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required local tool '$tool' is unavailable; no browser was opened." } }

$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$privateRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-replay-approver')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $manifestFullPath.StartsWith($privateRoot,[StringComparison]::OrdinalIgnoreCase) -or $manifestFullPath.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'The replay approver manifest must remain in its private LocalAppData directory.' }
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private replay approver manifest is missing.' }
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.environment -cne 'dev' -or $manifest.identityType -cne 'replay-approver' -or $manifest.tenantCode -cne 'TenantA') { throw 'Private manifest is not the approved Azure-dev TenantA replay approver.' }

$accountJson = & az account show --query '{id:id,tenantId:tenantId,state:state}' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI is not authenticated; no browser was opened.' }
$account = $accountJson | ConvertFrom-Json
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify this is the approved Azure-dev subscription and paste its GUID (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer) -or [guid]$answer.Trim() -ne [guid]$account.id) { throw 'Subscription confirmation failed; no downstream check ran.' }
    $ExpectedSubscriptionId = [guid]$account.id
}
if ($account.state -ne 'Enabled' -or [guid]$account.id -ne $ExpectedSubscriptionId -or [guid]$account.tenantId -ne [guid]$manifest.directoryId -or [guid]$manifest.subscriptionId -ne $ExpectedSubscriptionId) { throw 'CLI subscription or directory does not match the pinned dev manifest.' }

Write-Host 'Step 1/4: verifying the dedicated approver account (read-only).'
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-entra-replay-approver-account.ps1') -Mode Verify -ManifestPath $manifestFullPath -ExpectedSubscriptionId $ExpectedSubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Approver account verification failed; no browser was opened.' }
Write-Host 'Step 2/4: verifying the direct phase10-operator app-role assignment (read-only).'
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-entra-replay-approver.ps1') -Mode Verify -ManifestPath $manifestFullPath -ExpectedSubscriptionId $ExpectedSubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Approver app-role verification failed; no browser was opened.' }
Write-Host 'Step 3/4: operator-side infrastructure and runner assignment inspection (not a signed-in runner check).'
$preflightReport = Join-Path $repoRoot ("TestResults/Phase10/azure-replay-approver-preflight/runner-preflight-{0}.json" -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'phase10-azure-replay-drill-preflight.ps1') -ExpectedSubscriptionId $ExpectedSubscriptionId -RunnerPrincipalObjectId ([string]$manifest.replayRunnerObjectId) -ReportPath $preflightReport
if ($LASTEXITCODE -ne 0) { throw 'Replay runner preflight did not pass; no browser was opened.' }

$catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
$target = @($catalog.targets | Where-Object key -eq 'azure-dev')
if ($target.Count -ne 1) { throw 'Runtime target catalog must contain exactly one Azure-dev target.' }
$target = $target[0]
$defaultDomain = & az containerapp env show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureManagedEnvironmentName --query properties.defaultDomain -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Azure-dev environment domain lookup failed; no browser was opened.' }
$gatewayFqdn = & az containerapp show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureGatewayContainerAppName --query properties.configuration.ingress.fqdn -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Azure-dev gateway lookup failed; no browser was opened.' }
$uiFqdn = & az containerapp show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureUiContainerAppName --query properties.configuration.ingress.fqdn -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$defaultDomain) -or [string]::IsNullOrWhiteSpace([string]$gatewayFqdn) -or [string]::IsNullOrWhiteSpace([string]$uiFqdn)) { throw 'Azure-dev UI/API origins are unavailable; no browser was opened.' }
$resolver = Join-Path $PSScriptRoot 'resolve-phase10-azure-generated-urls.mjs'
$resolvedJson = & node $resolver --target azure-dev --default-domain ([string]$defaultDomain) --gateway-fqdn ([string]$gatewayFqdn) --ui-fqdn ([string]$uiFqdn) --require-live-apps
if ($LASTEXITCODE -ne 0) { throw 'Azure-generated URL validation failed; no browser was opened.' }
$resolved = $resolvedJson | ConvertFrom-Json

$envNames = @('PHASE10_REPLAY_APPROVER_MANIFEST','PHASE10_AZURE_UI_ORIGIN','PHASE10_AZURE_API_ORIGIN')
$priorValues = @{}; foreach ($name in $envNames) { $priorValues[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:PHASE10_REPLAY_APPROVER_MANIFEST = $manifestFullPath
    $env:PHASE10_AZURE_UI_ORIGIN = [string]$resolved.uiOrigin
    $env:PHASE10_AZURE_API_ORIGIN = [string]$resolved.apiOrigin
    Write-Host 'Step 4/4: opening one headed browser. Complete normal Entra sign-in/MFA; the test only reads TenantA and signs out. No replay approval, message, order, or payment is submitted.'
    Push-Location $repoRoot
    try { & npm --prefix automation run test:azure:replay-approver-preflight; $testExit = $LASTEXITCODE }
    finally { Pop-Location }
    if ($testExit -ne 0) { throw 'Replay approver token preflight failed; no replay mutation was attempted.' }
}
finally { foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name,$priorValues[$name],'Process') } }
