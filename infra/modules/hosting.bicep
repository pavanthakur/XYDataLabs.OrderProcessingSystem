@description('Region')
param location string
@description('Environment code')
param environment string
@description('Base application name')
param baseName string
@description('GitHub owner prefix for uniqueness')
param githubOwner string
@description('App Service Plan SKU')
param sku string

var planName = 'asp-${baseName}-${environment}'
var apiName = '${githubOwner}-${baseName}-api-xyapp-${environment}'
var uiName  = '${githubOwner}-${baseName}-ui-xyapp-${environment}'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: sku
    tier: sku == 'F1' ? 'Free' : sku
  }
  properties: {
    reserved: false
  }
  tags: {
    env: environment
    app: baseName
    component: 'hosting'
  }
}

resource apiApp 'Microsoft.Web/sites@2023-12-01' = {
  name: apiName
  location: location
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
    }
    httpsOnly: true
  }
  tags: {
    env: environment
    app: baseName
    role: 'api'
  }
}

resource uiApp 'Microsoft.Web/sites@2023-12-01' = {
  name: uiName
  location: location
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
    }
    httpsOnly: true
  }
  tags: {
    env: environment
    app: baseName
    role: 'ui'
  }
}

output apiHostName string = apiApp.properties.defaultHostName
output uiHostName string = uiApp.properties.defaultHostName
