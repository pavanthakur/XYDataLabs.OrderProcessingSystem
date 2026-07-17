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

@description('Gateway container image reference')
param gatewayImage string

@description('Orders container image reference')
param ordersImage string

@description('Inventory container image reference')
param inventoryImage string

@description('Notifications container image reference')
param notificationsImage string

@description('UI container image reference')
param uiImage string

@description('Deploy Azure SQL for the Phase 10 parity slice')
param deploySql bool = false

@description('Deploy Azure Cache for Redis for the Phase 10 parity slice')
param deployRedis bool = false

@description('SQL Server admin username')
param sqlAdminUsername string = 'sqladmin'

@secure()
@description('SQL Server admin password')
param sqlAdminPassword string = ''

@description('Database service objective (Basic, S0, S1, etc)')
param databaseServiceObjective string = 'Basic'

@description('Redis SKU name')
param redisSkuName string = 'Basic'

@description('Redis SKU family')
param redisSkuFamily string = 'C'

@description('Redis SKU capacity')
param redisCapacity int = 0

@description('Platform ACR registry name used for the Phase 10 runtime image path')
param platformAcrName string = ''

@description('Platform ACR login server used for image pulls')
param platformAcrLoginServer string = ''

@description('Platform user-assigned managed identity resource id used by Container Apps to pull from ACR')
param platformAcrPullIdentityId string = ''

@description('ACR pull token username used by Container Apps when the deploy path does not own Azure RBAC grants')
param acrRegistryUsername string = ''

@secure()
@description('ACR pull token password used by Container Apps when the deploy path does not own Azure RBAC grants')
param acrRegistryPassword string = ''

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

module sql 'modules/sql.bicep' = if (deploySql) {
  name: 'sql-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
    databaseServiceObjective: databaseServiceObjective
  }
}

module redis 'modules/redis.phase10.bicep' = if (deployRedis) {
  name: 'redis-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    skuName: redisSkuName
    skuFamily: redisSkuFamily
    capacity: redisCapacity
  }
}

#disable-next-line BCP318
var sqlConnectionString = deploySql ? 'Server=tcp:${sql.outputs.sqlServerFqdn},1433;Initial Catalog=${sql.outputs.databaseName};User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;' : ''
#disable-next-line BCP318
var redisConnectionString = deployRedis ? '${redis.outputs.redisHostName}:${string(redis.outputs.redisSslPort)},password=${redis.outputs.redisPrimaryKey},ssl=True,abortConnect=False' : ''

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
    appInsightsConnectionString: insights.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: insights.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    keyVaultUri: keyVaultUri
    gatewayImage: gatewayImage
    ordersImage: ordersImage
    inventoryImage: inventoryImage
    notificationsImage: notificationsImage
    uiImage: uiImage
    sqlConnectionString: sqlConnectionString
    redisConnectionString: redisConnectionString
    acrLoginServer: platformAcrLoginServer
    acrPullIdentityId: platformAcrPullIdentityId
    acrRegistryUsername: acrRegistryUsername
    acrRegistryPassword: acrRegistryPassword
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
output gatewayContainerAppFqdn string = containerApps.outputs.gatewayContainerAppFqdn
output uiContainerAppFqdn string = containerApps.outputs.uiContainerAppFqdn
output functionAppName string = functions.outputs.functionAppName
output keyVaultName string = keyVault.outputs.keyVaultName
output appInsightsName string = insights.outputs.appInsightsName
output acrName string = platformAcrName
output acrLoginServer string = platformAcrLoginServer
output acrPullIdentityId string = platformAcrPullIdentityId
output oidcClientId string = identity.outputs.clientId
#disable-next-line BCP318
output sqlServerName string = deploySql ? sql.outputs.sqlServerName : ''
#disable-next-line BCP318
output sqlServerFqdn string = deploySql ? sql.outputs.sqlServerFqdn : ''
#disable-next-line BCP318
output sqlDatabaseName string = deploySql ? sql.outputs.databaseName : ''
#disable-next-line BCP318
output redisName string = deployRedis ? redis.outputs.redisName : ''
#disable-next-line BCP318
output redisHostName string = deployRedis ? redis.outputs.redisHostName : ''
#disable-next-line BCP318
output redisSslPort int = deployRedis ? redis.outputs.redisSslPort : 0
