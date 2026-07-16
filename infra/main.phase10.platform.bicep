targetScope = 'subscription'

@description('Azure region for the shared platform foundation')
param location string = 'centralindia'

@description('Base application name')
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
param githubOwner string

@description('Platform suffix used to keep the persistent foundation distinct from environment RGs')
param platformSuffix string = 'platform'

@description('Create the AcrPull role assignment from the platform ACR to the runtime pull identity. Requires roleAssignments/write at the registry scope.')
param assignAcrPullRole bool = false

var platformRgName = 'rg-${baseName}-${platformSuffix}'

resource platformRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: platformRgName
  location: location
  tags: {
    env: platformSuffix
    app: baseName
    lifecycle: 'platform'
  }
}

module acr 'modules/acr.phase10.bicep' = {
  name: 'acr-platform-${platformSuffix}'
  scope: platformRg
  params: {
    location: location
    environment: platformSuffix
    baseName: baseName
    githubOwner: githubOwner
    assignAcrPullRole: assignAcrPullRole
  }
}

output resourceGroupName string = platformRg.name
output acrName string = acr.outputs.registryName
output acrLoginServer string = acr.outputs.registryLoginServer
output acrPullIdentityId string = acr.outputs.acrPullIdentityId
output acrPullIdentityClientId string = acr.outputs.acrPullIdentityClientId
output acrPullIdentityPrincipalId string = acr.outputs.acrPullIdentityPrincipalId
