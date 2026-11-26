targetScope = 'resourceGroup'

@description('Azure region for Functions host storage')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Azure resource suffix override used for environment-scoped resource names')
param resourceSuffix string

@description('Base application name')
param baseName string

@description('Storage redundancy SKU for dedicated Functions host storage')
param hostStorageSkuName string

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
// Keep names deterministic and environment-specific; do not derive them from deployment-run IDs.
var storageAccountName = '${take(replace(toLower(baseName), '-', ''), 8)}${take(replace(toLower(effectiveResourceSuffix), '-', ''), 3)}${uniqueString(resourceGroup().id)}'
var hostStorageIdentityName = '${baseName}-functions-storage-${effectiveResourceSuffix}'

resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: hostStorageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
  tags: {
    env: environment
    app: baseName
    component: 'functions-host-storage'
  }
}

resource hostStorageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: hostStorageIdentityName
  location: location
  tags: {
    env: environment
    app: baseName
    component: 'functions-host-storage-identity'
  }
}

output hostStorageAccountName string = hostStorage.name
output hostStorageAccountId string = hostStorage.id
output hostStorageIdentityName string = hostStorageIdentity.name
output hostStorageIdentityResourceId string = hostStorageIdentity.id
output hostStorageIdentityPrincipalId string = hostStorageIdentity.properties.principalId
output hostStorageIdentityClientId string = hostStorageIdentity.properties.clientId
