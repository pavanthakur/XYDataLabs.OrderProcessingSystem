# Enhanced SharedSettings with Launch Configuration Migration Guide

## 🎯 Overview

This guide shows you how to replace individual `launchSettings.json` files with a centralized configuration in your enhanced `sharedsettings` files. This approach provides:

- **Single Source of Truth**: All environment configuration in one place
- **Azure Integration**: Built-in Azure deployment settings
- **Enterprise Consistency**: Standardized configuration across all environments
- **Automated Generation**: Generate `launchSettings.json` from centralized configuration

## 📁 New File Structure

### Enhanced SharedSettings Files
```
sharedsettings-enhanced.dev.json     # Development with local + Azure settings
sharedsettings-enhanced.uat.json     # UAT with Azure integration
sharedsettings-enhanced.prod.json    # Production with full Azure configuration
```

### Configuration Sections
Each enhanced file contains:
```json
{
  "ApiSettings": { ... },           // Existing API/UI port configuration
  "LaunchSettings": { ... },        // Launch profiles for Visual Studio/.NET CLI
  "Azure": { ... },                 // Azure deployment configuration
  "Docker": { ... }                 // Docker enterprise settings
}
```

## 🚀 Quick Start

### 1. Generate LaunchSettings from Enhanced Configuration
```powershell
# Generate for development environment
.\generate-launchsettings.ps1 -Environment dev -Project Both

# Generate for UAT with Azure settings
.\generate-launchsettings.ps1 -Environment uat -Project Both -UseAzureSettings

# Generate for production
.\generate-launchsettings.ps1 -Environment prod -Project Both -UseAzureSettings -Force
```

### 2. Use with Enterprise Docker Script
```powershell
# Start with enhanced settings and auto-generate launch configuration
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -UseEnhancedSettings -GenerateLaunchSettings

# UAT deployment with Azure integration
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -UseEnhancedSettings -ConservativeClean

# Production with full enterprise features
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -UseEnhancedSettings -BackupFirst
```

## 📋 Configuration Details

### Development Environment Features
```json
"LaunchSettings": {
  "Environment": "Development",
  "DefaultProfile": "http",
  "Profiles": {
    "API": {
      "http": {
        "launchBrowser": true,
        "launchUrl": "swagger",
        "hotReloadEnabled": true
      }
    }
  }
}
```

### UAT Environment Features
```json
"LaunchSettings": {
  "Environment": "Staging", 
  "DefaultProfile": "https",
  "Profiles": {
    "API": {
      "https": {
        "launchBrowser": false,
        "hotReloadEnabled": false,
        "environmentVariables": {
          "CORS_ALLOWED_ORIGINS": "https://uat-ui.xydatalabs.com"
        }
      }
    }
  }
}
```

### Production Environment Features
```json
"LaunchSettings": {
  "Environment": "Production",
  "DefaultProfile": "https",
  "Profiles": {
    "API": {
      "https": {
        "launchBrowser": false,
        "hotReloadEnabled": false,
        "environmentVariables": {
          "CORS_ALLOWED_ORIGINS": "https://ui.xydatalabs.com"
        }
      }
    }
  }
}
```

## 🌐 Azure Integration

### Local Development with Azure Services
```json
"Azure": {
  "Local": {
    "Enabled": false,
    "ConnectionStrings": {
      "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=OrderProcessingDB_Dev;Trusted_Connection=true;",
      "Redis": "localhost:6379"
    }
  }
}
```

### Azure Cloud Configuration
```json
"Azure": {
  "Cloud": {
    "Enabled": true,
    "WebApps": {
      "API": {
        "Name": "wa-orderprocessing-api-prod",
        "Url": "https://api.xydatalabs.com",
        "CustomDomain": "api.xydatalabs.com"
      },
      "UI": {
        "Name": "wa-orderprocessing-ui-prod", 
        "Url": "https://ui.xydatalabs.com",
        "CustomDomain": "ui.xydatalabs.com"
      }
    },
    "Database": {
      "ServerName": "sql-orderprocessing-prod.database.windows.net",
      "Edition": "Premium",
      "ServiceObjective": "P1"
    }
  }
}
```

## 🛠️ Migration Steps

### Step 1: Backup Existing Files
```powershell
# Backup current launchSettings.json files
.\generate-launchsettings.ps1 -Environment dev -Project Both -Backup
```

### Step 2: Test Enhanced Configuration
```powershell
# Test development environment
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -UseEnhancedSettings -GenerateLaunchSettings

# Verify Visual Studio integration
# Open Visual Studio and check debug dropdown for new profiles
```

### Step 3: Update Team Workflow
```powershell
# Team members can generate their launchSettings.json
.\generate-launchsettings.ps1 -Environment dev -Project Both

# Or automatically generate during Docker startup
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -UseEnhancedSettings -GenerateLaunchSettings
```

## 🎛️ Command Reference

### Generate LaunchSettings Script
```powershell
# Basic generation
.\generate-launchsettings.ps1 -Environment dev

# With Azure settings
.\generate-launchsettings.ps1 -Environment uat -UseAzureSettings

# Force overwrite existing files
.\generate-launchsettings.ps1 -Environment prod -Force

# Generate for specific project only
.\generate-launchsettings.ps1 -Environment dev -Project API

# Create backup before generation
.\generate-launchsettings.ps1 -Environment dev -Backup
```

### Enhanced Docker Script
```powershell
# Use enhanced settings
.\start-docker.ps1 -Environment dev -UseEnhancedSettings

# Auto-generate launch settings
.\start-docker.ps1 -Environment dev -GenerateLaunchSettings

# Full enterprise mode with enhanced settings
.\start-docker.ps1 -Environment uat -EnterpriseMode -UseEnhancedSettings -ConservativeClean
```

## 🔄 Visual Studio Integration

### Debug Profile Selection
After generating `launchSettings.json`, Visual Studio will show:
- **http**: HTTP development profile
- **https**: HTTPS development profile  
- **Docker**: Docker container profile
- **IIS Express**: IIS Express profile (dev only)

### Environment Variables
Generated profiles include environment-specific variables:
- **Development**: Local development settings
- **UAT**: Staging environment with Azure integration
- **Production**: Production Azure configuration

## 📊 Benefits

### 1. Centralized Configuration
- **Single file** per environment contains all settings
- **Consistent** configuration across team members
- **Version controlled** enterprise settings

### 2. Azure Integration
- **Built-in Azure deployment** configuration
- **Environment-specific** Azure resource settings
- **Connection string** management for Azure services

### 3. Enterprise Features
- **Environment isolation** through separate configuration
- **Security policies** embedded in configuration
- **Audit trail** through version control

### 4. Developer Experience
- **Automatic generation** of Visual Studio launch profiles
- **No manual configuration** required
- **Team consistency** guaranteed

## 🎯 Best Practices

### 1. Environment Strategy
```powershell
# Development: Local development with optional Azure services
.\generate-launchsettings.ps1 -Environment dev

# UAT: Production-like with Azure integration
.\generate-launchsettings.ps1 -Environment uat -UseAzureSettings

# Production: Full Azure configuration
.\generate-launchsettings.ps1 -Environment prod -UseAzureSettings
```

### 2. Team Workflow
```powershell
# Each developer runs once after git pull
.\generate-launchsettings.ps1 -Environment dev

# Or integrate into Docker startup
.\start-docker.ps1 -Environment dev -GenerateLaunchSettings
```

### 3. CI/CD Integration
```yaml
# Azure DevOps Pipeline step
- task: PowerShell@2
  displayName: 'Generate Launch Settings'
  inputs:
    targetType: 'filePath'
    filePath: 'generate-launchsettings.ps1'
    arguments: '-Environment $(environment) -UseAzureSettings -Force'
```

This enhanced configuration approach eliminates the need for individual `launchSettings.json` files while providing comprehensive Azure integration and enterprise-grade configuration management.
