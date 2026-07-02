targetScope = 'resourceGroup'

@description('Azure region for Log Analytics')
param location string

@description('Environment code')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Log Analytics retention in days')
param retentionInDays int = 30

var logAnalyticsName = 'law-${take(baseName, 15)}-${environment}'

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
  tags: {
    env: environment
    app: baseName
    component: 'logging'
  }
}

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
