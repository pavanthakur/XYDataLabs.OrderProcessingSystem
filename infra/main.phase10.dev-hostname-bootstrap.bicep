targetScope = 'subscription'

@description('Azure region for the dev Container Apps environment')
param location string = 'centralindia'

@description('Dev only. This bootstrap creates no application, identity, SQL, or payment resource.')
@allowed(['dev'])
param environment string = 'dev'

@allowed(['dev'])
param resourceSuffix string = 'dev'

param baseName string = 'orderprocessing'

resource appRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${baseName}-${resourceSuffix}'
  location: location
  tags: {
    env: environment
    app: baseName
  }
}

module logAnalytics 'modules/loganalytics.phase10.bicep' = {
  name: 'loganalytics-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    resourceSuffix: resourceSuffix
    baseName: baseName
  }
}

module acaEnvironment 'modules/aca-environment.phase10.bicep' = {
  name: 'aca-environment-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    resourceSuffix: resourceSuffix
    baseName: baseName
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
  }
}

output resourceGroupName string = appRg.name
output managedEnvironmentId string = acaEnvironment.outputs.managedEnvironmentId
output defaultDomain string = acaEnvironment.outputs.defaultDomain
output uiOrigin string = 'https://${baseName}-ui-${resourceSuffix}.${acaEnvironment.outputs.defaultDomain}'
output apiOrigin string = 'https://${baseName}-gate-${resourceSuffix}.${acaEnvironment.outputs.defaultDomain}'
