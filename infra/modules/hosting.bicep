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
@description('App Insights Connection String (optional)')
param appInsightsConnectionString string = ''
@description('App Insights Instrumentation Key (optional)')
param appInsightsInstrumentationKey string = ''
@description('SQL Server FQDN (optional)')
param sqlServerFqdn string = ''
@description('SQL Database Name (optional)')
param sqlDatabaseName string = ''
@description('SQL Admin Username (optional)')
param sqlAdminUsername string = ''
@description('SQL Admin Password (optional)')
@secure()
param sqlAdminPassword string = ''

var planName = 'asp-${baseName}-${environment}'
var apiName = '${githubOwner}-${baseName}-api-xyapp-${environment}'
var uiName  = '${githubOwner}-${baseName}-ui-xyapp-${environment}'

// Construct SQL connection string from components
// Only create connection string if all required SQL parameters are provided
var sqlConnectionString = !empty(sqlServerFqdn) && !empty(sqlDatabaseName) && !empty(sqlAdminUsername) && !empty(sqlAdminPassword) 
  ? 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;' 
  : ''

// App Insights configuration for App Services
var appInsightsSettings = !empty(appInsightsConnectionString) ? [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
    value: '~3'
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: appInsightsInstrumentationKey
  }
  {
    name: 'XDT_MicrosoftApplicationInsights_Mode'
    value: 'recommended'
  }
] : []

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
      appSettings: appInsightsSettings
      connectionStrings: !empty(sqlConnectionString) ? [
        {
          name: 'OrderProcessingSystemDbConnection'
          connectionString: sqlConnectionString
          type: 'SQLAzure'
        }
      ] : []
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
      appSettings: appInsightsSettings
      connectionStrings: !empty(sqlConnectionString) ? [
        {
          name: 'OrderProcessingSystemDbConnection'
          connectionString: sqlConnectionString
          type: 'SQLAzure'
        }
      ] : []
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
