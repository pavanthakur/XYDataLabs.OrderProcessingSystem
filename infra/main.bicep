targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'centralindia'

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
param githubOwner string

@description('App Service SKU (F1, B1, P1v3, etc)')
param appServiceSku string = 'F1'

@description('Boolean to enable identity (OIDC) provisioning via deployment script')
param enableIdentity bool = true

@description('SQL Server admin username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL Server admin password')
@secure()
param sqlAdminPassword string

@description('Database service objective (Basic, S0, S1, etc)')
param databaseServiceObjective string = 'Basic'

var rgName = 'rg-${baseName}-${environment}'

// Resource Group (subscription scope deployment creates RG first)
resource appRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgName
  location: location
  tags: {
    env: environment
    app: baseName
  }
}

// SQL Database
module sql 'modules/sql.bicep' = {
  name: 'sql-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
    databaseServiceObjective: databaseServiceObjective
  }
}

// Hosting (Plan + WebApps)
module hosting 'modules/hosting.bicep' = {
  name: 'hosting-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    githubOwner: githubOwner
    sku: appServiceSku
    appInsightsConnectionString: insights.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: insights.outputs.appInsightsInstrumentationKey
    sqlConnectionString: sql.outputs.connectionString
  }
}

// Application Insights
module insights 'modules/insights.bicep' = {
  name: 'insights-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
  }
}

// Identity + Federated Credentials (optional)
// Note: This module requires a User-Assigned Managed Identity with Graph permissions
// For now, identity provisioning should be done separately via setup-github-oidc.ps1
module identity 'modules/identity.bicep' = if (enableIdentity) {
  name: 'identity-${environment}'
  scope: appRg
}

output resourceGroupName string = appRg.name
output apiHostName string = hosting.outputs.apiHostName
output uiHostName string = hosting.outputs.uiHostName
output appInsightsName string = insights.outputs.appInsightsName
output appInsightsConnectionString string = insights.outputs.appInsightsConnectionString
output appInsightsInstrumentationKey string = insights.outputs.appInsightsInstrumentationKey
output sqlServerName string = sql.outputs.sqlServerName
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output databaseName string = sql.outputs.databaseName
output oidcClientId string = enableIdentity ? identity!.outputs.clientId : ''
