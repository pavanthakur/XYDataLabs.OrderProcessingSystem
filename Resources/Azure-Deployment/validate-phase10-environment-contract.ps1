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

function Assert-RuntimeTargetValue {
    param(
        [string] $TargetKey,
        [string] $PropertyName,
        [AllowNull()][object] $ExpectedValue
    )

    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
    $target = $catalog.targets | Where-Object { $_.key -eq $TargetKey } | Select-Object -First 1
    $actualValue = if ($null -eq $target) { $null } else { $target.$PropertyName }
    Assert-Condition `
        -Condition (($null -eq $ExpectedValue -and $null -eq $actualValue) -or ($null -ne $ExpectedValue -and $actualValue -eq $ExpectedValue)) `
        -PassMessage "Runtime target '$TargetKey' -> '$PropertyName' has the approved value" `
        -FailMessage "Runtime target '$TargetKey' -> '$PropertyName' does not match the approved environment contract"
}

function Assert-RuntimeTargetFieldsDistinct {
    param(
        [string] $TargetKey,
        [string] $FirstPropertyName,
        [string] $SecondPropertyName
    )

    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
    $matches = @($catalog.targets | Where-Object { $_.key -eq $TargetKey })
    $first = if ($matches.Count -eq 1) { [string]$matches[0].$FirstPropertyName } else { '' }
    $second = if ($matches.Count -eq 1) { [string]$matches[0].$SecondPropertyName } else { '' }
    Assert-Condition `
        -Condition ($matches.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($first) -and -not [string]::IsNullOrWhiteSpace($second) -and -not [string]::Equals($first, $second, [StringComparison]::OrdinalIgnoreCase)) `
        -PassMessage "Runtime target '$TargetKey' keeps '$FirstPropertyName' distinct from '$SecondPropertyName'" `
        -FailMessage "Runtime target '$TargetKey' must define distinct non-empty '$FirstPropertyName' and '$SecondPropertyName' values"
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
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-dev.json' -ParameterName 'functionsHostStorageSkuName' -ExpectedValue 'Standard_LRS'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'functionsHostStorageSkuName' -ExpectedValue 'Standard_LRS'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-prod.json' -ParameterName 'functionsHostStorageSkuName' -ExpectedValue 'Standard_GRS'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-dev.json' -ParameterName 'replayRequestQueueName' -ExpectedValue 'dlq-replay-requests-dev'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'replayRequestQueueName' -ExpectedValue 'dlq-replay-requests-stg'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-prod.json' -ParameterName 'replayRequestQueueName' -ExpectedValue 'dlq-replay-requests-prod'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-dev.json' -ParameterName 'replayDrillRequestQueueName' -ExpectedValue 'dlq-replay-drill-requests-dev'
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-staging.json' -ParameterName 'replayDrillRequestQueueName' -ExpectedValue ''
Assert-ParameterValue -RelativePath 'infra/parameters/phase10-prod.json' -ParameterName 'replayDrillRequestQueueName' -ExpectedValue ''
Assert-RuntimeTargetValue -TargetKey 'azure-dev' -PropertyName 'azureOrderEventsTopicName' -ExpectedValue 'order-events-dev'
Assert-RuntimeTargetValue -TargetKey 'azure-stg' -PropertyName 'azureOrderEventsTopicName' -ExpectedValue 'order-events-staging'
Assert-RuntimeTargetValue -TargetKey 'azure-prod' -PropertyName 'azureOrderEventsTopicName' -ExpectedValue 'order-events-prod'
Assert-RuntimeTargetValue -TargetKey 'azure-dev' -PropertyName 'azureServiceBusFullyQualifiedNamespace' -ExpectedValue 'sb-orderprocessing-dev.servicebus.windows.net'
Assert-RuntimeTargetValue -TargetKey 'azure-stg' -PropertyName 'azureServiceBusFullyQualifiedNamespace' -ExpectedValue 'sb-orderprocessing-stg.servicebus.windows.net'
Assert-RuntimeTargetValue -TargetKey 'azure-prod' -PropertyName 'azureServiceBusFullyQualifiedNamespace' -ExpectedValue 'sb-orderprocessing-prod.servicebus.windows.net'
Assert-RuntimeTargetValue -TargetKey 'azure-dev' -PropertyName 'azureReplayDrillRequestQueueName' -ExpectedValue 'dlq-replay-drill-requests-dev'
Assert-RuntimeTargetValue -TargetKey 'azure-stg' -PropertyName 'azureReplayDrillRequestQueueName' -ExpectedValue $null
Assert-RuntimeTargetValue -TargetKey 'azure-prod' -PropertyName 'azureReplayDrillRequestQueueName' -ExpectedValue $null
Assert-RuntimeTargetFieldsDistinct -TargetKey 'azure-dev' -FirstPropertyName 'azureReplayDrillRequestQueueName' -SecondPropertyName 'azureReplayRequestQueueName'
$devParameterSet = Get-Content -LiteralPath (Join-Path $repoRoot 'infra/parameters/phase10-dev.json') -Raw | ConvertFrom-Json
$normalReplayQueue = [string]$devParameterSet.parameters.replayRequestQueueName.value
$drillReplayQueue = [string]$devParameterSet.parameters.replayDrillRequestQueueName.value
Assert-Condition `
    -Condition (-not [string]::IsNullOrWhiteSpace($normalReplayQueue) -and -not [string]::IsNullOrWhiteSpace($drillReplayQueue) -and -not [string]::Equals($normalReplayQueue, $drillReplayQueue, [StringComparison]::OrdinalIgnoreCase)) `
    -PassMessage 'Azure dev parameter file keeps the isolated replay queue distinct from the normal Function queue' `
    -FailMessage 'Azure dev replay drill queue must be distinct from the normal Function queue'

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
Assert-FileContains -RelativePath 'infra/modules/functions-host-storage.bicep' -RegexPattern "resource hostStorage 'Microsoft\.Storage/storageAccounts@[\s\S]*?kind: 'StorageV2'[\s\S]*?allowBlobPublicAccess: false[\s\S]*?allowSharedKeyAccess: false[\s\S]*?minimumTlsVersion: 'TLS1_2'[\s\S]*?supportsHttpsTrafficOnly: true" -Description 'Functions host uses a dedicated hardened StorageV2 account with shared-key and public-blob access disabled'
Assert-FileContains -RelativePath 'infra/modules/functions-host-storage.bicep' -RegexPattern "resource hostStorageIdentity 'Microsoft\.ManagedIdentity/userAssignedIdentities@" -Description 'Functions host storage has a dedicated user-assigned identity'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Grant exact Functions host Storage role using bootstrap identity[\s\S]*?az role assignment create[\s\S]*?--role "\$ROLE_ID"[\s\S]*?--scope "\$STORAGE_ACCOUNT_ID"[\s\S]*?Storage Blob Data Owner assignment could not be verified at exact resource scope' -Description 'deployment bootstrap grants and verifies the host-storage role only at the dedicated account scope'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'AzureWebJobsStorage__accountName'[\s\S]*?value: hostStorage\.name[\s\S]*?name: 'AzureWebJobsStorage__credential'[\s\S]*?value: 'managedidentity'[\s\S]*?name: 'AzureWebJobsStorage__clientId'[\s\S]*?value: hostStorageIdentity\.properties\.clientId" -Description 'Functions host storage uses identity-based account-name configuration, not a storage key'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "var operationsDatabaseConnectionString = '[^']*Authentication=Active Directory Managed Identity;[^']*'" -Description 'Functions SQL connection uses managed identity without SQL administrator credentials'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'ConnectionStrings__OrderProcessingSystemDbConnection'[\s\S]*?value: operationsDatabaseConnectionString" -Description 'Functions startup receives the operations database connection string'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern "var sqlConnectionString = deploySql \? '[^']*Authentication=Active Directory Managed Identity;[^']*' : ''" -Description 'Container Apps SQL runtime uses managed identity instead of the SQL administrator credential'
Assert-FileNotContains -RelativePath 'Resources/Azure-Deployment/open-local-sql-firewall.ps1' -RegexPattern '\$sqlPwd|Password\s*:\s*\$' -Description 'local SQL firewall helper never prints the Key Vault SQL administrator password'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'Phase10DlqTopicName'[\s\S]*?value: deadLetterTopicName[\s\S]*?name: 'Phase10DlqIntakeSubscriptionName'[\s\S]*?value: deadLetterSubscriptionName[\s\S]*?name: 'Phase10ReplayRequestQueueName'[\s\S]*?value: replayRequestQueueName" -Description 'Functions trigger settings match the IaC-managed DLQ topic, subscription, and replay queue'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "name: 'ServiceBus__ReplayRequestQueueName'[\s\S]*?value: replayRequestQueueName" -Description 'Functions application replay publisher options match the trigger queue'
Assert-FileContains -RelativePath 'infra/modules/servicebus.bicep' -RegexPattern "resource replayRequestQueue 'Microsoft\.ServiceBus/namespaces/queues@[\s\S]*?name: replayRequestQueueName" -Description 'Service Bus IaC creates the approved Functions replay request queue'
Assert-FileContains -RelativePath 'infra/modules/servicebus.bicep' -RegexPattern "resource replayDrillRequestQueue 'Microsoft\.ServiceBus/namespaces/queues@[\s\S]*?if \(environment == 'dev' && !empty\(replayDrillRequestQueueName\)\)[\s\S]*?name: replayDrillRequestQueueName" -Description 'isolated replay drill queue is created only for Azure dev'
Assert-FileContains -RelativePath 'infra/modules/servicebus.bicep' -RegexPattern "replayDrillReceiverRoleAssignment 'Microsoft\.Authorization/roleAssignments@[\s\S]*?scope: replayDrillRequestQueue[\s\S]*?serviceBusDataReceiverRoleDefinitionId" -Description 'optional drill receiver RBAC is scoped to the isolated queue'
Assert-FileContains -RelativePath 'infra/modules/servicebus.bicep' -RegexPattern "replayDrillBusinessTopicSenderRoleAssignment 'Microsoft\.Authorization/roleAssignments@[\s\S]*?scope: orderTopic[\s\S]*?serviceBusDataSenderRoleDefinitionId" -Description 'optional drill sender RBAC is scoped to the business topic'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var ordersEnv = concat\(publisherEnv,[\s\S]*?replayPublisherEnabledEnv\)" -Description 'Orders is the sole Container App that runs the replay approval publisher'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var inventoryEnv = concat\(publisherEnv,[\s\S]*?replayPublisherDisabledEnv\)[\s\S]*?var notificationsEnv = concat\(publisherEnv,[\s\S]*?replayPublisherDisabledEnv\)" -Description 'Inventory and Notifications do not compete to publish replay approvals'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'payments'[\s\S]*?env: concat\(runtimeCommonEnv, publisherEnv, replayPublisherDisabledEnv\)" -Description 'Payments does not compete to publish replay approvals'
Assert-FileNotContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "var publisherEnv = \[[\s\S]*?name: 'ServiceBus__ReplayRequestId'" -Description 'normal runtime configuration does not pin the publisher to a drill request'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern "replayDrillRequestQueueName: replayDrillRequestQueueName[\s\S]*?replayDrillRunnerPrincipalObjectId: replayDrillRunnerPrincipalObjectId[\s\S]*?output replayDrillRequestQueueName string = serviceBus\.outputs\.replayDrillRequestQueueName" -Description 'top-level IaC passes drill queue/RBAC inputs and reports the queue output'
Assert-FileNotContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern 'replayDrillRequestQueueName|ReplayDrill' -Description 'deployed Functions trigger remains on the normal replay queue'
Assert-FileNotContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern 'ServiceBus__ReplayRequestId' -Description 'normal deployment does not enable targeted replay-drill routing'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "name: 'ServiceBus__ReplayRequestQueueName'[\s\S]*?value: replayRequestQueueName" -Description 'Container App replay publisher receives the same approved queue name'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern "replayRequestQueueName: serviceBus\.outputs\.replayRequestQueueName[\s\S]*?output replayRequestQueueName string = serviceBus\.outputs\.replayRequestQueueName" -Description 'top-level IaC passes and reports the replay queue name from its Service Bus owner module'
Assert-FileContains -RelativePath 'scripts/phase10-azure-replay-drill-preflight.ps1' -RegexPattern "ValidateSet\('dev'\)[\s\S]*?function Get-ReplayDrillRuntimeChecks[\s\S]*?ServiceBus__ReplayEnabled[\s\S]*?ServiceBus__ReplayRequestQueueName[\s\S]*?ServiceBus__ReplayRequestId" -Description 'Azure replay-drill preflight checks dev-only publisher state and exact request scoping'
Assert-FileNotContains -RelativePath 'scripts/phase10-azure-replay-drill-preflight.ps1' -RegexPattern 'az\s+(containerapp\s+update|role\s+assignment\s+create|servicebus\s+(queue\s+create|namespace\s+create))' -Description 'Azure replay-drill preflight is read-only and cannot deploy or assign roles'
Assert-FileContains -RelativePath 'scripts/phase10-azure-replay-drill-config.ps1' -RegexPattern 'ValidateSet\(''Pause'', ''Route'', ''Restore'', ''RestoreSafe''\)[\s\S]*?MUTATE AZURE DEV REPLAY SETTINGS[\s\S]*?if \(-not \$Execute\)[\s\S]*?Read-only plan only[\s\S]*?ShouldProcess' -Description 'Azure replay config controller is read-only by default and requires explicit confirmation for writes'
Assert-FileContains -RelativePath 'scripts/phase10-azure-replay-drill-config.ps1' -RegexPattern 'preflight\.status -ne .PASS.[\s\S]*?Replay routing requires a fully verified paused manifest[\s\S]*?recovery-required' -Description 'replay configuration transitions require a passing preflight, verified pause, and recovery manifest'
Assert-FileContains -RelativePath 'scripts/phase10-azure-replay-drill-config.ps1' -RegexPattern 'pendingReplayRequestCount -ne 0[\s\S]*?RestoreSafe' -Description 'normal restore requires evidence that the selected request checkpointed and no requests remain pending'
Assert-FileNotContains -RelativePath 'scripts/phase10-azure-replay-drill-config.ps1' -RegexPattern 'az\s+(role\s+assignment\s+create|servicebus\s+(queue\s+create|namespace\s+create)|containerapp\s+revision\s+copy)' -Description 'replay config controller cannot create roles/resources or copy unreviewed images'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID:\s*\$\{\{\s*vars\.PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID\s*\}\}[\s\S]*?valid only as a GUID in the dev GitHub Environment[\s\S]*?replayDrillRunnerPrincipalObjectId="\$REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID"' -Description 'optional replay-drill runner RBAC identity is sourced from the environment variable, validated as dev-only, and passed to deployment'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'name: What-If \(subscription scope\)[\s\S]*?REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID:\s*\$\{\{\s*vars\.PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID\s*\}\}[\s\S]*?replayDrillRunnerPrincipalObjectId="\$REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID"' -Description 'what-if previews the same optional replay-drill runner grant as deployment'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(replayDrillRunnerPrincipalObjectId="\$REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID"[^\r\n]*\r?\n\s*--parameters replayDrillRunnerPrincipalType=User[\s\S]*?){2}' -Description 'what-if and deployment explicitly restrict the drill runner to the named-user principal type'
Assert-FileContains -RelativePath 'infra/modules/functions.bicep' -RegexPattern "type: 'SystemAssigned, UserAssigned'[\s\S]*?userAssignedIdentities:[\s\S]*?hostStorageIdentity\.id" -Description 'Function App attaches the dedicated storage identity'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Grant exact Functions host Storage role using bootstrap identity[\s\S]*?Restart Functions host after storage access is granted[\s\S]*?az functionapp restart' -Description 'Functions host is restarted after the bootstrap role grant is verified'
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
Assert-FileContains -RelativePath '.github/workflows/phase10-deploy-orchestrator.yml' -RegexPattern '(?s)deploySql:[\s\S]*?default:\s*false[\s\S]*?deployRedis:[\s\S]*?default:\s*false[\s\S]*?deploySql:\s*\$\{\{ inputs\.deploySql \}\}[\s\S]*?deployRedis:\s*\$\{\{ inputs\.deployRedis \}\}' -Description 'orchestrator defaults SQL/Redis updates off and forwards explicit selection'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(?s)deploySql:[\s\S]*?default:\s*false[\s\S]*?deployRedis:[\s\S]*?default:\s*false' -Description 'reusable deployment preserves SQL credentials and Redis unless explicitly selected'
Assert-FileContains -RelativePath 'scripts/phase10-deployment-identity.mjs' -RegexPattern 'deploySql[\s\S]*?deployRedis[\s\S]*?sqlEntraAdminConfigurationSha256' -Description 'reviewed deployment identity binds SQL/Redis selection and hashes the Entra SQL administrator configuration'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern '(?s)Refresh Azure CLI Login \(OIDC\) Before SQL Migrations.*?azure/login@v3.*?Run Azure SQL Migrations' -Description 'reusable deploy workflow refreshes the short-lived OIDC assertion before long-running SQL migration and Key Vault synchronization'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'steps\.outputs\.outputs\.payments' -Description 'reusable deploy workflow refreshes payments runtime alongside other backend services'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'SQL_ENTRA_ADMIN_OBJECT_ID[\s\S]*?SQL_ENTRA_ADMIN_LOGIN[\s\S]*?aadAdminObjectId=\$\{SQL_ENTRA_ADMIN_OBJECT_ID\}[\s\S]*?aadAdminLogin=\$\{SQL_ENTRA_ADMIN_LOGIN\}' -Description 'SQL deployment uses the explicit environment Entra administrator configuration'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'ensure-phase10-tenant-provider-secret-aliases\.ps1[\s\S]*?-GatewayBaseUrl ''\$\{\{ steps\.aliases\.outputs\.apiPublicUrl \}\}''[\s\S]*?verify-phase10-azure-tenant-topology\.ps1[\s\S]*?-GatewayBaseUrl ''\$\{\{ steps\.aliases\.outputs\.apiPublicUrl \}\}''' -Description 'post-deploy tenant discovery and alias sync consume the same resolved environment URL'
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
Assert-FileContains -RelativePath 'infra/modules/keyvault.phase10.bicep' -RegexPattern "DedicatedTenantConnectionStrings--\$\{tenantCode\}" -Description 'Phase 10 Key Vault module provisions dedicated tenant connection contracts from an ARM-evaluable non-secret key collection'
Assert-FileContains -RelativePath 'infra/modules/keyvault.phase10.bicep' -RegexPattern 'param\s+dedicatedTenantCodes\s+array[\s\S]*?for\s+tenantCode\s+in\s+dedicatedTenantCodes[\s\S]*?dedicatedTenantConnectionStrings\[tenantCode\]' -Description 'Phase 10 Key Vault secret values remain secure while What-If evaluates their resource loop'
Assert-FileContains -RelativePath 'infra/modules/keyvault.phase10.bicep' -RegexPattern "!empty\(deploymentPrincipalObjectId\)\s*\?\s*\[[\s\S]*?objectId:\s*deploymentPrincipalObjectId[\s\S]*?secrets:\s*\[\s*'get'\s*'list'\s*'set'\s*\]" -Description 'deployment principal receives scoped get/list/set access for deployment-owned secret synchronization'
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern 'dedicatedTenantConnectionStrings:\s*baselineDedicatedTenantConnectionStrings' -Description 'Phase 10 deployment supplies its sample dedicated tenant connection contract through IaC'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Diagnose Phase 10 SQL Identity Setup Failure' -Description 'reusable deploy workflow emits non-secret SQL identity failure diagnostics'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'Resolve-ContainerAppPrincipalId' -Description 'Phase 10 SQL identity setup resolves Container App identities directly'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'Resolve-FunctionAppPrincipalId' -Description 'Phase 10 SQL identity setup resolves Function App identity directly'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern '\[Guid\]\$GuidText[\s\S]*?ToByteArray\(\)[\s\S]*?WITH SID = \$managedIdentitySid, TYPE = E' -Description 'managed identity SQL principal SID uses SQL-compatible GUID byte ordering'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/setup-phase10-sql-managed-identities.ps1' -RegexPattern 'Managed identity database principal SID verification failed[\s\S]*?Managed identity database role verification failed' -Description 'managed identity database grant verifies the created SID and least-privilege roles'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'orderprocessing-pay-\$envSuffix' -Description 'runtime host verifier includes the payments container'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'orderprocessing-functions-\$envSuffix' -Description 'runtime host verifier includes the Functions host'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-runtime-hosts.ps1' -RegexPattern 'containerapp.*revision.*list' -Description 'runtime host verifier inspects latest ACA revisions'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'api/v1/Info/tenant-registry' -Description 'tenant topology verifier reads the runtime tenant registry endpoint'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'DedicatedTenantConnectionStrings--' -Description 'tenant topology verifier validates dedicated tenant Key Vault secrets dynamically'
Assert-FileContains -RelativePath 'scripts/verify-phase10-azure-tenant-topology.ps1' -RegexPattern 'PaymentProviders--' -Description 'tenant topology verifier validates tenant/provider secret contracts dynamically'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'verify-phase10-azure-tenant-topology\.ps1' -Description 'reusable deploy workflow verifies active tenant topology before endpoint smoke'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1[\s\S]*DeploymentPrincipalObjectId' -Description 'deploy workflow synchronizes provider secrets only after binding the scoped deployment principal contract'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/ensure-phase10-provider-runtime-secrets.ps1' -RegexPattern 'Wait-Phase10KeyVaultSecretWriteAccess' -Description 'provider secret synchronization fails fast when vault write authorization is not ready'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern "OpenPayRedirectUrl\s+'\$\{\{ steps\.aliases\.outputs\.apiPublicUrl \}\}/payment/callback'" -Description 'deployment synchronizes the stable public gateway callback URL for OpenPay redirects'
Assert-FileContains -RelativePath 'Resources/Azure-Deployment/ensure-phase10-tenant-provider-secret-aliases.ps1' -RegexPattern 'RequiredProviderCodes' -Description 'deployment synchronizes aliases for every validated payment matrix provider path'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern "RequiredProviderCodes @\('OpenPay', 'Razorpay'\)" -Description 'deploy workflow provisions and verifies both supported payment matrix provider paths'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Phase10__ProviderSecretSyncRun' -Description 'deploy workflow refreshes payment-aware runtime hosts after Key Vault provider secret synchronization'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'ensure-phase10-tenant-provider-secret-aliases\.ps1[\s\S]*Phase10__ProviderSecretSyncRun[\s\S]*verify-phase10-azure-tenant-topology\.ps1' -Description 'provider alias synchronization, runtime refresh, and topology verification execute in the required order'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'verify-phase10-azure-tenant-topology\.ps1' -Description 'runtime smoke workflow verifies active tenant topology before route smoke'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1|ensure-phase10-tenant-provider-secret-aliases\.ps1' -Description 'runtime smoke remains read-only and does not mutate Key Vault secrets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureResourceGroupName' -Description 'runtime target catalog records stable Azure resource group names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureGatewayContainerAppName' -Description 'runtime target catalog records stable gateway Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureOrdersContainerAppName' -Description 'runtime target catalog records stable orders Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azurePaymentsContainerAppName' -Description 'runtime target catalog records stable payments Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureInventoryContainerAppName' -Description 'runtime target catalog records stable inventory Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureNotificationsContainerAppName' -Description 'runtime target catalog records stable notifications Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureUiContainerAppName' -Description 'runtime target catalog records stable UI Container App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureManagedEnvironmentName' -Description 'runtime target catalog records the ACA environment name for live URL resolution'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureFunctionAppName' -Description 'runtime target catalog records stable Azure Functions App names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureSqlServerName' -Description 'runtime target catalog records stable Azure SQL server names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureOperationsDatabaseName' -Description 'runtime target catalog records the operations database paired with each Azure SQL server'
Assert-FileContains -RelativePath 'automation/src/contracts/runtime-target-catalog.ts' -RegexPattern 'azureOperationsDatabaseName\?: string' -Description 'runtime-target TypeScript contract includes the Azure operations database field'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureRedisName' -Description 'runtime target catalog records stable Azure Redis names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureKeyVaultName' -Description 'runtime target catalog records stable Key Vault names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureApplicationInsightsName' -Description 'runtime target catalog records stable Application Insights names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureServiceBusNamespaceName' -Description 'runtime target catalog records stable Service Bus namespace names for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureBrokerSuffix' -Description 'runtime target catalog records broker suffixes for Azure transport targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azureReplayRequestQueueName' -Description 'runtime target catalog records explicit replay queue names for Azure transport automation'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'publicUiBaseUrl' -Description 'runtime target catalog records explicit UI URL fields for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'publicApiBaseUrl' -Description 'runtime target catalog records explicit API URL fields for Azure targets'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'allowGeneratedAzureUrlFallback' -Description 'runtime target catalog records explicit generated URL fallback policy'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern '"publicUrlMode": "generated"' -Description 'dev target explicitly selects live generated URL resolution'
Assert-FileContains -RelativePath 'scripts/resolve-phase10-azure-generated-urls.mjs' -RegexPattern 'expectedUiOrigin !== uiOrigin' -Description 'generated dev URL resolver requires exact Entra origin agreement'
Assert-FileContains -RelativePath '.github/workflows/phase10-dev-hostname-bootstrap.yml' -RegexPattern 'main.phase10.dev-hostname-bootstrap.bicep' -Description 'dev hostname bootstrap uses dedicated additive template'
Assert-FileContains -RelativePath '.github/workflows/phase10-deploy-orchestrator.yml' -RegexPattern 'Verify generated Azure-dev origin matches Entra registration' -Description 'orchestrator verifies generated URL against Entra before deployment'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'https://staging\.orderprocessing\.xydatalabs\.com' -Description 'staging UI smoke target uses the stable custom domain'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'https://staging\.orderprocessing-api\.xydatalabs\.com' -Description 'staging API smoke target uses the stable custom domain'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'https://orderprocessing\.xydatalabs\.com' -Description 'prod UI smoke target uses the stable custom domain'
Assert-FileContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'https://orderprocessing-api\.xydatalabs\.com' -Description 'prod API smoke target uses the stable custom domain'
Assert-FileNotContains -RelativePath 'automation/config/runtime-targets.json' -RegexPattern 'azurewebsites\.net|azurecontainerapps\.io' -Description 'runtime target catalog does not store generated Azure/App Service hostnames as primary automation URLs'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.dev.json' -RegexPattern 'https://dev\.orderprocessing-api\.xydatalabs\.com' -Description 'legacy dev App Service metadata remains unchanged'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.dev.json' -RegexPattern 'https://dev\.orderprocessing\.xydatalabs\.com' -Description 'legacy dev App Service UI metadata remains unchanged'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.stg.json' -RegexPattern 'https://staging\.orderprocessing-api\.xydatalabs\.com' -Description 'staging shared settings API URL uses stable custom domain'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.stg.json' -RegexPattern 'https://staging\.orderprocessing\.xydatalabs\.com' -Description 'staging shared settings UI URL uses stable custom domain'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.prod.json' -RegexPattern 'https://orderprocessing-api\.xydatalabs\.com' -Description 'prod shared settings API URL uses stable custom domain'
Assert-FileContains -RelativePath 'Resources/Configuration/sharedsettings.prod.json' -RegexPattern 'https://orderprocessing\.xydatalabs\.com' -Description 'prod shared settings UI URL uses stable custom domain'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'read_target_field azureFunctionAppName' -Description 'Azure runtime smoke resolves Functions App name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'read_target_field azureGatewayContainerAppName' -Description 'Azure runtime smoke resolves gateway Container App name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'resolve-phase10-azure-generated-urls\.mjs' -Description 'Azure runtime smoke resolves and checks live dev Gateway/UI URLs'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'read_target_field publicUiBaseUrl' -Description 'Azure runtime smoke retains stable URL path for staging/prod'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'GatewayContainerAppName' -Description 'Azure runtime smoke passes runtime-target gateway name into runtime host verifier'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'UiContainerAppName' -Description 'Azure runtime smoke passes runtime-target UI name into runtime host verifier'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-runtime-smoke.yml' -RegexPattern 'RG_NAME="rg-orderprocessing|GATEWAY_APP="orderprocessing-gate|FUNCTION_APP="orderprocessing-functions' -Description 'Azure runtime smoke workflow does not hardcode Azure resource names'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'read_target_field azureServiceBusNamespaceName' -Description 'Azure transport smoke resolves Service Bus namespace from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'read_target_field azureKeyVaultName' -Description 'Azure transport smoke resolves Key Vault name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'read_target_field azureSqlServerName' -Description 'Azure transport smoke resolves SQL server name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'read_target_field azureBrokerSuffix' -Description 'Azure transport smoke resolves broker suffix from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'read_target_field azureReplayRequestQueueName' -Description 'Azure transport smoke resolves the Functions replay queue from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'az servicebus queue show' -Description 'Azure transport smoke verifies the Functions replay request queue exists'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-transport-smoke.yml' -RegexPattern 'RG_NAME="rg-orderprocessing|SB_NAMESPACE="sb-orderprocessing|GATEWAY_APP="orderprocessing-gate' -Description 'Azure transport smoke workflow does not hardcode Azure transport resource names'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'read_target_field azureResourceGroupName' -Description 'Azure payment matrix resolves resource group from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'read_target_field azureApplicationInsightsName' -Description 'Azure payment matrix resolves Application Insights name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'read_target_field azureKeyVaultName' -Description 'Azure payment matrix resolves Key Vault name from runtime-targets.json'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'XYDATALABS_AZURE_APP_INSIGHTS_NAME' -Description 'Azure payment verifier receives runtime-target Application Insights name'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'XYDATALABS_AZURE_KEY_VAULT_NAME' -Description 'Azure payment verifier receives runtime-target Key Vault name'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'RG_NAME="rg-orderprocessing' -Description 'Azure payment matrix workflow does not hardcode Azure resource group names'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'GATEWAY_APP="orderprocessing-gate' -Description 'Azure payment matrix workflow does not hardcode gateway Container App names'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'UI_APP="orderprocessing-ui' -Description 'Azure payment matrix workflow does not hardcode UI Container App names'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'automation/config/runtime-targets.json' -Description 'Azure payment matrix reads runtime target URLs from the checked-in runtime target catalog'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'resolve-phase10-azure-generated-urls\.mjs' -Description 'Azure payment matrix resolves and checks live dev Gateway/UI URLs'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'read_target_field publicUiBaseUrl' -Description 'Azure payment matrix retains stable URL path for staging/prod'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'azureGeneratedGatewayUrl' -Description 'Azure payment matrix records the live generated Gateway URL'
Assert-FileContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'GatewayBaseUrl' -Description 'Azure payment matrix passes the runtime target gateway URL into topology verification'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern 'ensure-phase10-provider-runtime-secrets\.ps1|ensure-phase10-tenant-provider-secret-aliases\.ps1' -Description 'Azure payment matrix preflight remains read-only and does not mutate Key Vault secrets'
Assert-FileNotContains -RelativePath '.github/workflows/phase10-azure-payment-matrix.yml' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'Azure payment matrix workflow does not hardcode sample tenant codes'
Assert-FileNotContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'Azure payment verifier does not hardcode sample tenant codes in active execution logic'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern 'XYDATALABS_AZURE_RESOURCE_GROUP_NAME' -Description 'Azure payment verifier can consume runtime-target resource group overrides'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern 'XYDATALABS_AZURE_APP_INSIGHTS_NAME' -Description 'Azure payment verifier can consume runtime-target Application Insights overrides'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern 'XYDATALABS_AZURE_KEY_VAULT_NAME' -Description 'Azure payment verifier can consume runtime-target Key Vault overrides'
Assert-FileContains -RelativePath 'scripts/verify-payment-run-azure.ps1' -RegexPattern 'XYDATALABS_AZURE_SQL_SERVER_NAME' -Description 'Azure payment verifier can consume runtime-target SQL server overrides'
Assert-FileNotContains -RelativePath 'scripts/verify-payment-run-physical.ps1' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'physical payment verifier does not hardcode sample tenant codes in active execution logic'
Assert-FileNotContains -RelativePath 'automation/src/catalog/api-tenant-execution-catalog.ts' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'automation tenant catalog does not infer topology from sample tenant codes'
Assert-FileNotContains -RelativePath 'automation/src/orchestrator/payment-automation-executor.ts' -RegexPattern '\bTenantA\b|\bTenantB\b|\bTenantC\b' -Description 'payment automation executor does not hardcode sample tenant codes'
Assert-FileNotContains -RelativePath 'scripts/run-phase10-local-container-stack-end-to-end.ps1' -RegexPattern '\bTenant[ABC]\b(?!-routing-regression)' -Description 'local Phase 10 end-to-end wrapper does not pass hardcoded sample tenant lists (the tenantc-routing-regression step identifier is exempt)'

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
Assert-FileContains -RelativePath 'infra/main.phase10.bicep' -RegexPattern 'param applicationIdentity object' -Description 'Phase 10 requires a validated identity deployment parameter'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern "IdentityProvider__Mode[\s\S]*Entra" -Description 'Azure APIs explicitly select Entra instead of local identity'
Assert-FileContains -RelativePath 'infra/modules/containerapps.bicep' -RegexPattern 'PUBLIC_IDENTITY_SCOPES' -Description 'UI receives environment-specific public API scopes at runtime'
Assert-FileContains -RelativePath '.github/workflows/infra-deploy.yml' -RegexPattern 'Validate Entra provisioning before cloud writes' -Description 'deployment validates identity before cloud mutations'
Assert-FileContains -RelativePath 'frontend/apps/web/server.mjs' -RegexPattern 'runtime-config.json' -Description 'promotable UI image publishes public runtime configuration'
Assert-FileNotContains -RelativePath 'frontend/apps/web/Dockerfile' -RegexPattern 'ARG VITE_KEYCLOAK|ENV VITE_KEYCLOAK' -Description 'UI image does not bake local identity authority into cloud images'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.API/Program.cs' -RegexPattern 'UseMiddleware<TenantClaimConsistencyMiddleware>' -Description 'non-Docker API enforces the shared tenant authorization policy'
Assert-FileContains -RelativePath 'XYDataLabs.OrderProcessingSystem.Gateway/Program.cs' -RegexPattern 'app.UseAuthorization\(\)' -Description 'gateway explicitly orders authentication and authorization middleware'

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
