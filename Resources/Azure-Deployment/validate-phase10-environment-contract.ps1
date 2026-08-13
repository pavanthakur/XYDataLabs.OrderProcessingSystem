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

function Assert-FileNotContains {
    param(
        [string] $RelativePath,
        [string] $RegexPattern,
        [string] $Description
    )

    $content = Get-FileText -RelativePath $RelativePath
    Assert-Condition `
        -Condition (-not ($content -match $RegexPattern)) `
        -PassMessage "$RelativePath -> $Description" `
        -FailMessage "$RelativePath violates expected contract: $Description"
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
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var aspNetCoreEnvironment = environment == 'prod'[\s\S]*'Staging'[\s\S]*'Development'" -Description 'container apps normalize dev/staging/prod to ASP.NET environment names'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'ORDERPROCESSING_EXPECTED_ENVIRONMENT'[\s\S]*value: environment" -Description 'container apps publish expected deployment environment marker'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'ORDERPROCESSING_AZURE_HOST'[\s\S]*value: 'true'" -Description 'container apps explicitly identify Azure hosting for Key Vault loading'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'ASPNETCORE_ENVIRONMENT'[\s\S]*value: aspNetCoreEnvironment" -Description 'container apps set ASPNETCORE_ENVIRONMENT explicitly'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'DOTNET_ENVIRONMENT'[\s\S]*value: aspNetCoreEnvironment" -Description 'container apps set DOTNET_ENVIRONMENT explicitly'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "var aspNetCoreEnvironment = environment == 'prod'[\s\S]*'Staging'[\s\S]*'Development'" -Description 'functions normalize dev/staging/prod to ASP.NET environment names'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'ORDERPROCESSING_EXPECTED_ENVIRONMENT'[\s\S]*value: environment" -Description 'functions publish expected deployment environment marker'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'ASPNETCORE_ENVIRONMENT'[\s\S]*value: aspNetCoreEnvironment" -Description 'functions set ASPNETCORE_ENVIRONMENT explicitly'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'DOTNET_ENVIRONMENT'[\s\S]*value: aspNetCoreEnvironment" -Description 'functions set DOTNET_ENVIRONMENT explicitly'
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
Assert-FileContains -RelativePath '.github/workflows/build-phase10-images.yml' -RegexPattern 'repository:\s*orderprocessing-orders[\s\S]*dockerfile:\s*XYDataLabs\.OrderProcessingSystem\.Orders\.Host/Dockerfile' -Description 'orders phase10 image is built from Orders.Host Dockerfile'
Assert-FileContains -RelativePath '.github/workflows/build-phase10-images.yml' -RegexPattern 'repository:\s*orderprocessing-payments[\s\S]*dockerfile:\s*XYDataLabs\.OrderProcessingSystem\.Payments\.Host/Dockerfile' -Description 'payments phase10 image is built from Payments.Host Dockerfile'
Assert-FileContains -RelativePath '.github/workflows/build-phase10-images.yml' -RegexPattern 'repository:\s*orderprocessing-inventory[\s\S]*dockerfile:\s*XYDataLabs\.OrderProcessingSystem\.Inventory\.Host/Dockerfile' -Description 'inventory phase10 image is built from Inventory.Host Dockerfile'
Assert-FileContains -RelativePath '.github/workflows/build-phase10-images.yml' -RegexPattern 'repository:\s*orderprocessing-notifications[\s\S]*dockerfile:\s*XYDataLabs\.OrderProcessingSystem\.Notifications\.Host/Dockerfile' -Description 'notifications phase10 image is built from Notifications.Host Dockerfile'
Assert-FileContains -RelativePath '.github/workflows/phase10-deploy-orchestrator.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in deploy orchestrator'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in reusable deploy workflow'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'setup-phase10-sql-managed-identities\.ps1' -Description 'reusable deploy workflow grants SQL access to actual Phase 10 runtime identities'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(?s)Refresh Azure CLI Login \(OIDC\) Before SQL Migrations.*?azure/login@v3.*?Run Azure SQL Migrations' -Description 'reusable deploy workflow refreshes the short-lived OIDC assertion before long-running SQL migration and Key Vault synchronization'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'steps\.outputs\.outputs\.payments' -Description 'reusable deploy workflow refreshes payments runtime alongside other backend services'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'az functionapp restart' -Description 'reusable deploy workflow restarts the Function App after SQL setup'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'verify-phase10-azure-runtime-hosts\.ps1' -Description 'reusable deploy workflow verifies all runtime hosts before endpoint smoke'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in runtime smoke workflow'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'verify-phase10-azure-runtime-hosts\.ps1' -Description 'runtime smoke workflow verifies all runtime hosts from the Azure control plane'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'Orders Container App' -Description 'runtime smoke workflow context links include backend runtime hosts'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in transport smoke workflow'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern '(?s)\$\{\{\s*inputs\.environment\s*\}\}.*staging.*ENV_SUFFIX="stg"' -Description 'staging to stg normalization in payment matrix workflow'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'TenantTier\] = N''Dedicated''' -Description 'Phase 10 SQL identity setup discovers dedicated tenants from the tenant registry'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'DedicatedTenantConnectionStrings--' -Description 'Phase 10 SQL identity setup resolves dedicated tenant databases from Key Vault secrets'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/run-database-migrations.ps1' -RegexPattern "runtimeUsername\s*=\s*'tenantc_runtime'[\s\S]*?ALTER ROLE db_datareader ADD MEMBER[\s\S]*?ALTER ROLE db_datawriter ADD MEMBER" -Description 'TenantC runtime uses a dedicated contained user limited to reader/writer roles'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/run-database-migrations.ps1' -RegexPattern 'RandomNumberGenerator\]::Fill[\s\S]*?ALTER USER[\s\S]*?DedicatedTenantConnectionStrings--TenantC' -Description 'TenantC contained runtime password rotates into its Key Vault connection contract'
Assert-FileContains -RelativePath 'infra/modules/keyvault.phase10.bicep' -RegexPattern "DedicatedTenantConnectionStrings--\$\{dedicatedTenant\.key\}" -Description 'Phase 10 Key Vault module provisions dedicated tenant connection contracts from a keyed collection'
Assert-FileContains -RelativePath 'infra/modules/keyvault.phase10.bicep' -RegexPattern "!empty\(deploymentPrincipalObjectId\)\s*\?\s*\[[\s\S]*?objectId:\s*deploymentPrincipalObjectId[\s\S]*?secrets:\s*\[\s*'get'\s*'list'\s*'set'\s*\]" -Description 'deployment principal receives scoped get/list/set access for deployment-owned secret synchronization'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern 'dedicatedTenantConnectionStrings:\s*baselineDedicatedTenantConnectionStrings' -Description 'Phase 10 deployment supplies its sample dedicated tenant connection contract through IaC'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Diagnose Phase 10 SQL Identity Setup Failure' -Description 'reusable deploy workflow emits non-secret SQL identity failure diagnostics'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'Resolve-ContainerAppPrincipalId' -Description 'Phase 10 SQL identity setup resolves Container App identities directly'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'Resolve-FunctionAppPrincipalId' -Description 'Phase 10 SQL identity setup resolves Function App identity directly'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'orderprocessing-pay-\$envSuffix' -Description 'runtime host verifier includes the payments container'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'orderprocessing-functions-\$envSuffix' -Description 'runtime host verifier includes the Functions host'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'containerapp.*revision.*list' -Description 'runtime host verifier inspects latest ACA revisions'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'api/v1/Info/tenant-registry' -Description 'tenant topology verifier reads the runtime tenant registry endpoint'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'DedicatedTenantConnectionStrings--' -Description 'tenant topology verifier validates dedicated tenant Key Vault secrets dynamically'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'PaymentProviders--' -Description 'tenant topology verifier validates tenant/provider secret contracts dynamically'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'RequiredProviderCodes' -Description 'tenant topology verifier can validate provider override paths before matrix execution'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'verify-phase10-azure-tenant-topology\.ps1' -Description 'reusable deploy workflow verifies active tenant topology before endpoint smoke'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1[\s\S]*DeploymentPrincipalObjectId' -Description 'deploy workflow synchronizes provider secrets only after binding the scoped deployment principal contract'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/ensure-phase10-provider-runtime-secrets.ps1' -RegexPattern 'Wait-Phase10KeyVaultSecretWriteAccess' -Description 'provider secret synchronization fails fast when vault write authorization is not ready'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern "OpenPayRedirectUrl\s+'https://\$\{\{ steps\.outputs\.outputs\.gatewayFqdn \}\}/payment/callback'" -Description 'deployment synchronizes the public gateway callback URL for OpenPay redirects'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/ensure-phase10-tenant-provider-secret-aliases.ps1' -RegexPattern 'RequiredProviderCodes' -Description 'deployment synchronizes aliases for every validated payment matrix provider path'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern "RequiredProviderCodes @\('OpenPay', 'Razorpay'\)" -Description 'deploy workflow provisions and verifies both supported payment matrix provider paths'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Phase10__ProviderSecretSyncRun' -Description 'deploy workflow refreshes payment-aware runtime hosts after Key Vault provider secret synchronization'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'ensure-phase10-tenant-provider-secret-aliases\.ps1[\s\S]*Phase10__ProviderSecretSyncRun[\s\S]*verify-phase10-azure-tenant-topology\.ps1' -Description 'provider alias synchronization, runtime refresh, and topology verification execute in the required order'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'verify-phase10-azure-tenant-topology\.ps1' -Description 'runtime smoke workflow verifies active tenant topology before route smoke'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1|ensure-phase10-tenant-provider-secret-aliases\.ps1' -Description 'runtime smoke remains read-only and does not mutate Key Vault secrets'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'Verify tenant and provider matrix contract' -Description 'Azure payment matrix fails before browser execution when provider override aliases are not provisioned'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern "RequiredProviderCodes @\('OpenPay', 'Razorpay'\)" -Description 'Azure payment matrix preflight validates both supported provider paths for every active tenant'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1|ensure-phase10-tenant-provider-secret-aliases\.ps1' -Description 'Azure payment matrix preflight remains read-only and does not mutate Key Vault secrets'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'Azure payment matrix workflow does not hardcode sample tenant codes'
Assert-FileNotContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'Azure payment verifier does not hardcode sample tenant codes in active execution logic'
Assert-FileNotContains -RelativePath 'scripts/verify-payment-run-physical.ps1' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'physical payment verifier does not hardcode sample tenant codes in active execution logic'
Assert-FileNotContains -RelativePath 'automation/src/catalog/api-tenant-execution-catalog.ts' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'automation tenant catalog does not infer topology from sample tenant codes'
Assert-FileNotContains -RelativePath 'automation/src/orchestrator/payment-automation-executor.ts' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'payment automation executor does not hardcode sample tenant codes'
Assert-FileNotContains -RelativePath 'scripts/run-phase10-local-container-stack-end-to-end.ps1' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'local Phase 10 end-to-end wrapper does not pass hardcoded sample tenant lists'

Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern '\$envSuffix = if \(\$Environment -eq ''staging''\) \{ ''stg'' \} else \{ \$Environment \}' -Description 'runtime smoke script staging normalization'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern 'Gateway backend route contract' -Description 'runtime smoke includes gateway backend route validation'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-runtime-smoke.ps1' -RegexPattern 'ACA HTTPS FQDN target' -Description 'runtime smoke validates ACA HTTPS FQDN-style backend routes'
Assert-FileContains -RelativePath 'scripts/run-phase10-azure-transport-smoke.ps1' -RegexPattern '\$resourceSuffix = if \(\$Environment -eq ''staging''\) \{ ''stg'' \} else \{ \$Environment \}' -Description 'transport smoke script staging normalization'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern '\[ValidateSet\(''dev'', ''staging'', ''stg'', ''prod''\)\]' -Description 'Azure payment verifier accepts staging and stg aliases'
Assert-FileContains -RelativePath 'scripts/set-tenant-payment-provider.ps1' -RegexPattern '\[ValidateSet\(''dev'', ''staging'', ''stg'', ''prod''\)\]' -Description 'tenant provider setter accepts staging and stg aliases'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.SharedKernel/SharedSettingsLoader.cs' -RegexPattern 'ORDERPROCESSING_EXPECTED_ENVIRONMENT' -Description 'shared settings loader validates expected deployment environment marker'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.SharedKernel/SharedSettingsLoader.cs' -RegexPattern 'ORDERPROCESSING_AZURE_HOST[\s\S]*KeyVault__Uri' -Description 'shared settings loader detects Container Apps and consumes the exact Key Vault URI'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.SharedKernel/SharedSettingsLoader.cs' -RegexPattern 'Runtime environment mismatch detected' -Description 'shared settings loader fails fast on ASPNETCORE/DOTNET environment disagreement'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.SharedKernel/SharedSettingsLoader.cs' -RegexPattern 'Environment contract violation detected' -Description 'shared settings loader fails fast on deployment/runtime environment mismatch'

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
