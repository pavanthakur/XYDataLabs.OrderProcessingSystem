targetScope = 'resourceGroup'

@description('Azure region for Application Insights')
param location string

@description('Environment code')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Optional Log Analytics workspace resource id')
param workspaceResourceId string = ''

var aiName = 'ai-${baseName}-${environment}'

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: !empty(workspaceResourceId) ? {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResourceId
  } : {
    Application_Type: 'web'
  }
  tags: {
    env: environment
    app: baseName
    component: 'monitoring'
  }
}

output appInsightsName string = insights.name
output appInsightsConnectionString string = insights.properties.ConnectionString
output appInsightsInstrumentationKey string = insights.properties.InstrumentationKey
