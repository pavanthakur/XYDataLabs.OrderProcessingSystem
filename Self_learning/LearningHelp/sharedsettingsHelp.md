# SharedSettings & Multi-Environment Docker Configuration Guide

## Overview

This document explains the enterprise-ready SharedSettings configuration system that supports multiple environments (dev, UAT, production) with Docker Compose, eliminating hardcoded values and providing Azure migration readiness.

## 🎯 Key Benefits

- **Single Source of Truth**: Only `sharedsettings.json` defines ports and configuration
- **Multi-Environment Support**: Separate configurations for dev, UAT, and production
- **Azure Ready**: Prepared for Azure App Configuration and Key Vault integration
- **Environment Isolation**: Proper separation of development and production settings
- **Zero Docker Changes**: Docker configuration remains unchanged when migrating to Azure
- **Automated Port Management**: Automatic extraction and synchronization of ports
- **Enterprise Scalability**: Production-ready with resource limits and monitoring

## 📁 File Structure

```
├── sharedsettings.json          # Main configuration file
├── .env                         # Auto-generated environment variables
├── docker-compose.yml          # Base configuration (production defaults)
├── docker-compose.dev.yml      # Development environment overrides
├── docker-compose.uat.yml      # UAT/Staging environment overrides  
├── docker-compose.prod.yml     # Production environment overrides
├── extract-ports.ps1           # Port extraction utility
└── start-docker.ps1            # Multi-environment startup script
```

## 🏗️ Architecture Overview

### Environment-Specific Compose Files

1. **docker-compose.yml** - Base configuration with production defaults
2. **docker-compose.dev.yml** - Development overrides (hot reload, source mounting)
3. **docker-compose.uat.yml** - UAT overrides (production-like testing)
4. **docker-compose.prod.yml** - Production overrides (scaling, monitoring)

### Configuration Hierarchy
```
Base (docker-compose.yml) → Environment Override → Runtime
```

## 🔧 Core Components

### 1. sharedsettings.json
The single source of truth for all configuration:

```json
{
  "ApiSettings": {
    "UI": {
      "http": {
        "Host": "localhost",
        "Port": 5002,
        "HttpsEnabled": false
      },
      "https": {
        "Host": "localhost",
        "Port": 5003,
        "HttpsEnabled": true,
        "CertPassword": "P@ss100",
        "CertPath": "/https/aspnetapp.pfx"
      }
    },
    "API": {
      "http": {
        "Host": "localhost",
        "Port": 5000,
        "HttpsEnabled": false
      },
      "https": {
        "Host": "localhost",
        "Port": 5001,
        "HttpsEnabled": true,
        "CertPassword": "P@ss100",
        "CertPath": "/https/aspnetapp.pfx"
      }
    }
  }
}
```

### 2. Dynamic Port System
The system automatically:
1. Reads `sharedsettings.json`
2. Extracts port configurations
3. Generates `.env` file with Docker environment variables
4. Configures Docker Compose dynamically

### 3. Auto-Generated .env File
```properties
# Port configuration extracted from sharedsettings.json
# Generated on 2025-07-30 00:55:42
API_HTTP_PORT=5000
API_HTTPS_PORT=5001
UI_HTTP_PORT=5002
UI_HTTPS_PORT=5003
```

## 🚀 Usage Commands

### Basic Environment-Specific Usage

```powershell
# Development Environment (default)
.\start-docker.ps1 -Environment dev -Profile http
.\start-docker.ps1 -Environment dev -Profile https

# UAT/Staging Environment
.\start-docker.ps1 -Environment uat -Profile http
.\start-docker.ps1 -Environment uat -Profile https

# Production Environment  
.\start-docker.ps1 -Environment prod -Profile http
.\start-docker.ps1 -Environment prod -Profile https

# Stop services (environment-specific)
.\start-docker.ps1 -Environment dev -Profile http -Down
.\start-docker.ps1 -Environment uat -Profile https -Down
.\start-docker.ps1 -Environment prod -Profile all -Down
```

### Quick Start Commands

```powershell
# Development with hot reload (most common)
.\start-docker.ps1

# Production deployment
.\start-docker.ps1 -Environment prod -Profile all

# UAT testing
.\start-docker.ps1 -Environment uat -Profile https
```

### Environment Features

#### Development Environment (`-Environment dev`)
- **Hot Reload**: Source code changes reflected immediately
- **Source Mounting**: Local code mapped to containers
- **Debug Configuration**: Development-friendly settings
- **Fast Startup**: Optimized for development workflow

#### UAT Environment (`-Environment uat`)
- **Production-Like**: Similar to production configuration
- **Resource Limits**: Performance testing with constraints
- **Enhanced Health Checks**: Comprehensive monitoring
- **Staging Database**: Separate UAT data isolation

#### Production Environment (`-Environment prod`)
- **High Availability**: Multiple replicas for reliability
- **Resource Management**: CPU/memory limits and reservations
- **Monitoring**: Advanced health checks and restart policies
- **Security**: Production-hardened configuration

### Advanced Usage

```powershell
# Use custom sharedsettings file
.\start-docker.ps1 -Profile https -SharedSettingsPath "custom-settings.json"

# Use custom .env file location
.\start-docker.ps1 -Profile http -EnvFilePath "custom.env"

# Extract ports only (without starting Docker)
.\extract-ports.ps1
```

### Manual Port Extraction

```powershell
# Extract ports from default sharedsettings.json
.\extract-ports.ps1

# Extract from custom file
.\extract-ports.ps1 -SharedSettingsPath "custom-config.json" -EnvFilePath "custom.env"
```

## 🌐 Application URLs

After successful startup, access your applications at:

### HTTP Profile
- **API**: http://localhost:5000/swagger
- **UI**: http://localhost:5002

### HTTPS Profile
- **API**: https://localhost:5001/swagger
- **UI**: https://localhost:5003

## ☁️ Azure Migration Path

### Current Architecture
```
sharedsettings.json → extract-ports.ps1 → .env → docker-compose.yml
```

### Future Azure Architecture
```
Azure App Configuration → extract-ports.ps1 → .env → docker-compose.yml
```

### Migration Steps

#### Phase 1: Azure App Configuration Setup

1. **Create Azure App Configuration resource**
```bash
az appconfig create --name "MyOrderProcessingConfig" --resource-group "MyResourceGroup" --location "East US"
```

2. **Upload configuration values**
```bash
az appconfig kv set --name "MyOrderProcessingConfig" --key "ApiSettings:API:http:Port" --value "5000"
az appconfig kv set --name "MyOrderProcessingConfig" --key "ApiSettings:API:https:Port" --value "5001"
az appconfig kv set --name "MyOrderProcessingConfig" --key "ApiSettings:UI:http:Port" --value "5002"
az appconfig kv set --name "MyOrderProcessingConfig" --key "ApiSettings:UI:https:Port" --value "5003"
```

#### Phase 2: Update extract-ports.ps1

Replace the JSON reading section:

```powershell
# BEFORE (Local JSON)
$sharedSettings = Get-Content $SharedSettingsPath -Raw | ConvertFrom-Json
$apiHttpPort = $sharedSettings.ApiSettings.API.http.Port

# AFTER (Azure App Configuration)
$apiHttpPort = az appconfig kv show --name "MyOrderProcessingConfig" --key "ApiSettings:API:http:Port" --query "value" -o tsv
$apiHttpsPort = az appconfig kv show --name "MyOrderProcessingConfig" --key "ApiSettings:API:https:Port" --query "value" -o tsv
$uiHttpPort = az appconfig kv show --name "MyOrderProcessingConfig" --key "ApiSettings:UI:http:Port" --query "value" -o tsv
$uiHttpsPort = az appconfig kv show --name "MyOrderProcessingConfig" --key "ApiSettings:UI:https:Port" --query "value" -o tsv
```

#### Phase 3: Azure Key Vault Integration

For sensitive values like certificates:

```powershell
# Get certificate password from Key Vault
$certPassword = az keyvault secret show --vault-name "MyKeyVault" --name "CertPassword" --query "value" -o tsv
```

#### Phase 4: Environment-Specific Configuration

```powershell
# Development environment
$configName = "OrderProcessing-Dev"

# Staging environment
$configName = "OrderProcessing-Staging"

# Production environment
$configName = "OrderProcessing-Prod"
```

### Azure-Ready extract-ports.ps1 Template

```powershell
param(
    [string]$Environment = "Development",
    [string]$ConfigurationName = "OrderProcessing-Dev",
    [string]$KeyVaultName = "MyKeyVault"
)

# Get configuration from Azure App Configuration
$apiHttpPort = az appconfig kv show --name $ConfigurationName --key "ApiSettings:API:http:Port" --query "value" -o tsv
$apiHttpsPort = az appconfig kv show --name $ConfigurationName --key "ApiSettings:API:https:Port" --query "value" -o tsv
$uiHttpPort = az appconfig kv show --name $ConfigurationName --key "ApiSettings:UI:http:Port" --query "value" -o tsv
$uiHttpsPort = az appconfig kv show --name $ConfigurationName --key "ApiSettings:UI:https:Port" --query "value" -o tsv

# Get secrets from Key Vault
$certPassword = az keyvault secret show --vault-name $KeyVaultName --name "CertPassword" --query "value" -o tsv

# Generate .env file (same as current logic)
$envContent = @"
# Port configuration extracted from Azure App Configuration
# Environment: $Environment
# Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
API_HTTP_PORT=$apiHttpPort
API_HTTPS_PORT=$apiHttpsPort
UI_HTTP_PORT=$uiHttpPort
UI_HTTPS_PORT=$uiHttpsPort
CERT_PASSWORD=$certPassword
"@

$envContent | Out-File -FilePath ".env" -Encoding utf8 -NoNewline
```

## 🔧 Troubleshooting

### Common Issues

1. **Port Already in Use**
   ```powershell
   # Check what's using the port
   netstat -ano | findstr :5000
   
   # Kill the process
   taskkill /PID <ProcessID> /F
   ```

2. **Docker Containers Not Starting**
   ```powershell
   # Check container logs
   docker logs <container-name>
   
   # Force cleanup
   docker-compose down --remove-orphans
   docker system prune -f
   ```

3. **Configuration Not Loading**
   ```powershell
   # Verify .env file generation
   Get-Content .env
   
   # Manual port extraction
   .\extract-ports.ps1 -Verbose
   ```

### Health Check Commands

```powershell
# Check container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Test API connectivity
curl http://localhost:5000/swagger -UseBasicParsing
curl https://localhost:5001/swagger -UseBasicParsing -SkipCertificateCheck

# Test UI connectivity
curl http://localhost:5002 -UseBasicParsing
curl https://localhost:5003 -UseBasicParsing -SkipCertificateCheck
```

## 📋 Best Practices

### Development
- Use HTTP profile for faster development
- Keep `sharedsettings.json` in version control
- Use `.env` in `.gitignore` (auto-generated)

### Staging/Production
- Use HTTPS profile exclusively
- Store sensitive values in Azure Key Vault
- Use environment-specific Azure App Configuration instances
- Implement proper access controls

### Security
- Never commit certificate passwords
- Use Azure Managed Identity for accessing Key Vault
- Rotate certificates regularly
- Use different certificates per environment

## 🔄 Migration Checklist

- [ ] Azure App Configuration resource created
- [ ] Configuration values uploaded to Azure
- [ ] Azure Key Vault setup for secrets
- [ ] Updated extract-ports.ps1 for Azure
- [ ] Tested with staging environment
- [ ] Production deployment verified
- [ ] Documentation updated for team

## 📞 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker and application logs
3. Verify Azure connectivity (for Azure configurations)
4. Check network connectivity and firewall settings

---

*This configuration system provides a robust foundation for scalable, cloud-ready application deployment while maintaining development simplicity.*