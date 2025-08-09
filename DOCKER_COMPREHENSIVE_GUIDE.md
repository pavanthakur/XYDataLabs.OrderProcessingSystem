# 🐳 Docker Comprehensive Startup Guide
## Complete Reference for XY Order Processing System

> **Single Source of Truth** - This document contains all standardized approaches, commands, and configurations for running the XY Order Processing System using Docker.

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Developer Quick Reference](#developer-quick-reference)
3. [Prerequisites](#prerequisites)
4. [Environment Overview](#environment-overview)
5. [Command Reference](#command-reference)
6. [Standard Mode Operations](#standard-mode-operations)
7. [Enterprise Mode Operations](#enterprise-mode-operations)
8. [Troubleshooting](#troubleshooting)
9. [Configuration Details](#configuration-details)
10. [Best Practices](#best-practices)
11. [Related Documentation](#related-documentation)

---

## 🚀 Quick Start

### Immediate Startup Commands

```powershell
# Development - HTTP (Most Common)
.\start-docker.ps1 -Environment dev -Profile http

# Development - HTTPS with SSL
.\start-docker.ps1 -Environment dev -Profile https

# UAT Testing
.\start-docker.ps1 -Environment uat -Profile https

# Production (Enterprise Mode Recommended)
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst
```

### Stop Services
```powershell
.\start-docker.ps1 -Environment dev -Profile http -Down
```

---

## 👨‍💻 Developer Quick Reference

### ⭐⭐⭐ **Essential Daily Commands (Must Know)**

```powershell
# 1. Start Development (90% of daily use)
.\start-docker.ps1 -Environment dev -Profile http

# 2. Stop Development
.\start-docker.ps1 -Environment dev -Profile http -Down

# 3. Clean Start (when having issues)
.\start-docker.ps1 -Environment dev -Profile http -CleanCache
```

### ⭐⭐ **Weekly Commands (Should Know)**

```powershell
# 4. HTTPS Testing
.\start-docker.ps1 -Environment dev -Profile https

# 5. Full Services (HTTP + HTTPS)
.\start-docker.ps1 -Environment dev -Profile all

# 6. Enterprise Mode (advanced features)
.\start-docker.ps1 -Environment dev -Profile http -EnterpriseMode
```

### ⭐ **Troubleshooting Commands (Good to Know)**

```powershell
# 7. Nuclear Option (when everything is broken)
.\start-docker.ps1 -Environment dev -Profile http -CleanCache -EnterpriseMode

# 8. Conservative Cleanup (preserve some data)
.\start-docker.ps1 -Environment dev -Profile http -ConservativeClean -EnterpriseMode
```

### 🔄 **Recommended Daily Workflow**

```powershell
# Morning Startup
.\start-docker.ps1 -Environment dev -Profile http

# 🚀 Code, test, develop... (containers stay running)
# Access: http://localhost:5000/swagger (API) + http://localhost:5002 (UI)

# End of Day
.\start-docker.ps1 -Environment dev -Profile http -Down
```

### 🆘 **When Things Go Wrong**

```powershell
# Step 1: Try clean restart
.\start-docker.ps1 -Environment dev -Profile http -Down
.\start-docker.ps1 -Environment dev -Profile http -CleanCache

# Step 2: If still broken, nuclear option
.\start-docker.ps1 -Environment dev -Profile http -CleanCache -EnterpriseMode
```

### ✅ **Before Committing Code**

```powershell
# Test HTTPS works
.\start-docker.ps1 -Environment dev -Profile https

# Or test everything
.\start-docker.ps1 -Environment dev -Profile all
```

> **💡 Pro Tip**: 80% of the time you only need the first 3 commands. The rest are for specific scenarios or troubleshooting.

---

## 📦 Prerequisites

### 1. System Requirements
- **Docker Desktop**: Latest version with Windows containers support
- **PowerShell**: Version 5.1 or higher
- **.NET 8.0 SDK**: For local development
- **Windows 10/11**: With Hyper-V enabled

### 2. SSL Certificates (Required for HTTPS)
```powershell
# Generate development certificates
dotnet dev-certs https -ep ./dev-certs/aspnetapp.pfx -p P@ss100
dotnet dev-certs https --trust
```

### 3. Configuration Files
All environments require their specific `sharedsettings.{env}.json` files:
- `sharedsettings.dev.json` - Development configuration
- `sharedsettings.uat.json` - UAT configuration  
- `sharedsettings.prod.json` - Production configuration

### 4. Docker Networks (Auto-Created)
The script automatically creates these networks:
- **Standard**: `xynetwork`
- **Enterprise Dev**: `xy-dev-network` (172.20.0.0/16)
- **Enterprise UAT**: `xy-uat-network` (172.21.0.0/16)
- **Enterprise Prod**: `xy-prod-network` (172.22.0.0/16)

---

## 🌍 Environment Overview

### Development Environment (`dev`)
- **Purpose**: Local development and testing
- **Network**: xy-dev-network (Enterprise) / xynetwork (Standard)
- **Security**: Development level
- **Cleanup**: Aggressive cleanup available
- **Backup**: Not required
- **URLs**: 
  - API HTTP: http://localhost:5000/swagger
  - API HTTPS: https://localhost:5001/swagger
  - UI HTTP: http://localhost:5002
  - UI HTTPS: https://localhost:5003

### UAT Environment (`uat`)
- **Purpose**: User acceptance testing and staging
- **Network**: xy-uat-network (Enterprise) / xynetwork (Standard)
- **Security**: Testing level
- **Cleanup**: Conservative cleanup
- **Backup**: Required in Enterprise mode
- **URLs**: Same ports as dev (environment isolation via networks)

### Production Environment (`prod`)
- **Purpose**: Live production deployment
- **Network**: xy-prod-network (Enterprise) / xynetwork (Standard)
- **Security**: Production level
- **Cleanup**: Minimal cleanup only
- **Backup**: Mandatory in Enterprise mode
- **URLs**: Same ports as dev (environment isolation via networks)

---

## 📖 Command Reference

### Script Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Environment` | `dev`, `uat`, `prod` | `dev` | Target environment |
| `-Profile` | `http`, `https`, `all` | `http` | Services to start |
| `-SharedSettingsPath` | File path | `sharedsettings.{env}.json` | Configuration file |
| `-EnvFilePath` | File path | `.env` | Environment file output |
| `-Down` | Switch | False | Stop services |
| `-CleanCache` | Switch | False | Clean Docker cache |
| `-EnterpriseMode` | Switch | False | Enable enterprise features |
| `-ConservativeClean` | Switch | False | Conservative cache cleanup |
| `-PreservePersistentData` | Switch | False | Preserve volumes during cleanup |
| `-BackupFirst` | Switch | False | Create backup before starting |

### Profile Options

| Profile | Services Started | Use Case |
|---------|------------------|----------|
| `http` | API + UI (HTTP only) | Development, quick testing |
| `https` | API + UI (HTTPS only) | SSL testing, secure development |
| `all` | API + UI (HTTP + HTTPS) | Full testing, production |

---

## 🔧 Standard Mode Operations

### Basic Operations
```powershell
# Start development with HTTP
.\start-docker.ps1 -Environment dev -Profile http

# Start with HTTPS (requires certificates)
.\start-docker.ps1 -Environment dev -Profile https

# Start all services (HTTP + HTTPS)
.\start-docker.ps1 -Environment uat -Profile all

# Stop services
.\start-docker.ps1 -Environment dev -Profile http -Down
```

### With Cache Management
```powershell
# Clean cache before starting (full cleanup)
.\start-docker.ps1 -Environment dev -Profile https -CleanCache

# This automatically runs:
# 1. docker system prune -f --volumes
# 2. Starts the specified environment
```

### Environment-Specific Examples
```powershell
# Development - Fast iteration
.\start-docker.ps1 -Environment dev -Profile http -CleanCache

# UAT - Production-like testing
.\start-docker.ps1 -Environment uat -Profile all

# Production - Stable deployment
.\start-docker.ps1 -Environment prod -Profile https
```

---

## 🏢 Enterprise Mode Operations

### Enterprise Mode Benefits
- **Network Isolation**: Environment-specific Docker networks
- **Intelligent Cleanup**: Environment-aware cache policies
- **Automatic Backups**: Data protection for critical environments
- **Audit Logging**: Complete operation tracking
- **Security Policies**: Environment-specific security levels

### Basic Enterprise Commands
```powershell
# Enable enterprise features for development
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# UAT with conservative cleanup
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# Production with mandatory backup
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst
```

### Enterprise Cleanup Options
```powershell
# Development: Aggressive cleanup (safe for dev)
.\start-docker.ps1 -Environment dev -Profile http -EnterpriseMode -CleanCache

# UAT: Conservative cleanup (preserves recent data)
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# Production: Minimal cleanup (production-safe only)
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -ConservativeClean
```

### Data Protection Commands
```powershell
# Preserve persistent data during cleanup
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean -PreservePersistentData

# Mandatory backup before production start
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst

# Safe production restart with data preservation
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst -PreservePersistentData
```

---

## 📊 Monitoring & Status

### Container Status
After startup, the script displays:
```
Container status:
NAMES                                   STATUS                    PORTS
testappxy_orderprocessingsystem-ui-1   Up 30 seconds            0.0.0.0:5002->5002/tcp
testappxy_orderprocessingsystem-api-1  Up 30 seconds (healthy)  0.0.0.0:5000->5000/tcp
```

### Access URLs
- **API Swagger (HTTP)**: http://localhost:5000/swagger
- **API Swagger (HTTPS)**: https://localhost:5001/swagger  
- **UI Application (HTTP)**: http://localhost:5002
- **UI Application (HTTPS)**: https://localhost:5003

### Log Monitoring
```powershell
# View real-time logs
docker-compose -f docker-compose.dev.yml logs -f

# View specific service logs
docker-compose -f docker-compose.dev.yml logs -f api
docker-compose -f docker-compose.dev.yml logs -f ui

# Enterprise mode logs (if enabled)
Get-Content "logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 20 -Wait
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Port Already in Use
```powershell
# Check what's using the port
netstat -ano | findstr :5000

# Kill the process (replace PID)
taskkill /PID 1234 /F

# Or use different ports by modifying sharedsettings.{env}.json
```

#### 2. Network Issues
```powershell
# List Docker networks
docker network ls

# Remove problematic network
docker network rm xynetwork

# Script will recreate automatically on next run
```

**Common Network Error**: `network xynetwork declared as external, but could not be found`
- **Cause**: Clean cache removes networks, but Docker Compose expects specific network names
- **Solution**: Network names in `docker-compose.{env}.yml` must match `sharedsettings.{env}.json`
- **Check**: Verify network name consistency between files

#### 3. SSL Certificate Issues
```powershell
# Regenerate certificates
dotnet dev-certs https --clean
dotnet dev-certs https -ep ./dev-certs/aspnetapp.pfx -p P@ss100
dotnet dev-certs https --trust
```

#### 4. Configuration File Missing
```powershell
# Check if file exists
Test-Path sharedsettings.dev.json

# The script will show error with expected file path
```

### Debug Mode
```powershell
# Add verbose output
$VerbosePreference = "Continue"
.\start-docker.ps1 -Environment dev -Profile http -Verbose
```

---

## ⚙️ Configuration Details

### Port Configuration
Ports are automatically extracted from `sharedsettings.{env}.json`:

```json
{
  "ApiSettings": {
    "API": {
      "http": { "Port": 5000 },
      "https": { "Port": 5001 }
    },
    "UI": {
      "http": { "Port": 5002 },
      "https": { "Port": 5003 }
    }
  }
}
```

### Generated .env File
The script automatically generates:
```
# Port configuration extracted from sharedsettings.json
# Generated on 2025-08-03 15:30:45
# Environment: dev
API_HTTP_PORT=5000
API_HTTPS_PORT=5001
UI_HTTP_PORT=5002
UI_HTTPS_PORT=5003
```

### Docker Compose Files
- `docker-compose.dev.yml` - Development configuration
- `docker-compose.uat.yml` - UAT configuration  
- `docker-compose.prod.yml` - Production configuration

---

## 🎯 Best Practices

### Development Workflow
```powershell
# Daily development start
.\start-docker.ps1 -Environment dev -Profile http

# Clean start when needed
.\start-docker.ps1 -Environment dev -Profile http -CleanCache

# End of day
.\start-docker.ps1 -Environment dev -Profile http -Down
```

### Testing Workflow
```powershell
# Start UAT for testing
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode

# Conservative cleanup if issues
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# Stop after testing
.\start-docker.ps1 -Environment uat -Profile https -Down
```

### Production Deployment
```powershell
# Always use enterprise mode with backup
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst

# For maintenance restarts
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -ConservativeClean -PreservePersistentData
```

### Resource Management
```powershell
# Check Docker resource usage
docker system df

# Enterprise cleanup by environment
.\start-docker.ps1 -Environment dev -Profile http -EnterpriseMode -CleanCache    # Aggressive
.\start-docker.ps1 -Environment uat -Profile http -EnterpriseMode -ConservativeClean  # Conservative  
.\start-docker.ps1 -Environment prod -Profile http -EnterpriseMode -ConservativeClean # Minimal
```

---

## 📚 Related Documentation

This comprehensive guide references and consolidates information from:

- **README.md** - Basic project setup and requirements
- **DOCKER_STARTUP_GUIDE.md** - Original startup documentation
- **ENTERPRISE_DOCKER_GUIDE.md** - Enterprise features overview
- **SIMPLIFIED_CONFIG_GUIDE.md** - Configuration management
- **PRODUCTION_CONFIG_NOTES.md** - Production-specific settings
- **LearningHelp/DockerHelp.md** - Docker basics and troubleshooting
- **LearningHelp/sharedsettingsHelp.md** - Configuration file details

### Quick Reference Links
- [Docker Official Documentation](https://docs.docker.com/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [.NET Docker Images](https://hub.docker.com/_/microsoft-dotnet)

---

## 📞 Support & Maintenance

### Script Maintenance
The `start-docker.ps1` script is actively maintained and includes:
- **Backward Compatibility**: All existing commands continue to work
- **Feature Flags**: Enterprise features are opt-in via `-EnterpriseMode`
- **Error Handling**: Comprehensive error messages and logging
- **Auto-Recovery**: Automatic prerequisite creation and validation

### Version Information
- **Script Version**: Latest (with Enterprise features)
- **Docker Compose Version**: Environment-specific files
- **Target Framework**: .NET 8.0
- **Supported Platforms**: Windows 10/11 with Docker Desktop

---

**📝 Note**: This document serves as the definitive guide for all Docker operations in the XY Order Processing System. For specific issues or advanced configurations, refer to the individual documentation files listed in the Related Documentation section.

**🔄 Last Updated**: August 3, 2025 - Comprehensive consolidation with Enterprise features integration.
