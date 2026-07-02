targetScope = 'resourceGroup'

@description('Environment code')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('GitHub owner / org prefix for global uniqueness')
param githubOwner string

var gatewayAppRegistrationName = '${githubOwner}-${baseName}-gateway-phase10-${environment}'
var ordersAppRegistrationName = '${githubOwner}-${baseName}-orders-phase10-${environment}'
var functionsAppRegistrationName = '${githubOwner}-${baseName}-functions-phase10-${environment}'

output clientId string = ''
output appRegistrationName string = gatewayAppRegistrationName
output gatewayAppRegistrationName string = gatewayAppRegistrationName
output ordersAppRegistrationName string = ordersAppRegistrationName
output functionsAppRegistrationName string = functionsAppRegistrationName
