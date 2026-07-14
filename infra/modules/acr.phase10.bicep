targetScope = 'resourceGroup'

@description('Azure region for Azure Container Registry')
param location string

@description('Environment code')
@minLength(2)
param environment string

@description('Base application name')
@minLength(2)
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
@minLength(2)
param githubOwner string

@description('Azure Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Basic'

var registryNameSeed = toLower(replace('${githubOwner}${baseName}${environment}', '-', ''))
var registryName = take('xyops${registryNameSeed}', 50)
var acrPullIdentityName = 'id-${baseName}-acr-pull-${environment}'
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    env: environment
    app: baseName
    component: 'container-registry'
  }
}

resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: acrPullIdentityName
  location: location
  tags: {
    env: environment
    app: baseName
    component: 'container-registry-pull'
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, acrPullIdentity.id, 'AcrPull')
  scope: registry
  properties: {
    principalId: acrPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output acrPullIdentityId string = acrPullIdentity.id
output acrPullIdentityClientId string = acrPullIdentity.properties.clientId
output acrPullIdentityPrincipalId string = acrPullIdentity.properties.principalId
