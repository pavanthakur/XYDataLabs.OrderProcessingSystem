@description('Azure region for Redis')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Azure resource suffix override used for Redis naming')
param resourceSuffix string = ''

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Azure Managed Redis SKU name. Use Balanced_B0 for the smallest Phase 10 dev/test baseline.')
param skuName string = 'Balanced_B0'

@description('Azure Managed Redis database clustering policy. EnterpriseCluster keeps the endpoint compatible with non-clustered client usage.')
param clusteringPolicy string = 'EnterpriseCluster'

@description('Enable high availability. Keep Disabled for dev/test cost control; use Enabled for production readiness.')
param highAvailability string = 'Disabled'

var effectiveResourceSuffix = empty(resourceSuffix) ? environment : resourceSuffix
var redisName = '${baseName}-redis-${effectiveResourceSuffix}'

resource redis 'Microsoft.Cache/redisEnterprise@2025-04-01' = {
  name: redisName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    encryption: {}
    highAvailability: highAvailability
    minimumTlsVersion: '1.2'
  }
  tags: {
    env: environment
    app: baseName
    component: 'cache'
  }
}

resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' = {
  parent: redis
  name: 'default'
  properties: {
    accessKeysAuthentication: 'Enabled'
    clientProtocol: 'Encrypted'
    clusteringPolicy: clusteringPolicy
    evictionPolicy: 'VolatileLRU'
    modules: []
    port: 10000
  }
}

#disable-next-line use-resource-symbol-reference
var redisPrimaryKey = listKeys(redisDatabase.id, '2025-04-01').primaryKey

output redisName string = redis.name
output redisHostName string = redis.properties.hostName
output redisSslPort int = redisDatabase.properties.port
output redisPrimaryKey string = redisPrimaryKey
output redisConnectionString string = '${redis.properties.hostName}:${string(redisDatabase.properties.port)},password=${redisPrimaryKey},ssl=True,abortConnect=False'
