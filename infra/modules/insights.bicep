@description('Region')
param location string
@description('Environment')
param environment string
@description('Base application name')
param baseName string

var aiName = 'ai-${baseName}-${environment}'

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  tags: {
    env: environment
    app: baseName
    component: 'monitoring'
  }
}

output appInsightsName string = insights.name
