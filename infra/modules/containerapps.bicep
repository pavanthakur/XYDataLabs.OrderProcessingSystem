targetScope = 'resourceGroup'

@description('Environment-specific Entra API and SPA configuration; no credentials.')
param identity object

@description('Azure region for Container Apps resources')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Azure resource suffix override used for environment-scoped resource names')
param resourceSuffix string = ''

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Pre-created ACA environment resource id')
param managedEnvironmentId string

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

@description('Orders payment-state subscription name')
param ordersPaymentStateSubscriptionName string = 'orders-payment-state'

@description('Notifications subscription name')
param notificationsSubscriptionName string = 'notifications-order-created'

@description('Dead-letter topic name')
param deadLetterTopicName string = 'order-events-dlq'

@description('Dead-letter replay subscription name')
param deadLetterSubscriptionName string = 'dlq-replay'

@description('Approved replay request queue name')
param replayRequestQueueName string = 'dlq-replay-requests'

@description('Maximum delivery count before dead-lettering')
param maxDeliveryCount int = 10

@description('Message TTL in ISO 8601 duration format')
param messageTtl string = 'P7D'

@description('Gateway container image reference')
param gatewayImage string

@description('Orders container image reference')
param ordersImage string

@description('Payments container image reference')
param paymentsImage string

@description('Inventory container image reference')
param inventoryImage string

@description('Notifications container image reference')
param notificationsImage string

@description('UI container image reference')
param uiImage string

@description('Optional managed-identity SQL connection string for Phase 10 application runtime')
param sqlConnectionString string = ''

@description('Optional Redis connection string for Phase 10 parity runs')
param redisConnectionString string = ''

@description('Azure Container Registry login server used for image pulls')
param acrLoginServer string = ''

@description('User-assigned managed identity resource id used by Container Apps to pull from ACR')
param acrPullIdentityId string = ''

@description('ACR pull token username used when role-assignment-free registry auth is selected')
param acrRegistryUsername string = ''

@secure()
@description('ACR pull token password used when role-assignment-free registry auth is selected')
param acrRegistryPassword string = ''

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
var aspNetCoreEnvironment = environment == 'prod'
  ? 'Production'
  : environment == 'staging'
    ? 'Staging'
    : 'Development'
var gatewayName = '${baseName}-gate-${effectiveResourceSuffix}'
var ordersName = '${baseName}-ord-${effectiveResourceSuffix}'
var paymentsName = '${baseName}-pay-${effectiveResourceSuffix}'
var inventoryName = '${baseName}-inv-${effectiveResourceSuffix}'
var notificationsName = '${baseName}-notif-${effectiveResourceSuffix}'
var uiName = '${baseName}-ui-${effectiveResourceSuffix}'
var frontendWebBaseUrl = identity.webOrigin
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
  {
    name: 'ORDERPROCESSING_AZURE_HOST'
    value: 'true'
  }
  {
    name: 'Frontend__WebBaseUrl'
    value: frontendWebBaseUrl
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
]
var sqlEnv = !empty(sqlConnectionString) ? [
  {
    name: 'ConnectionStrings__OrderProcessingSystemDbConnection'
    value: sqlConnectionString
  }
] : []
var redisEnv = !empty(redisConnectionString) ? [
  {
    name: 'ConnectionStrings__Redis'
    value: redisConnectionString
  }
] : []
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
    name: 'ServiceBus__ReplayRequestQueueName'
    value: replayRequestQueueName
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
var identityEnv = [
  { name: 'IdentityProvider__Enabled', value: 'true' }
  { name: 'IdentityProvider__Mode', value: 'Entra' }
  { name: 'IdentityProvider__Authority', value: identity.authority }
  { name: 'IdentityProvider__Audience', value: identity.audience }
  { name: 'IdentityProvider__RequiredScope', value: identity.requiredScope }
  { name: 'IdentityProvider__TenantClaimType', value: identity.tenantClaimType }
  { name: 'TenantConfiguration__UiSelectorEnabled', value: string(identity.selectorEnabled) }
]
var runtimeCommonEnv = concat(commonEnv, sqlEnv, redisEnv, identityEnv)
var ordersEnv = concat(publisherEnv, [
  {
    name: 'ServiceBus__PaymentStateSubscriptionName'
    value: ordersPaymentStateSubscriptionName
  }
])
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
var uiEnv = concat(runtimeCommonEnv, [
  { name: 'IDENTITY_MODE', value: 'Entra' }
  { name: 'APP_ENVIRONMENT', value: environment }
  { name: 'PUBLIC_WEB_ORIGIN', value: identity.webOrigin }
  { name: 'PUBLIC_IDENTITY_AUTHORITY', value: identity.authority }
  { name: 'PUBLIC_IDENTITY_CLIENT_ID', value: identity.spaClientId }
  { name: 'PUBLIC_IDENTITY_SCOPES', value: identity.apiScope }
  {
    name: 'ORDERPROCESSING_API_BASE_URL'
    value: 'http://${gatewayName}'
  }
])
var registryPasswordSecretName = 'acr-pull-token-password'
var useRegistryPassword = !empty(acrRegistryUsername) && !empty(acrRegistryPassword)
var registryConfigs = useRegistryPassword ? [
  {
    server: acrLoginServer
    username: acrRegistryUsername
    passwordSecretRef: registryPasswordSecretName
  }
] : [
  {
    server: acrLoginServer
    identity: acrPullIdentityId
  }
]
var registrySecrets = useRegistryPassword ? [
  {
    name: registryPasswordSecretName
    value: acrRegistryPassword
  }
] : []
var appIdentity = !empty(acrPullIdentityId) ? {
  type: 'SystemAssigned, UserAssigned'
  userAssignedIdentities: {
    '${acrPullIdentityId}': {}
  }
} : {
  type: 'SystemAssigned'
}

resource ordersApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: ordersName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
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
            env: concat(runtimeCommonEnv, ordersEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

resource inventoryApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: inventoryName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
      ingress: {
        external: false
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'inventory'
          image: inventoryImage
          env: concat(runtimeCommonEnv, inventoryEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

resource paymentsApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: paymentsName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
      ingress: {
        external: false
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'payments'
          image: paymentsImage
          env: concat(runtimeCommonEnv, publisherEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

resource notificationsApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: notificationsName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
      ingress: {
        external: false
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'notifications'
          image: notificationsImage
          env: concat(runtimeCommonEnv, notificationsEnv)
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

resource uiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: uiName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
      ingress: {
        external: true
        targetPort: 5022
      }
    }
    template: {
      containers: [
        {
          name: 'ui'
          image: uiImage
          env: uiEnv
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

var ordersInternalAddress = 'https://${ordersApp.properties.configuration.ingress.fqdn}'
var paymentsInternalAddress = 'https://${paymentsApp.properties.configuration.ingress.fqdn}'
var inventoryInternalAddress = 'https://${inventoryApp.properties.configuration.ingress.fqdn}'
var notificationsInternalAddress = 'https://${notificationsApp.properties.configuration.ingress.fqdn}'
var uiInternalAddress = 'https://${uiApp.properties.configuration.ingress.fqdn}'

resource gatewayApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: gatewayName
  location: location
  identity: appIdentity
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      secrets: registrySecrets
      registries: registryConfigs
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
          env: concat(runtimeCommonEnv, [
            {
              name: 'Gateway__AllowedHosts__5'
              value: gatewayName
            }
            {
              name: 'ReverseProxy__Clusters__orders-cluster__Destinations__orders-primary__Address'
              value: ordersInternalAddress
            }
            {
              name: 'ReverseProxy__Clusters__payments-cluster__Destinations__payments-primary__Address'
              value: paymentsInternalAddress
            }
            {
              name: 'ReverseProxy__Clusters__inventory-cluster__Destinations__inventory-primary__Address'
              value: inventoryInternalAddress
            }
            {
              name: 'ReverseProxy__Clusters__notifications-cluster__Destinations__notifications-primary__Address'
              value: notificationsInternalAddress
            }
            {
              name: 'ReverseProxy__Clusters__ui-cluster__Destinations__ui-primary__Address'
              value: uiInternalAddress
            }
          ])
          resources: {
            cpu: json(cpuCores)
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

output managedEnvironmentId string = managedEnvironmentId
output gatewayContainerAppName string = gatewayApp.name
output ordersContainerAppName string = ordersApp.name
output paymentsContainerAppName string = paymentsApp.name
output inventoryContainerAppName string = inventoryApp.name
output notificationsContainerAppName string = notificationsApp.name
output uiContainerAppName string = uiApp.name
output gatewayContainerAppFqdn string = gatewayApp.properties.configuration.ingress.fqdn
output uiContainerAppFqdn string = uiApp.properties.configuration.ingress.fqdn
output gatewayPrincipalId string = gatewayApp.identity.principalId
output ordersPrincipalId string = ordersApp.identity.principalId
output paymentsPrincipalId string = paymentsApp.identity.principalId
output inventoryPrincipalId string = inventoryApp.identity.principalId
output notificationsPrincipalId string = notificationsApp.identity.principalId
output uiPrincipalId string = uiApp.identity.principalId
