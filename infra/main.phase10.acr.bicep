targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'centralindia'

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
param githubOwner string

var rgName = 'rg-${baseName}-${environment}'

resource appRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgName
  location: location
  tags: {
    env: environment
    app: baseName
  }
}

module acr 'modules/acr.phase10.bicep' = {
  name: 'acr-phase10-${environment}'
  scope: appRg
  params: {
    location: location
    environment: environment
    baseName: baseName
    githubOwner: githubOwner
  }
}

output resourceGroupName string = appRg.name
output acrName string = acr.outputs.registryName
output acrLoginServer string = acr.outputs.registryLoginServer
output acrPullIdentityId string = acr.outputs.acrPullIdentityId
output acrPullIdentityClientId string = acr.outputs.acrPullIdentityClientId
output acrPullIdentityPrincipalId string = acr.outputs.acrPullIdentityPrincipalId
