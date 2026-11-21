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
    peerAuthentication: {
      mtls: {
        enabled: false
      }
    }
    peerTrafficConfiguration: {
      encryption: {
        enabled: false
      }
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2021-06-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2021-06-01').primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output managedEnvironmentId string = acaEnvironment.id
output defaultDomain string = acaEnvironment.properties.defaultDomain
