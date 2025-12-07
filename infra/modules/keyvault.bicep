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

// Grant App Service Managed Identities access to Key Vault secrets
// Combine both access policies into a single resource to avoid duplicate 'add' resources
resource accessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = if (!empty(apiAppPrincipalId) || !empty(uiAppPrincipalId)) {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: concat(
      // Add API access policy if principal ID is provided
      !empty(apiAppPrincipalId) ? [
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
      ] : [],
      // Add UI access policy if principal ID is provided
      !empty(uiAppPrincipalId) ? [
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
      ] : []
    )
  }
}

// Outputs
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
