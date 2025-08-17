# Simplified Centralized Configuration Guide

## 🎯 Overview

This guide shows the simplified approach to centralized configuration without `launchSettings.json` files. All configuration is now in your standard `sharedsettings.{env}.json` files.

## ✅ **What Changed**

### **Removed Dependencies**
- ❌ `launchSettings.json` files (API and UI projects)
- ❌ `sharedsettings-enhanced.*.json` files
- ❌ `generate-launchsettings.ps1` script
- ❌ `start-docker-enterprise.ps1` standalone script

### **Simplified Structure**
- ✅ All configuration in standard `sharedsettings.{env}.json` files
- ✅ Single Docker script with enterprise features built-in
- ✅ No external dependencies or generation scripts

## 📁 **Current File Structure**

```
sharedsettings.dev.json     # Development configuration
sharedsettings.uat.json     # UAT configuration
sharedsettings.prod.json    # Production configuration
start-docker.ps1            # Single Docker script with enterprise features
```

## 🏗️ **Configuration Sections**

Each `sharedsettings.{env}.json` now contains:

```json
{
  "ApiSettings": {
    "API": { "http": {...}, "https": {...} },
    "UI": { "http": {...}, "https": {...} }
  },
  "LaunchSettings": {
    "Environment": "Development|Staging|Production",
    "DefaultProfile": "http|https",
    "LaunchBrowser": true|false,
    "HotReloadEnabled": true|false,
    "API": {
      "LaunchUrl": "swagger",
      "EnvironmentVariables": {...}
    },
    "UI": {
      "EnvironmentVariables": {...}
    }
  },
  "Azure": {
    "Local": { "Enabled": true|false, "ConnectionStrings": {...} },
    "Cloud": { "Enabled": true|false, "WebApps": {...}, "Database": {...} }
  },
  "Docker": {
    "Networks": { "Name": "xy-{env}-network", "Subnet": "...", "Gateway": "..." },
    "Volumes": {...}
  }
}
```

## 🚀 **Usage Examples**

### **Development**
```powershell
# Standard startup
.\start-docker.ps1 -Environment dev -Profile https

# With enterprise features
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode
```

### **UAT**
```powershell
# Conservative UAT deployment
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# With backup
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -BackupFirst
```

### **Production**
```powershell
# Production deployment with full safety
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst
```

## 📋 **Environment Configurations**

### **Development** (`sharedsettings.dev.json`)
```json
{
  "LaunchSettings": {
    "Environment": "Development",
    "DefaultProfile": "http",
    "LaunchBrowser": true,
    "HotReloadEnabled": true
  },
  "Azure": {
    "Local": { "Enabled": true },
    "Cloud": { "Enabled": false }
  },
  "Docker": {
    "Networks": { "Name": "xy-dev-network" }
  }
}
```

### **UAT** (`sharedsettings.uat.json`)
```json
{
  "LaunchSettings": {
    "Environment": "Staging",
    "DefaultProfile": "https",
    "LaunchBrowser": false,
    "HotReloadEnabled": false
  },
  "Azure": {
    "Local": { "Enabled": false },
    "Cloud": { "Enabled": true }
  },
  "Docker": {
    "Networks": { "Name": "xy-uat-network" }
  }
}
```

### **Production** (`sharedsettings.prod.json`)
```json
{
  "LaunchSettings": {
    "Environment": "Production",
    "DefaultProfile": "https",
    "LaunchBrowser": false,
    "HotReloadEnabled": false
  },
  "Azure": {
    "Cloud": { "Enabled": true }
  },
  "Docker": {
    "Networks": { "Name": "xy-prod-network" }
  }
}
```

## 🛠️ **How It Works**

### **No More Launch Settings Files**
- Visual Studio and .NET CLI now get configuration from `sharedsettings` files
- Environment variables are set directly by the Docker script
- No need to maintain separate `launchSettings.json` files

### **Automatic Network Configuration**
```powershell
# The script automatically reads network configuration from sharedsettings
$settings = Get-Content "sharedsettings.$Environment.json" | ConvertFrom-Json
$networkName = $settings.Docker.Networks.Name
```

### **Environment-Specific Behavior**
- **Development**: Local services, browser launch, hot reload
- **UAT**: Azure integration, no browser launch, conservative cleanup
- **Production**: Azure only, minimal cleanup, mandatory backups

## 🎯 **Benefits**

### **1. Simplicity**
- ✅ No external dependencies
- ✅ No generation scripts
- ✅ Single configuration file per environment

### **2. Consistency**
- ✅ All team members get identical configuration
- ✅ Environment-specific settings guaranteed
- ✅ Version controlled configuration

### **3. Enterprise Ready**
- ✅ Environment isolation through networks
- ✅ Azure integration built-in
- ✅ Enterprise cleanup policies
- ✅ Backup strategies per environment

### **4. Developer Experience**
- ✅ Simple commands
- ✅ Clear environment separation
- ✅ No manual configuration required

## 🔄 **Visual Studio Integration**

### **Without Launch Settings Files**
Visual Studio will use default profiles, but your Docker script sets all necessary environment variables:

```powershell
# Environment variables are set by the Docker script based on sharedsettings
$env:ASPNETCORE_ENVIRONMENT = $settings.LaunchSettings.Environment
$env:CORS_ALLOWED_ORIGINS = $settings.LaunchSettings.API.EnvironmentVariables.CORS_ALLOWED_ORIGINS
```

### **Debug Through Docker**
Use Docker profiles in Visual Studio:
1. Set Docker Compose as startup project
2. Select environment profile (dev/uat/prod)
3. Press F5 to debug

## 📊 **Comparison**

| **Before** | **After** |
|------------|-----------|
| Multiple `launchSettings.json` files | No launch settings files |
| Enhanced sharedsettings files | Standard sharedsettings files |
| Generation scripts | Direct configuration reading |
| Multiple dependencies | Single script solution |

## 🎛️ **Command Reference**

### **Standard Commands**
```powershell
# Development
.\start-docker.ps1 -Environment dev -Profile https

# UAT
.\start-docker.ps1 -Environment uat -Profile all

# Production
.\start-docker.ps1 -Environment prod -Profile all
```

### **Enterprise Commands**
```powershell
# Development with enterprise features
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# UAT with conservative cleanup
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# Production with backup
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst
```

### **Stop Commands**
```powershell
# Stop any environment
.\start-docker.ps1 -Environment {env} -Profile {profile} -Down
```

This simplified approach eliminates complexity while maintaining all enterprise features and Azure integration in your standard sharedsettings files.
