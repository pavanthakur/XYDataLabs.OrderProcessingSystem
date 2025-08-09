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

### Essential Commands
```powershell
# Development
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# UAT Testing
.\start-docker.ps1 -Environment uat -Profile all -EnterpriseMode -ConservativeClean

# Production Deployment
.\start-docker.ps1 -Environment prod -Profile all -EnterpriseMode -BackupFirst

# Safe Cleanup
.\start-docker.ps1 -Environment any -Profile any -EnterpriseMode -PreservePersistentData -CleanCache

# Stop Services
.\start-docker.ps1 -Environment any -Profile any -Down
```

### Status Monitoring
```powershell
# View logs
docker-compose -f docker-compose.{env}.yml logs -f

# Check networks
docker network ls | grep xy-

# Verify backups
ls backups/

# Check enterprise logs
Get-Content logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log -Tail 20
```

This enterprise enhancement maintains your existing workflow while providing the production-grade features needed for enterprise architecture compliance.
