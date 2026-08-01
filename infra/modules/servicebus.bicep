targetScope = 'resourceGroup'

@description('Azure region for Service Bus resources')
param location string

@description('Environment code')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Name of the main topic for order-created events')
param orderEventsTopicName string = 'order-events'

@description('Name of the inventory subscription')
param inventorySubscriptionName string = 'inventory-order-created'

@description('Name of the orders payment-state subscription')
param ordersPaymentStateSubscriptionName string = 'orders-payment-state'

@description('Name of the notifications subscription')
param notificationsSubscriptionName string = 'notifications-order-created'

@description('Name of the DLQ replay subscription')
param deadLetterSubscriptionName string = 'dlq-replay'

@description('Maximum delivery count before dead-lettering')
param maxDeliveryCount int = 10

@description('Message TTL in ISO 8601 duration format')
param messageTtl string = 'P7D'

var sbNamespaceName = 'sb-${baseName}-${environment}'
var dlqTopicName = 'order-events-dlq'
var transportAuthRuleName = 'phase10-transport'

resource sbNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: sbNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource transportAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: sbNamespace
  name: transportAuthRuleName
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

resource orderTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: sbNamespace
  name: orderEventsTopicName
  properties: {
    defaultMessageTimeToLive: messageTtl
    maxMessageSizeInKilobytes: 256
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    supportOrdering: true
  }
}

resource inventorySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: inventorySubscriptionName
  properties: {
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
  }
}

resource ordersPaymentStateSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: ordersPaymentStateSubscriptionName
  properties: {
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
  }
}

resource notificationsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: notificationsSubscriptionName
  properties: {
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
  }
}

resource dlqTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: sbNamespace
  name: dlqTopicName
  properties: {
    defaultMessageTimeToLive: messageTtl
    enableBatchedOperations: true
    supportOrdering: false
  }
}

resource dlqReplaySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: dlqTopic
  name: deadLetterSubscriptionName
  properties: {
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
  }
}

output serviceBusNamespaceName string = sbNamespace.name
output orderEventsTopic string = orderTopic.name
output ordersPaymentStateSubscription string = ordersPaymentStateSubscription.name
output inventorySubscription string = inventorySubscription.name
output notificationsSubscription string = notificationsSubscription.name
output deadLetterTopic string = dlqTopic.name
output deadLetterSubscription string = dlqReplaySubscription.name
output transportAuthRuleName string = transportAuthRule.name
#disable-next-line use-resource-symbol-reference
var transportAuthRuleConnectionString = listKeys(transportAuthRule.id, '2022-10-01-preview').primaryConnectionString

@secure()
output transportAuthRuleConnectionString string = transportAuthRuleConnectionString
