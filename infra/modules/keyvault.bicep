targetScope = 'resourceGroup'

@description('Azure region for the Key Vault')
param location string

@description('Environment name (dev, uat, prod)')
param environment string

@description('Base application name')
param baseName string

@description('Object ID of the API App Service managed identity (for access policy)')
param apiAppPrincipalId string = ''

@description('Object ID of the UI App Service managed identity (for access policy)')
param uiAppPrincipalId string = ''

@description('Tenant ID')
param tenantId string = subscription().tenantId

// Key Vault name (must be globally unique, max 24 chars)
// Using shortened base name and environment to stay within limits
var shortBaseName = take(baseName, 15) // Limit base name to 15 chars
var keyVaultName = 'kv-${shortBaseName}-${environment}'

// Create Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: false
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    accessPolicies: []
  }
  tags: {
    environment: environment
    app: baseName
  }
}

// Grant API App Service Managed Identity access to Key Vault secrets
resource apiAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = if (!empty(apiAppPrincipalId)) {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: apiAppPrincipalId
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

// Grant UI App Service Managed Identity access to Key Vault secrets
resource uiAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = if (!empty(uiAppPrincipalId)) {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: uiAppPrincipalId
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
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
