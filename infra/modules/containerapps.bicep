targetScope = 'resourceGroup'

@description('Azure region for Container Apps resources')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Log Analytics workspace resource id for the ACA environment')
param logAnalyticsWorkspaceId string = ''

@description('Application Insights connection string')
param appInsightsConnectionString string = ''

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string = ''

@description('Key Vault URI for runtime secret lookup')
param keyVaultUri string = ''

@description('Service Bus topic name for transport tracing')
param serviceBusTopicName string = 'order-events'

@description('Service Bus connection string for the Phase 10 transport slice')
param serviceBusConnectionString string = ''

@description('Container CPU cores as a JSON numeric string')
param cpuCores string = '0.25'

@description('Inventory subscription name')
param inventorySubscriptionName string = 'inventory-order-created'

@description('Notifications subscription name')
param notificationsSubscriptionName string = 'notifications-order-created'

@description('Dead-letter topic name')
param deadLetterTopicName string = 'order-events-dlq'

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

var environmentName = 'aca-${baseName}-${environment}'
var gatewayName = '${baseName}-gate-${environment}'
var ordersName = '${baseName}-ord-${environment}'
var inventoryName = '${baseName}-inv-${environment}'
var notificationsName = '${baseName}-notif-${environment}'
var uiName = '${baseName}-ui-${environment}'
var commonEnv = [
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
]
var publisherEnv = [
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
var inventoryEnv = concat(publisherEnv, [
  {
    name: 'ServiceBus__SubscriptionName'
    value: inventorySubscriptionName
  }
])
var notificationsEnv = concat(publisherEnv, [
  {
    name: 'ServiceBus__SubscriptionName'
    value: notificationsSubscriptionName
  }
])

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: !empty(logAnalyticsWorkspaceId) ? {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2021-06-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2021-06-01').primarySharedKey
      }
    } : null
  }
}

resource gatewayApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: gatewayName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: gatewayImage
          env: commonEnv
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

resource ordersApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: ordersName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    configuration: {
      ingress: {
        external: false
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'orders'
          image: ordersImage
          env: concat(commonEnv, publisherEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

resource inventoryApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: inventoryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    template: {
      containers: [
        {
          name: 'inventory'
          image: inventoryImage
          env: concat(commonEnv, inventoryEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

resource notificationsApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: notificationsName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    template: {
      containers: [
        {
          name: 'notifications'
          image: notificationsImage
          env: concat(commonEnv, notificationsEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

resource uiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: uiName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'ui'
          image: uiImage
          env: commonEnv
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

output managedEnvironmentId string = acaEnvironment.id
output gatewayContainerAppName string = gatewayApp.name
output ordersContainerAppName string = ordersApp.name
output inventoryContainerAppName string = inventoryApp.name
output notificationsContainerAppName string = notificationsApp.name
output uiContainerAppName string = uiApp.name
output gatewayContainerAppFqdn string = gatewayApp.properties.configuration.ingress.fqdn
output uiContainerAppFqdn string = uiApp.properties.configuration.ingress.fqdn
output gatewayPrincipalId string = gatewayApp.identity.principalId
output ordersPrincipalId string = ordersApp.identity.principalId
output inventoryPrincipalId string = inventoryApp.identity.principalId
output notificationsPrincipalId string = notificationsApp.identity.principalId
output uiPrincipalId string = uiApp.identity.principalId
