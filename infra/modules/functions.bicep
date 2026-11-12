targetScope = 'resourceGroup'

@description('Azure region for Functions resources')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Azure resource suffix override used for environment-scoped resource names')
param resourceSuffix string = ''

@description('Base application name')
param baseName string = 'orderprocessing'

@description('App Service Plan SKU used for the Function App host')
param sku string = 'B1'

@description('Storage redundancy SKU for dedicated Functions host storage')
param hostStorageSkuName string = 'Standard_LRS'

@description('Application Insights connection string')
param appInsightsConnectionString string = ''

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string = ''

@description('Key Vault URI for runtime secret lookup')
param keyVaultUri string = ''

@description('Service Bus topic name')
param serviceBusTopicName string = 'order-events'

@description('Service Bus connection string for the Phase 10 transport slice')
param serviceBusConnectionString string = ''

@description('Dead-letter topic name')
param deadLetterTopicName string = 'order-events-dlq'

@description('Dead-letter replay subscription name')
param deadLetterSubscriptionName string = 'dlq-replay'

@description('Maximum delivery count before dead-lettering')
param maxDeliveryCount int = 10

@description('Message TTL in ISO 8601 duration format')
param messageTtl string = 'P7D'

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
var aspNetCoreEnvironment = environment == 'prod'
  ? 'Production'
  : environment == 'staging'
    ? 'Staging'
    : 'Development'
var functionAppName = '${baseName}-functions-${effectiveResourceSuffix}'
// Storage account names are globally unique, deterministic, and remain portable
// across environments without embedding generated hostnames in runtime config.
var storageAccountName = '${take(replace(toLower(baseName), '-', ''), 8)}${take(replace(toLower(effectiveResourceSuffix), '-', ''), 3)}${uniqueString(resourceGroup().id)}'
var hostStorageIdentityName = '${baseName}-functions-storage-${effectiveResourceSuffix}'
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: hostStorageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
  tags: {
    env: environment
    app: baseName
    component: 'functions-host-storage'
  }
}

resource hostStorageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: hostStorageIdentityName
  location: location
  tags: {
    env: environment
    app: baseName
    component: 'functions-host-storage-identity'
  }
}

resource hostStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostStorageIdentity.id, storageBlobDataOwnerRoleId)
  scope: hostStorage
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: hostStorageIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${baseName}-${effectiveResourceSuffix}'
  location: location
  sku: {
    name: sku
    tier: sku == 'F1' ? 'Free' : sku
  }
  properties: {
    reserved: false
  }
  tags: {
    env: environment
    app: baseName
    component: 'functions'
  }
}

var appSettings = [
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'dotnet-isolated'
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
  {
    name: 'AzureWebJobsStorage__accountName'
    value: hostStorage.name
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'AzureWebJobsStorage__clientId'
    value: hostStorageIdentity.properties.clientId
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: appInsightsInstrumentationKey
  }
  {
    name: 'KeyVault__Uri'
    value: keyVaultUri
  }
  {
    name: 'ORDERPROCESSING_EXPECTED_ENVIRONMENT'
    value: environment
  }
  {
    name: 'ASPNETCORE_ENVIRONMENT'
    value: aspNetCoreEnvironment
  }
  {
    name: 'DOTNET_ENVIRONMENT'
    value: aspNetCoreEnvironment
  }
  {
    name: 'ServiceBus__Enabled'
    value: 'true'
  }
  {
    name: 'ServiceBus__TopicName'
    value: serviceBusTopicName
  }
  {
    name: 'ServiceBus__ConnectionString'
    value: serviceBusConnectionString
  }
  {
    name: 'ServiceBusConnection'
    value: serviceBusConnectionString
  }
  {
    name: 'ServiceBus__DeadLetterTopicName'
    value: deadLetterTopicName
  }
  {
    name: 'ServiceBus__DeadLetterSubscriptionName'
    value: deadLetterSubscriptionName
  }
  {
    name: 'ServiceBus__MaxDeliveryCount'
    value: string(maxDeliveryCount)
  }
  {
    name: 'ServiceBus__MessageTtl'
    value: messageTtl
  }
  {
    name: 'ServiceBus__ReplayEnabled'
    value: 'true'
  }
]

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${hostStorageIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      appSettings: appSettings
    }
  }
  dependsOn: [
    hostStorageBlobDataOwner
  ]
}

output functionAppName string = app.name
output functionPrincipalId string = app.identity.principalId
output hostStorageAccountName string = hostStorage.name
output hostStorageIdentityName string = hostStorageIdentity.name
output hostStorageIdentityClientId string = hostStorageIdentity.properties.clientId
