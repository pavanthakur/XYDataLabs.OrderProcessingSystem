targetScope = 'resourceGroup'

@description('Azure region for Service Bus resources')
param location string

@description('Environment code')
param environment string

@description('Azure resource suffix override used for namespace naming')
param resourceSuffix string = ''

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

@description('Name of the approved replay request queue')
param replayRequestQueueName string = 'dlq-replay-requests'

@description('Optional Azure-dev-only queue used by the isolated duplicate-delivery drill')
param replayDrillRequestQueueName string = ''

@description('Optional operator/test-runner object ID granted isolated drill receive and business-topic send access')
param replayDrillRunnerPrincipalObjectId string = ''

@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
@description('Principal type for the optional isolated replay-drill receiver grant')
param replayDrillRunnerPrincipalType string = 'User'

@description('Maximum delivery count before dead-lettering')
param maxDeliveryCount int = 10

@description('Message TTL in ISO 8601 duration format')
param messageTtl string = 'P7D'

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
var sbNamespaceName = 'sb-${baseName}-${effectiveResourceSuffix}'
var dlqTopicName = 'order-events-dlq'
var transportAuthRuleName = 'phase10-transport'
var entityAutoDeleteOnIdle = 'P10675199DT2H48M5.4775807S'

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
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    defaultMessageTimeToLive: messageTtl
    enableExpress: false
    enablePartitioning: false
    maxMessageSizeInKilobytes: 256
    maxSizeInMegabytes: 1024
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    supportOrdering: true
  }
}

resource inventorySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: inventorySubscriptionName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
    lockDuration: 'PT1M'
    enableBatchedOperations: true
    isClientAffine: false
  }
}

resource ordersPaymentStateSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: ordersPaymentStateSubscriptionName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
    lockDuration: 'PT1M'
    enableBatchedOperations: true
    isClientAffine: false
  }
}

resource notificationsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: orderTopic
  name: notificationsSubscriptionName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    forwardDeadLetteredMessagesTo: dlqTopicName
    lockDuration: 'PT1M'
    enableBatchedOperations: true
    isClientAffine: false
  }
}

resource dlqTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: sbNamespace
  name: dlqTopicName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    defaultMessageTimeToLive: messageTtl
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    maxMessageSizeInKilobytes: 256
    maxSizeInMegabytes: 1024
    supportOrdering: false
  }
}

resource dlqReplaySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: dlqTopic
  name: deadLetterSubscriptionName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: messageTtl
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
    enableBatchedOperations: true
    isClientAffine: false
  }
}

resource replayRequestQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: sbNamespace
  name: replayRequestQueueName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    defaultMessageTimeToLive: messageTtl
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enablePartitioning: false
    lockDuration: 'PT1M'
    maxMessageSizeInKilobytes: 256
    maxSizeInMegabytes: 1024
    maxDeliveryCount: maxDeliveryCount
    deadLetteringOnMessageExpiration: true
    requiresDuplicateDetection: false
  }
}

resource replayDrillRequestQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = if (environment == 'dev' && !empty(replayDrillRequestQueueName)) {
  parent: sbNamespace
  name: replayDrillRequestQueueName
  properties: {
    autoDeleteOnIdle: entityAutoDeleteOnIdle
    defaultMessageTimeToLive: messageTtl
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enablePartitioning: false
    lockDuration: 'PT1M'
    maxMessageSizeInKilobytes: 256
    maxSizeInMegabytes: 1024
    maxDeliveryCount: maxDeliveryCount
    deadLetteringOnMessageExpiration: true
    requiresDuplicateDetection: false
  }
}

var serviceBusDataReceiverRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
)
var serviceBusDataSenderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
)

resource replayDrillReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (environment == 'dev' && !empty(replayDrillRequestQueueName) && !empty(replayDrillRunnerPrincipalObjectId)) {
  name: guid(replayDrillRequestQueue.id, replayDrillRunnerPrincipalObjectId, serviceBusDataReceiverRoleDefinitionId)
  scope: replayDrillRequestQueue
  properties: {
    principalId: replayDrillRunnerPrincipalObjectId
    principalType: replayDrillRunnerPrincipalType
    roleDefinitionId: serviceBusDataReceiverRoleDefinitionId
  }
}

resource replayDrillBusinessTopicSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (environment == 'dev' && !empty(replayDrillRequestQueueName) && !empty(replayDrillRunnerPrincipalObjectId)) {
  name: guid(orderTopic.id, replayDrillRunnerPrincipalObjectId, serviceBusDataSenderRoleDefinitionId)
  scope: orderTopic
  properties: {
    principalId: replayDrillRunnerPrincipalObjectId
    principalType: replayDrillRunnerPrincipalType
    roleDefinitionId: serviceBusDataSenderRoleDefinitionId
  }
}

output serviceBusNamespaceName string = sbNamespace.name
output orderEventsTopic string = orderTopic.name
output ordersPaymentStateSubscription string = ordersPaymentStateSubscription.name
output inventorySubscription string = inventorySubscription.name
output notificationsSubscription string = notificationsSubscription.name
output deadLetterTopic string = dlqTopic.name
output deadLetterSubscription string = dlqReplaySubscription.name
output replayRequestQueueName string = replayRequestQueue.name
output replayDrillRequestQueueName string = environment == 'dev' ? replayDrillRequestQueueName : ''
output replayDrillRequestQueueId string = environment == 'dev' && !empty(replayDrillRequestQueueName) ? replayDrillRequestQueue.id : ''
output transportAuthRuleName string = transportAuthRule.name
#disable-next-line use-resource-symbol-reference
var transportAuthRuleConnectionString = listKeys(transportAuthRule.id, '2022-10-01-preview').primaryConnectionString

@secure()
output transportAuthRuleConnectionString string = transportAuthRuleConnectionString
