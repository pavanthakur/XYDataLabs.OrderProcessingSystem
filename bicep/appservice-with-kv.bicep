targetScope = 'resourceGroup'

@description('Name of the App Service')
param appName string

@description('Name of the Key Vault')
param keyVaultName string

@description('Name of the App Service Plan')
param appServicePlanName string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('App Service Plan SKU')
param appServiceSku string = 'F1'

@description('Environment name (dev, uat, prod)')
param environment string = 'dev'

@description('Non-secret OpenPayAdapter base URL')
param openPayAdapterBaseUrl string = 'https://api.openpay.example.com'

// Determine ASPNETCORE_ENVIRONMENT based on environment parameter
var aspNetCoreEnvironment = environment == 'dev' ? 'Development' : (environment == 'uat' ? 'Staging' : 'Production')

// Map SKU name to tier
var skuTierMap = {
  F1: 'Free'
  B1: 'Basic'
  B2: 'Basic'
  B3: 'Basic'
  S1: 'Standard'
  S2: 'Standard'
  S3: 'Standard'
  P1v2: 'PremiumV2'
  P2v2: 'PremiumV2'
  P3v2: 'PremiumV2'
  P1v3: 'PremiumV3'
  P2v3: 'PremiumV3'
  P3v3: 'PremiumV3'
}

// Reference to existing Key Vault (must be created separately)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServiceSku
    tier: skuTierMap[appServiceSku]
  }
  properties: {
    reserved: false
  }
  tags: {
    environment: environment
    app: 'orderprocessing'
  }
}

// App Service with Managed Identity
resource appService 'Microsoft.Web/sites@2023-12-01' = {
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
        // Non-secret app settings
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: aspNetCoreEnvironment
        }
        {
          name: 'OpenPayAdapter__BaseUrl'
          value: openPayAdapterBaseUrl
        }
        // Secret app settings as Key Vault references
        {
          name: 'OpenPayAdapter__ApiKey'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/secrets/OpenPayAdapter--ApiKey/)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/secrets/ApplicationInsights--ConnectionString/)'
        }
      ]
    }
  }
  tags: {
    environment: environment
    app: 'orderprocessing'
    role: 'api'
  }
}

// Grant App Service Managed Identity access to Key Vault secrets
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: appService.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Outputs
output appServiceName string = appService.name
output appServiceHostName string = appService.properties.defaultHostName
output appServicePrincipalId string = appService.identity.principalId
output appServicePlanName string = appServicePlan.name
