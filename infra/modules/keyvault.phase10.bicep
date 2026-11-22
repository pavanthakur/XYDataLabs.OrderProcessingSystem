targetScope = 'resourceGroup'

@description('Azure region for Key Vault')
param location string

@description('Environment code')
param environment string

@description('Azure resource suffix override used for Key Vault naming')
param resourceSuffix string = ''

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Principal ID allowed to read secrets for the gateway')
param gatewayPrincipalId string = ''

@description('Principal ID allowed to read secrets for Orders')
param ordersPrincipalId string = ''

@description('Principal ID allowed to read secrets for Payments')
param paymentsPrincipalId string = ''

@description('Principal ID allowed to read secrets for Inventory')
param inventoryPrincipalId string = ''

@description('Principal ID allowed to read secrets for Notifications')
param notificationsPrincipalId string = ''

@description('Principal ID allowed to read secrets for Functions')
param functionsPrincipalId string = ''

@description('Deployment workflow service principal object ID allowed to read and synchronize deployment-owned secrets')
param deploymentPrincipalObjectId string = ''

@description('Whether the SQL baseline is being provisioned or intentionally updated in this deployment')
param deploySql bool = false

@description('Snapshot of the current Key Vault access policies, captured immediately before deployment so the required vault property is preserved.')
param existingKeyVaultAccessPolicies array

@description('SQL Server admin password to persist in Key Vault for later SQL and managed-identity workflows')
@secure()
param sqlAdminPassword string = ''

@description('Dedicated tenant connection strings keyed by tenant code. Values are written as Key Vault secrets; tenant topology is still discovered from the registry at runtime.')
@secure()
param dedicatedTenantConnectionStrings object = {}

@description('Non-secret keys corresponding to dedicatedTenantConnectionStrings. Kept separate so ARM What-If can evaluate the deployment loop without inspecting secret values.')
param dedicatedTenantCodes array = []

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
var shortBaseName = take(baseName, 15)
var keyVaultName = 'kv-${shortBaseName}-${effectiveResourceSuffix}'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: false
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // The Key Vault API requires this property on vault PUT. The deployment workflow
    // supplies a fresh snapshot so existing operator policies are preserved; app
    // policies are still added independently through the child resource below.
    accessPolicies: existingKeyVaultAccessPolicies
  }
}

resource accessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = if (!empty(gatewayPrincipalId) || !empty(ordersPrincipalId) || !empty(paymentsPrincipalId) || !empty(inventoryPrincipalId) || !empty(notificationsPrincipalId) || !empty(functionsPrincipalId) || !empty(deploymentPrincipalObjectId)) {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: concat(
      !empty(gatewayPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: gatewayPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(ordersPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: ordersPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(paymentsPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: paymentsPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(inventoryPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: inventoryPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(notificationsPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: notificationsPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(functionsPrincipalId) ? [
        {
          tenantId: subscription().tenantId
          objectId: functionsPrincipalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
        }
      ] : [],
      !empty(deploymentPrincipalObjectId) ? [
        {
          tenantId: subscription().tenantId
          objectId: deploymentPrincipalObjectId
          permissions: {
            secrets: [
              'get'
              'list'
              'set'
            ]
          }
        }
      ] : []
    )
  }
}

resource sqlAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (deploySql) {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
  }
}

resource dedicatedTenantConnectionStringSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for tenantCode in dedicatedTenantCodes: {
  parent: keyVault
  name: 'DedicatedTenantConnectionStrings--${tenantCode}'
  properties: {
    value: string(dedicatedTenantConnectionStrings[tenantCode])
  }
}]

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
