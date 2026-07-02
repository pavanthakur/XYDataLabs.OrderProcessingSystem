targetScope = 'resourceGroup'

@description('Azure region for Functions resources')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

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

var functionAppName = 'func-${baseName}-${environment}'
var appSettings = [
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

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    siteConfig: {
      appSettings: appSettings
    }
  }
}

output functionAppName string = app.name
output functionPrincipalId string = app.identity.principalId
