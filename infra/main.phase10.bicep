targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'centralindia'

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
param githubOwner string

@description('Service Bus topic for order-created transport')
param orderEventsTopicName string = 'order-events'

@description('Inventory subscription name')
param inventorySubscriptionName string = 'inventory-order-created'

@description('Notifications subscription name')
param notificationsSubscriptionName string = 'notifications-order-created'

@description('Dead-letter replay subscription name')
param deadLetterSubscriptionName string = 'dlq-replay'

@description('Maximum delivery count before dead-lettering')
param maxDeliveryCount int = 10

@description('Message TTL in ISO 8601 duration format')
param messageTtl string = 'P7D'

var rgName = 'rg-${baseName}-${environment}'
var keyVaultName = 'kv-${take(baseName, 15)}-${environment}'
var keyVaultUri = 'https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/'

resource appRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgName
  location: location
  tags: {
    env: environment
    app: baseName
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    orderEventsTopicName: orderEventsTopicName
    inventorySubscriptionName: inventorySubscriptionName
    notificationsSubscriptionName: notificationsSubscriptionName
    deadLetterSubscriptionName: deadLetterSubscriptionName
    maxDeliveryCount: maxDeliveryCount
    messageTtl: messageTtl
  }
}

var serviceBusConnectionString = serviceBus.outputs.transportAuthRuleConnectionString

module logAnalytics 'modules/loganalytics.phase10.bicep' = {
  name: 'loganalytics-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
  }
}

module insights 'modules/insights.phase10.bicep' = {
  name: 'insights-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    workspaceResourceId: logAnalytics.outputs.logAnalyticsWorkspaceId
  }
}

module identity 'modules/identity.phase10.bicep' = {
  name: 'identity-phase10-${environment}'
  scope: appRg
  params: {
    environment: environment
    baseName: baseName
    githubOwner: githubOwner
  }
}

module containerApps 'modules/containerapps.bicep' = {
  name: 'containerapps-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    githubOwner: githubOwner
    appInsightsConnectionString: insights.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: insights.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    keyVaultUri: keyVaultUri
    serviceBusTopicName: serviceBus.outputs.orderEventsTopic
    serviceBusConnectionString: serviceBusConnectionString
    inventorySubscriptionName: serviceBus.outputs.inventorySubscription
    notificationsSubscriptionName: serviceBus.outputs.notificationsSubscription
    deadLetterTopicName: serviceBus.outputs.deadLetterTopic
    deadLetterSubscriptionName: serviceBus.outputs.deadLetterSubscription
    maxDeliveryCount: maxDeliveryCount
    messageTtl: messageTtl
  }
}

module functions 'modules/functions.bicep' = {
  name: 'functions-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    sku: 'B1'
    appInsightsConnectionString: insights.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: insights.outputs.appInsightsInstrumentationKey
    keyVaultUri: keyVaultUri
    serviceBusTopicName: serviceBus.outputs.orderEventsTopic
    serviceBusConnectionString: serviceBusConnectionString
    deadLetterTopicName: serviceBus.outputs.deadLetterTopic
    deadLetterSubscriptionName: serviceBus.outputs.deadLetterSubscription
    maxDeliveryCount: maxDeliveryCount
    messageTtl: messageTtl
  }
}

module keyVault 'modules/keyvault.phase10.bicep' = {
  name: 'keyvault-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    gatewayPrincipalId: containerApps.outputs.gatewayPrincipalId
    ordersPrincipalId: containerApps.outputs.ordersPrincipalId
    inventoryPrincipalId: containerApps.outputs.inventoryPrincipalId
    notificationsPrincipalId: containerApps.outputs.notificationsPrincipalId
    functionsPrincipalId: functions.outputs.functionPrincipalId
  }
}

output resourceGroupName string = appRg.name
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output logAnalyticsWorkspaceName string = logAnalytics.outputs.logAnalyticsWorkspaceName
output managedEnvironmentId string = containerApps.outputs.managedEnvironmentId
output gatewayContainerAppName string = containerApps.outputs.gatewayContainerAppName
output ordersContainerAppName string = containerApps.outputs.ordersContainerAppName
output inventoryContainerAppName string = containerApps.outputs.inventoryContainerAppName
output notificationsContainerAppName string = containerApps.outputs.notificationsContainerAppName
output uiContainerAppName string = containerApps.outputs.uiContainerAppName
output functionAppName string = functions.outputs.functionAppName
output keyVaultName string = keyVault.outputs.keyVaultName
output appInsightsName string = insights.outputs.appInsightsName
output oidcClientId string = identity.outputs.clientId
