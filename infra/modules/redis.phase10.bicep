@description('Azure region for Redis')
param location string

@description('Environment code (dev, staging, prod)')
param environment string

@description('Base application name')
param baseName string = 'orderprocessing'

@description('Redis SKU name')
param skuName string = 'Basic'

@description('Redis SKU family')
param skuFamily string = 'C'

@description('Redis SKU capacity')
param capacity int = 0

var redisName = '${baseName}-redis-${environment}'

resource redis 'Microsoft.Cache/redis@2024-11-01' = {
  name: redisName
  location: location
  #disable-next-line BCP187
  sku: {
    name: skuName
    family: skuFamily
    capacity: capacity
  }
  #disable-next-line BCP035
  properties: {
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisVersion: '6'
    redisConfiguration: {
      'maxmemory-policy': 'volatile-lru'
      'preferred-data-persistence-auth-method': ''
    }
  }
  tags: {
    env: environment
    app: baseName
    component: 'cache'
  }
}

#disable-next-line use-resource-symbol-reference
var redisPrimaryKey = listKeys(redis.id, '2024-11-01').primaryKey

output redisName string = redis.name
output redisHostName string = redis.properties.hostName
output redisSslPort int = redis.properties.sslPort
output redisPrimaryKey string = redisPrimaryKey
output redisConnectionString string = '${redis.properties.hostName}:${string(redis.properties.sslPort)},password=${redisPrimaryKey},ssl=True,abortConnect=False'
