[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
. (Join-Path $PSScriptRoot 'branch-policy.ps1')

$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Passes = New-Object 'System.Collections.Generic.List[string]'

function Add-Pass {
    param([string] $Message)
    $script:Passes.Add($Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Add-Failure {
    param([string] $Message)
    $script:Failures.Add($Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Assert-Condition {
    param(
        [bool] $Condition,
        [string] $PassMessage,
        [string] $FailMessage
    )

    if ($Condition) {
        Add-Pass $PassMessage
    }
    else {
        Add-Failure $FailMessage
    }
}

function Get-FileText {
    param([string] $RelativePath)

    $fullPath = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path $fullPath)) {
        throw "Required file not found: $RelativePath"
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Assert-FileContains {
    param(
        [string] $RelativePath,
        [string] $RegexPattern,
        [string] $Description
    )

    $content = Get-FileText -RelativePath $RelativePath
    Assert-Condition `
        -Condition ($content -match $RegexPattern) `
        -PassMessage "$RelativePath -> $Description" `
        -FailMessage "$RelativePath is missing expected contract: $Description"
}

function Assert-ParameterValue {
    param(
        [string] $RelativePath,
        [string] $ParameterName,
        [string] $ExpectedValue
    )

    $fullPath = Join-Path $repoRoot $RelativePath
    $json = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    $actualValue = $json.parameters.$ParameterName.value

    Assert-Condition `
        -Condition ($actualValue -eq $ExpectedValue) `
        -PassMessage "$RelativePath -> parameter '$ParameterName' = '$ExpectedValue'" `
        -FailMessage "$RelativePath -> parameter '$ParameterName' expected '$ExpectedValue' but found '$actualValue'"
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'Phase 10 Environment Contract Validation' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$branchPolicy = Get-GitHubBranchPolicy
$devDescriptor = Get-GitHubEnvironmentDescriptor -Policy $branchPolicy -EnvironmentKey 'dev'
$stagingDescriptor = Get-GitHubEnvironmentDescriptor -Policy $branchPolicy -EnvironmentKey 'staging'
$prodDescriptor = Get-GitHubEnvironmentDescriptor -Policy $branchPolicy -EnvironmentKey 'prod'

Assert-Condition `
    -Condition ($devDescriptor.GitHubEnvironment -eq 'dev' -and $devDescriptor.ResourceSuffix -eq 'dev') `
    -PassMessage "Branch policy maps dev -> GitHub environment dev -> resource suffix dev" `
    -FailMessage "Branch policy dev mapping is incorrect"

Assert-Condition `
    -Condition ($stagingDescriptor.Branch -eq 'staging' -and $stagingDescriptor.GitHubEnvironment -eq 'staging' -and $stagingDescriptor.ResourceSuffix -eq 'stg' -and $stagingDescriptor.AzureSqlDatabaseSuffix -eq 'Staging') `
    -PassMessage "Branch policy maps staging -> GitHub environment staging -> resource suffix stg -> Azure SQL suffix Staging" `
    -FailMessage "Branch policy staging mapping is incorrect"

Assert-Condition `
    -Condition ($prodDescriptor.Branch -eq 'main' -and $prodDescriptor.GitHubEnvironment -eq 'prod' -and $prodDescriptor.ResourceSuffix -eq 'prod') `
    -PassMessage "Branch policy maps main -> GitHub environment prod -> resource suffix prod" `
    -FailMessage "Branch policy prod mapping is incorrect"

Assert-ParameterValue -RelativePath 'infra/parameters/phase10-dev.json' -ParameterName 'environment' -ExpectedValue 'dev'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-dev.json' -ParameterName 'resourceSuffix' -ExpectedValue 'dev'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'environment' -ExpectedValue 'staging'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'resourceSuffix' -ExpectedValue 'stg'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-prod.json' -ParameterName 'environment' -ExpectedValue 'prod'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-prod.json' -ParameterName 'resourceSuffix' -ExpectedValue 'prod'

Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'orderEventsTopicName' -ExpectedValue 'order-events-staging'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'inventorySubscriptionName' -ExpectedValue 'inventory-order-created-staging'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'notificationsSubscriptionName' -ExpectedValue 'notifications-order-created-staging'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'deadLetterSubscriptionName' -ExpectedValue 'dlq-replay-staging'

Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern "param resourceSuffix string = ''" -Description 'top-level resourceSuffix parameter'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern "var effectiveResourceSuffix = empty\(resourceSuffix\) \? environment : resourceSuffix" -Description 'effectiveResourceSuffix normalization'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var ordersInternalAddress = 'https://\$\{ordersApp\.properties\.configuration\.ingress\.fqdn\}'" -Description 'orders backend uses ACA ingress HTTPS FQDN'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var paymentsInternalAddress = 'https://\$\{paymentsApp\.properties\.configuration\.ingress\.fqdn\}'" -Description 'payments backend uses ACA ingress HTTPS FQDN'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var inventoryInternalAddress = 'https://\$\{inventoryApp\.properties\.configuration\.ingress\.fqdn\}'" -Description 'inventory backend uses ACA ingress HTTPS FQDN'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var notificationsInternalAddress = 'https://\$\{notificationsApp\.properties\.configuration\.ingress\.fqdn\}'" -Description 'notifications backend uses ACA ingress HTTPS FQDN'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var uiInternalAddress = 'https://\$\{uiApp\.properties\.configuration\.ingress\.fqdn\}'" -Description 'ui backend uses ACA ingress HTTPS FQDN'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "ReverseProxy__Clusters__orders-cluster__Destinations__orders-primary__Address'[\s\S]*value: ordersInternalAddress" -Description 'gateway orders cluster consumes ACA FQDN address'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "ReverseProxy__Clusters__payments-cluster__Destinations__payments-primary__Address'[\s\S]*value: paymentsInternalAddress" -Description 'gateway payments cluster consumes ACA FQDN address'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "ReverseProxy__Clusters__inventory-cluster__Destinations__inventory-primary__Address'[\s\S]*value: inventoryInternalAddress" -Description 'gateway inventory cluster consumes ACA FQDN address'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "ReverseProxy__Clusters__notifications-cluster__Destinations__notifications-primary__Address'[\s\S]*value: notificationsInternalAddress" -Description 'gateway notifications cluster consumes ACA FQDN address'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "ReverseProxy__Clusters__ui-cluster__Destinations__ui-primary__Address'[\s\S]*value: uiInternalAddress" -Description 'gateway ui cluster consumes ACA FQDN address'

$resourceScopedModules = @(
    'infra/modules/servicebus.bicep',
    'infra/modules/sql.bicep',
    'infra/modules/redis.phase10.bicep',
    'infra/modules/loganalytics.phase10.bicep',
    'infra/modules/insights.phase10.bicep',
    'infra/modules/containerapps.bicep',
    'infra/modules/functions.bicep',
    'infra/modules/keyvault.phase10.bicep'
)

foreach ($modulePath in $resourceScopedModules) {
    Assert-FileContains -RelativePath $modulePath -RegexPattern "param resourceSuffix string = ''" -Description 'resourceSuffix module parameter'
    Assert-FileContains -RelativePath $modulePath -RegexPattern "effectiveResourceSuffix = empty\(resourceSuffix\) \? environment : resourceSuffix" -Description 'module resource suffix normalization'
}

Assert-FileContains -RelativePath '.github/workflows/phase10-deploy-orchestrator.yml' -RegexPattern 'options:\s*\r?\n\s*-\s*dev\s*\r?\n\s*-\s*staging\s*\r?\n\s*-\s*prod' -Description 'workflow_dispatch environment options dev/staging/prod'
Assert-FileContains -RelativePath '.github/workflows/phase10-deploy-orchestrator.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in deploy orchestrator'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in reusable deploy workflow'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in runtime smoke workflow'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in transport smoke workflow'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in payment matrix workflow'

Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern '\$envSuffix = if \(\$Environment -eq ''staging''\) \{ ''stg'' \} else \{ \$Environment \}' -Description 'runtime smoke script staging normalization'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern 'Gateway backend route contract' -Description 'runtime smoke includes gateway backend route validation'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern 'ACA HTTPS FQDN target' -Description 'runtime smoke validates ACA HTTPS FQDN-style backend routes'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-transport-smoke.ps1' -RegexPattern '\$resourceSuffix = if \(\$Environment -eq ''staging''\) \{ ''stg'' \} else \{ \$Environment \}' -Description 'transport smoke script staging normalization'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern '\[ValidateSet\(''dev'', ''staging'', ''stg'', ''prod''\)\]' -Description 'Azure payment verifier accepts staging and stg aliases'
Assert-FileContains -RelativePath 'scripts/set-tenant-payment-provider.ps1' -RegexPattern '\[ValidateSet\(''dev'', ''staging'', ''stg'', ''prod''\)\]' -Description 'tenant provider setter accepts staging and stg aliases'

Write-Host ''
Write-Host '----------------------------------------' -ForegroundColor Cyan
Write-Host ('Passes: {0}' -f $script:Passes.Count) -ForegroundColor Green
Write-Host ('Failures: {0}' -f $script:Failures.Count) -ForegroundColor $(if ($script:Failures.Count -eq 0) { 'Green' } else { 'Red' })

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Contract failures:' -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host ''
Write-Host 'Phase 10 environment contract is valid.' -ForegroundColor Green
