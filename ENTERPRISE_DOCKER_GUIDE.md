# Enterprise Docker Startup Guide

## Overview

Your Docker startup script has been enhanced with comprehensive enterprise features while maintaining full backward compatibility. You now have two deployment options:

1. **Standard Mode**: Original functionality with enhanced features
2. **Enterprise Mode**: Full enterprise-grade automation with security, compliance, and operational policies

## Enterprise Features Added

### 🏢 Environment-Specific Network Isolation
- **Development**: `xy-dev-network` (172.20.0.0/16)
- **UAT**: `xy-uat-network` (172.21.0.0/16) 
- **Production**: `xy-prod-network` (172.22.0.0/16)

### 🧹 Intelligent Cache Management
- **Development**: Aggressive cleanup available
- **UAT**: Conservative cleanup (preserves recent data)
- **Production**: Minimal cleanup (production-safe only)

### 💾 Automated Data Protection
- **UAT/Production**: Automatic backup requirements
- **Persistent Volume Protection**: Preserves critical data
- **Configuration Backup**: Saves environment settings

### 📊 Enterprise Logging & Audit Trail
- **Structured Logging**: Timestamped entries with severity levels
- **Audit Trail**: File-based logging for compliance
- **Operation Tracking**: Complete record of all actions

## Usage Examples

### Standard Mode (Existing Functionality)
```powershell
# Your existing commands work exactly as before
.\start-docker.ps1 -Environment dev -Profile https
.\start-docker.ps1 -Environment uat -Profile all -CleanCache
.\start-docker.ps1 -Environment prod -Profile https -Down
```

### Enterprise Mode (New Features)
```powershell
# Enable enterprise features
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# Production with mandatory backup
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst

# Conservative cleanup for UAT
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# Preserve persistent data during cleanup
.\start-docker.ps1 -Environment dev -Profile all -EnterpriseMode -CleanCache -PreservePersistentData
```

## New Enterprise Parameters

| Parameter | Description | Best Used For |
|-----------|-------------|---------------|
| `-EnterpriseMode` | Activates all enterprise features | UAT and Production environments |
| `-ConservativeClean` | Safe cleanup preserving recent data | UAT environment |
| `-PreservePersistentData` | Protects volumes marked as persistent | When you need to keep databases/files |
| `-BackupFirst` | Forces backup before any operations | Production deployments |

## Complete Enterprise Command Reference

### All Enterprise Parameters Available

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Environment` | String | `dev` | Target environment: `dev`, `uat`, `prod` |
| `-Profile` | String | `http` | Service profile: `http`, `https`, `all` |
| `-EnterpriseMode` | Switch | `false` | Enables enterprise features and logging |
| `-CleanCache` | Switch | `false` | Performs environment-specific cleanup |
| `-ConservativeClean` | Switch | `false` | Safe cleanup for UAT (24h+ containers only) |
| `-PreservePersistentData` | Switch | `false` | Protects persistent volumes during cleanup |
| `-BackupFirst` | Switch | `false` | Forces backup before any operations |
| `-Down` | Switch | `false` | Stops and removes containers |

### Enterprise Mode Features by Environment

| Feature | DEV | UAT | PROD |
|---------|-----|-----|------|
| **Network** | `xy-dev-network` | `xy-uat-network` | `xy-prod-network` |
| **Security Level** | `development` | `testing` | `production` |
| **Cleanup Policy** | `aggressive` | `conservative` | `minimal` |
| **Auto Backup** | ❌ | ✅ | ✅ |
| **Port Range** | 5020-5023 | 5030-5033 | 5040-5043 |
| **Subnet** | 172.20.0.0/16 | 172.21.0.0/16 | 172.22.0.0/16 |

### Tested Enterprise Command Examples

#### Development Environment Commands
```powershell
# Basic enterprise development
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# Development with aggressive cleanup
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -CleanCache

# Safe development cleanup (preserves data)
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -CleanCache -PreservePersistentData
```

#### UAT Environment Commands
```powershell
# UAT with automatic backup and conservative cleanup
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# UAT with full cleanup (for fresh testing)
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -CleanCache

# UAT startup (automatic backup included)
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode
```

#### Production Environment Commands
```powershell
# Production with mandatory backup (safest)
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst

# Production with minimal cleanup only
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -CleanCache

# Production startup (automatic backup included)
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode
```

### Enterprise Cleanup Policies Explained

#### Aggressive Cleanup (DEV)
- ✅ Removes unused containers
- ✅ Removes application images (for fresh builds)
- ✅ Cleans dangling images and build cache
- ✅ Prunes unused networks (except core networks)
- ✅ Full system prune with volumes
- ⚠️ **Space reclaimed**: Typically 100MB+ per cleanup

#### Conservative Cleanup (UAT)
- ✅ Removes containers older than 24 hours
- ✅ Cleans only dangling images
- ✅ Preserves recent containers and data
- ✅ Safe for testing environments
- ⚠️ **Space reclaimed**: Minimal, focuses on safety

#### Minimal Cleanup (PROD)
- ✅ Removes only dangling images
- ✅ Cleans build cache only
- ✅ Production-safe operations only
- ❌ No container or volume removal
- ⚠️ **Space reclaimed**: Very minimal, maximum safety

### Enterprise Logging and Monitoring

#### Log File Location
```powershell
# Enterprise logs are written to:
logs/docker-startup-{YYYY-MM-DD}.log

# View recent enterprise logs:
Get-Content logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log -Tail 20
```

#### Backup Locations
```powershell
# Backups are stored in:
backups/docker-backup-{env}-{YYYY-MM-DD-HHMMSS}/

# Example backup contents:
# ✅ sharedsettings.{env}.json
# ✅ docker-compose.{env}.yml
# ✅ Environment-specific configurations
```

#### Network Inspection Commands
```powershell
# Check enterprise networks
docker network ls | Select-String "xy-"

# Inspect network labels and security
docker network inspect xy-dev-network --format "{{json .Labels}}"
docker network inspect xy-uat-network --format "{{json .Labels}}"
docker network inspect xy-prod-network --format "{{json .Labels}}"
```

### Enterprise Safety Features

#### Production Warnings
- **Automatic Warning**: "Production environment should use -BackupFirst flag"
- **Backup Enforcement**: UAT and PROD environments automatically create backups
- **Minimal Cleanup**: Production uses safest cleanup policies only

#### Network Security Labels
```json
// Example network labels for UAT environment:
{
  "environment": "uat",
  "managed-by": "enterprise-automation", 
  "security-level": "testing"
}
```

#### Data Protection
- **Persistent Volume Protection**: `-PreservePersistentData` flag protects databases
- **Configuration Backup**: Automatic backup of environment settings
- **Core Network Protection**: xy-*-network and xy-database-network preserved during cleanup

## Environment-Specific Behavior

### Development Environment
```powershell
# Standard aggressive cleanup
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -CleanCache

# Features:
# ✅ Aggressive cleanup available
# ✅ Fast iteration development
# ✅ No backup requirements
# ✅ Hot reload support
```

### UAT Environment  
```powershell
# Conservative approach for testing
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# Features:
# ✅ Conservative cleanup (preserves recent data)
# ✅ Automatic backup creation
# ✅ Production-like configuration
# ✅ Enhanced monitoring
```

### Production Environment
```powershell
# Maximum safety for production
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst

# Features:
# ✅ Minimal cleanup (production-safe only)
# ✅ Mandatory backup enforcement
# ✅ Network isolation
# ✅ Full audit logging
```

## Enterprise Network Architecture

### Network Isolation by Environment
- **Development**: Isolated to development activities
- **UAT**: Separate network for testing isolation
- **Production**: Completely isolated production network

### Automatic Network Management
- Creates environment-specific networks automatically
- Configures proper subnets and gateways
- Labels networks with security policies
- Maintains network isolation between environments

## Data Protection Strategy

### Backup Automation
```powershell
# Automatic backup triggers:
# - UAT environment: Always creates backup
# - Production: Mandatory backup before operations
# - Manual: Use -BackupFirst flag

# Backup includes:
# ✅ Persistent volumes (labeled with persistent=true)
# ✅ Environment configuration files
# ✅ Docker Compose configurations
```

### Volume Protection
```powershell
# Persistent data protection:
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -PreservePersistentData -CleanCache

# Protects:
# ✅ Database volumes
# ✅ User uploaded files
# ✅ Application state data
# ✅ Configuration data
```

## Cleanup Policies by Environment

### Development (Aggressive)
- ✅ Removes unused containers
- ✅ Cleans dangling images
- ✅ Prunes unused networks
- ✅ Clears build cache
- ⚠️ Can remove volumes (unless -PreservePersistentData used)

### UAT (Conservative)
- ✅ Removes containers stopped >24 hours
- ✅ Cleans dangling images only
- ✅ Preserves recent development work
- ✅ Clears build cache safely

### Production (Minimal)
- ✅ Removes dangling images only
- ✅ Clears build cache
- ❌ Never touches containers
- ❌ Never touches volumes
- ❌ Never touches networks

## Enterprise Logging

### Log File Structure
```
logs/
├── docker-startup-2025-08-03.log          # Daily startup logs
├── docker-enterprise-2025-08-03.log       # Enterprise operations
└── backups/
    └── docker-backup-prod-2025-08-03-143022/  # Timestamped backups
```

### Log Entry Format
```
[2025-08-03 14:30:22] [INFO] Starting Enterprise Docker Management Mode
[2025-08-03 14:30:22] [SUCCESS] Network 'xy-prod-network' created successfully
[2025-08-03 14:30:23] [WARNING] Production environment should use -BackupFirst flag
```

## Migration Guide

### From Standard to Enterprise Mode

1. **No changes required** - All existing commands work
2. **Add -EnterpriseMode** flag to enable enterprise features
3. **For production** - Add -BackupFirst for mandatory backups
4. **For UAT** - Use -ConservativeClean for safer operations

### Gradual Adoption
```powershell
# Week 1: Test in development
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# Week 2: Validate in UAT  
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# Week 3: Deploy to production
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst
```

## Troubleshooting Enterprise Features

### Network Issues
```powershell
# If enterprise network creation fails, falls back to standard network
# Check logs for specific subnet conflicts

# Manual network creation:
docker network create xy-dev-network --subnet 172.20.0.0/16
```

### Backup Issues
```powershell
# If backup fails in production, operation is halted for safety
# Check backup directory permissions and disk space

# Manual backup verification:
ls backups/docker-backup-prod-*
```

### Cleanup Issues
```powershell
# Conservative cleanup protects against data loss
# Use -PreservePersistentData for additional protection

# Check what would be cleaned:
docker system df
```

## Best Practices

### Development Environment
- Use `-EnterpriseMode -CleanCache` for clean development iterations
- Enable aggressive cleanup for rapid prototyping
- No backup requirements for faster development cycles

### UAT Environment  
- Always use `-EnterpriseMode -ConservativeClean`
- Leverage automatic backups for rollback capability
- Test production procedures in UAT first

### Production Environment
- Mandatory `-EnterpriseMode -BackupFirst` for all operations
- Never use aggressive cleanup
- Monitor enterprise logs for audit compliance
- Coordinate changes with team for network isolation

## Quick Reference

### Essential Enterprise Commands
```powershell
# Development
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# UAT Testing with Conservative Cleanup
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# Production Deployment with Backup
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst

# Safe Cleanup with Data Protection
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode -CleanCache -PreservePersistentData

# Stop Services
.\start-docker.ps1 -Environment any -Profile any -Down
```

### Enterprise Status Monitoring & Validation
```powershell
# Check all enterprise networks
docker network ls | Select-String "xy-"

# Inspect network security labels
docker network inspect xy-dev-network --format "{{json .Labels}}"
docker network inspect xy-uat-network --format "{{json .Labels}}"
docker network inspect xy-prod-network --format "{{json .Labels}}"

# View enterprise container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Select-String "orderprocessing"

# Check for application errors
docker logs testappxy_orderprocessingsystem-api-https-1 | Select-String -Pattern "(ERROR|Exception|Failed)"
docker logs testappxy_orderprocessingsystem-ui-https-1 | Select-String -Pattern "(ERROR|Exception|Failed)"

# View enterprise logs
Get-Content logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log -Tail 20

# Check enterprise backups
ls backups/ | Select-Object -Last 5

# Verify database connectivity (non-Docker)
sqlcmd -S localhost,1433 -U sa -P "Admin100@" -Q "SELECT name FROM sys.databases WHERE name LIKE 'OrderProcessingSystem%'"

# Test Entity Framework migrations (non-Docker)
cd XYDataLabs.OrderProcessingSystem.API
dotnet ef database update --verbose
```

### Enterprise Environment URLs by Mode

| Environment | API URL | UI URL | Network | Security |
|-------------|---------|--------|---------|----------|
| **DEV** | https://localhost:5021/swagger | https://localhost:5023 | xy-dev-network | development |
| **UAT** | https://localhost:5031/swagger | https://localhost:5033 | xy-uat-network | testing |
| **PROD** | https://localhost:5041/swagger | https://localhost:5043 | xy-prod-network | production |
| **Local** | https://localhost:5011/swagger | https://localhost:5013 | host | local |

### Troubleshooting Enterprise Mode

#### Common Issues and Solutions
```powershell
# Issue: "Cannot index into a null array" warning
# Solution: Fixed in current version - network cleanup now handles null arrays properly

# Issue: "Image already exists" error
# Solution: Use -CleanCache flag to remove application images before rebuild

# Issue: Network not found error
# Solution: Enterprise mode automatically creates networks with proper labels

# Issue: Production backup not created
# Solution: UAT and PROD automatically create backups, use -BackupFirst for explicit backup

# Issue: Containers not healthy
# Solution: Check application logs and ensure database connectivity:
docker logs [container-name] | Select-String -Pattern "(ERROR|Exception|Failed)"
```

### Enterprise Mode vs Standard Mode Comparison

| Feature | Standard Mode | Enterprise Mode |
|---------|---------------|-----------------|
| **Networks** | Default Docker networks | Environment-specific isolated networks |
| **Cleanup** | Basic system prune | Environment-specific policies |
| **Backups** | Manual only | Automatic for UAT/PROD |
| **Logging** | Console only | File-based audit trail |
| **Security** | Basic | Security level labeling |
| **Monitoring** | Basic status | Enterprise health checks |

This enterprise enhancement maintains your existing workflow while providing the production-grade features needed for enterprise architecture compliance.
