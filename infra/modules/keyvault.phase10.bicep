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

@description('Deployment workflow service principal object ID allowed to read secrets for Azure verification scripts')
param deploymentPrincipalObjectId string = ''

@description('SQL Server admin password to persist in Key Vault for later SQL and managed-identity workflows')
@secure()
param sqlAdminPassword string = ''

@description('Dedicated tenant connection strings keyed by tenant code. Values are written as Key Vault secrets; tenant topology is still discovered from the registry at runtime.')
@secure()
param dedicatedTenantConnectionStrings object = {}

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
    accessPolicies: []
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
            ]
          }
        }
      ] : []
    )
  }
}

resource sqlAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(sqlAdminPassword)) {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
  }
}

resource dedicatedTenantConnectionStringSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for dedicatedTenant in items(dedicatedTenantConnectionStrings): {
  parent: keyVault
  name: 'DedicatedTenantConnectionStrings--${dedicatedTenant.key}'
  properties: {
    value: string(dedicatedTenant.value)
  }
}]

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
