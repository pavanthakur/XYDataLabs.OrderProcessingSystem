# Docker Startup Guide

## Enhanced start-docker.ps1 Script

The `start-docker.ps1` script has been enhanced with automatic prerequisite management and cache cleanup capabilities.

## Prerequisites

The script now automatically handles these prerequisites:

### 1. Docker Network (Auto-managed)
- **Network Name**: `xynetwork`
- **Auto-creation**: The script automatically creates the network if it doesn't exist
- **Manual creation**: `docker network create xynetwork`

### 2. SSL Certificates (Required for HTTPS)
- **Location**: `Resources/Certificates/aspnetapp.pfx`
- **Required for**: HTTPS profiles
- **Note**: Ensure certificates are present before running HTTPS profiles

### 3. Environment Configuration Files
- **Development**: `sharedsettings.dev.json`
- **UAT**: `sharedsettings.uat.json` 
- **Production**: `sharedsettings.prod.json`

## Usage Examples

### Basic Startup
```powershell
# Start development environment with HTTP
.\start-docker.ps1 -Environment dev -Profile http

# Start UAT environment with HTTPS
.\start-docker.ps1 -Environment uat -Profile https

# Start production environment with both HTTP and HTTPS
.\start-docker.ps1 -Environment prod -Profile all
```

### With Cache Cleanup
```powershell
# Clean Docker cache and start fresh
.\start-docker.ps1 -Environment dev -Profile https -CleanCache

# This is equivalent to running:
# docker system prune -f --volumes
# .\start-docker.ps1 -Environment dev -Profile https
```

### Stop Services
```powershell
# Stop specific environment and profile
.\start-docker.ps1 -Environment dev -Profile http -Down

# Stop all profiles for an environment
.\start-docker.ps1 -Environment dev -Profile all -Down
```

## Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Environment` | `dev`, `uat`, `prod` | `dev` | Target environment |
| `-Profile` | `http`, `https`, `all` | `http` | Services to start |
| `-CleanCache` | Switch | `false` | Clean Docker cache before startup |
| `-Down` | Switch | `false` | Stop services instead of starting |
| `-SharedSettingsPath` | Path | `sharedsettings.{env}.json` | Custom settings file path |
| `-EnvFilePath` | Path | `.env` | Custom .env file path |

## What the Script Does

### 1. Prerequisite Checks
- ✅ Verifies Docker network exists (creates if missing)
- ✅ Validates environment configuration files
- ✅ Extracts and validates port configurations

### 2. Cache Management (Optional)
- 🧹 Removes unused containers, networks, and images
- 🧹 Clears build cache
- 🧹 Removes anonymous volumes
- 📊 Reports space reclaimed

### 3. Environment Setup
- 📝 Generates `.env` file with environment-specific ports
- 🔧 Configures Docker Compose with correct profile
- 🚀 Starts containers in detached mode

### 4. Status Reporting
- 📋 Shows container status and port mappings
- 🌐 Displays application URLs
- 💡 Provides environment-specific guidance
- 🎯 Shows quick command references

## Troubleshooting

### Network Issues
If you encounter network-related errors:
```powershell
# Manually create the network
docker network create xynetwork

# Or use the script with cache cleanup
.\start-docker.ps1 -Environment dev -Profile https -CleanCache
```

### Cache Issues
If builds are failing or behaving unexpectedly:
```powershell
# Clean cache and restart
.\start-docker.ps1 -Environment dev -Profile https -CleanCache
```

### Port Conflicts
If ports are already in use:
1. Check the environment-specific `sharedsettings.{env}.json` file
2. Modify port numbers as needed
3. Restart the script

### SSL Certificate Issues (HTTPS)
Ensure certificates are present:
```powershell
# Check certificate exists
Test-Path "Resources/Certificates/aspnetapp.pfx"

# If missing, generate new certificates (example)
dotnet dev-certs https -ep Resources/Certificates/aspnetapp.pfx -p YourPassword
```

## Environment-Specific Features

### Development (`dev`)
- Hot reload enabled
- Source code mounted for live changes
- Debug configuration active
- Minimal resource constraints

### UAT (`uat`)
- Production-like configuration
- Enhanced monitoring and health checks
- Resource limits applied
- Testing-optimized settings

### Production (`prod`)
- High availability configuration
- Resource limits and monitoring
- Performance optimizations
- Security hardening

## Quick Command Reference

```powershell
# Most common operations
.\start-docker.ps1 -Environment dev -Profile http        # Dev HTTP
.\start-docker.ps1 -Environment dev -Profile https       # Dev HTTPS  
.\start-docker.ps1 -Environment dev -Profile https -CleanCache  # Clean start
.\start-docker.ps1 -Environment dev -Profile http -Down  # Stop services

# Monitoring
docker-compose -f docker-compose.dev.yml logs -f         # View logs
docker ps                                                # Container status
docker network ls                                        # Network status
```

## Integration with Visual Studio

The enhanced script works seamlessly with Visual Studio's Docker Compose project:
- VS uses `docker-compose.dev.yml` as the base file
- Script handles network prerequisites automatically
- Cache cleanup resolves build issues
- Environment switching maintains consistency

## Best Practices

1. **Use CleanCache for troubleshooting**: When encountering build or startup issues
2. **Test environments in order**: dev → uat → prod
3. **Verify prerequisites**: Especially SSL certificates for HTTPS
4. **Monitor resource usage**: Especially in production environment
5. **Use environment-specific configurations**: Don't share settings between environments
