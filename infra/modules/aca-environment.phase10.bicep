targetScope = 'resourceGroup'

param location string
param environment string
param resourceSuffix string = ''
param baseName string = 'orderprocessing'
param logAnalyticsWorkspaceId string

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'aca-${baseName}-${effectiveResourceSuffix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2021-06-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2021-06-01').primarySharedKey
      }
    }
  }
}

output managedEnvironmentId string = acaEnvironment.id
output defaultDomain string = acaEnvironment.properties.defaultDomain
