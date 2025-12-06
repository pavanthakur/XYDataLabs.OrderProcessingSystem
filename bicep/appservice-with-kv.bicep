@description('The name of the App Service')
param appName string

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The name of the App Service Plan')
param appServicePlanName string

@description('The name of the Key Vault')
param keyVaultName string

@description('The base URL for the OpenPay adapter')
param openPayBaseUrl string

@description('The ASP.NET Core environment (Development, Staging, Production)')
param aspnetcoreEnvironment string

// Get reference to existing App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' existing = {
  name: appServicePlanName
}

// Get reference to existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Deploy or update App Service with system-assigned Managed Identity
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'OpenPayAdapter__BaseUrl'
          value: openPayBaseUrl
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: aspnetcoreEnvironment
        }
        {
          name: 'OpenPayAdapter__ApiKey'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=OpenPayAdapter--ApiKey)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=APPLICATIONINSIGHTS-CONNECTION-STRING)'
        }
      ]
    }
  }
  tags: {
    Environment: aspnetcoreEnvironment
    ManagedBy: 'Bicep'
  }
}

// Role definition for Key Vault Secrets User
// Built-in role: Key Vault Secrets User - 4633458b-17de-408a-b874-0445c86b69e6
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

// Grant the web app's managed identity the Key Vault Secrets User role
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webApp.id, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Output the web app's principal ID
output principalId string = webApp.identity.principalId
output webAppName string = webApp.name
output webAppHostName string = webApp.properties.defaultHostName
