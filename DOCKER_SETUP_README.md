# XY Data Labs Order Processing System - Docker Setup Guide

## Overview
This guide provides step-by-step instructions to build and run the Order Processing System using Docker containers.

## Prerequisites
- Docker Desktop installed and running
- Docker Compose v2.0+ installed
- Windows PowerShell or Command Prompt
- At least 4GB RAM available for Docker

## Project Structure
```
XYDataLabs.OrderProcessingSystem/
├── docker-compose.dev.yml
├── docker-compose.uat.yml  
├── docker-compose.prod.yml
├── sharedsettings.dev.json
├── sharedsettings.uat.json
├── sharedsettings.prod.json
├── XYDataLabs.OrderProcessingSystem.API/
│   └── Dockerfile
├── XYDataLabs.OrderProcessingSystem.UI/
│   └── Dockerfile
└── [other project folders]
```

## Step-by-Step Docker Commands

### Step 1: Navigate to Project Directory
```powershell
cd q:\GIT\TestAppXY_OrderProcessingSystem
```

**Troubleshooting:**
- If path doesn't exist, verify the project location
- Use `ls` or `dir` to list current directory contents
- Ensure you're in the root directory containing `docker-compose.yml`

### Step 2: Verify Docker Compose Configuration
```powershell
docker-compose config
```

**Expected Output:** Should display the parsed docker-compose configuration without errors.

**Troubleshooting:**
- If "file not found": Ensure `docker-compose.yml` exists in current directory
- If syntax errors: Check YAML formatting (spaces, not tabs)
- If service errors: Verify Dockerfile paths in docker-compose.yml

### Step 3: Check Available Profiles
```powershell
docker-compose config --profiles
```

**Expected Output:** Should show available profiles (http, https, etc.)

### Step 4: Build Docker Images
```powershell
# Build all images for the http profile
docker-compose --profile http build

# Alternative: Build with no cache (if you need clean build)
docker-compose --profile http build --no-cache
```

**Expected Output:**
- Building process for API and UI services
- Successful completion messages for both images

**Troubleshooting:**
- **Build fails with "context" error**: Check Dockerfile paths in docker-compose.yml
- **"No such file" errors**: Verify project file references in Dockerfiles
- **NuGet restore fails**: Check internet connection and NuGet sources
- **Memory issues**: Increase Docker Desktop memory allocation
- **Long build time**: First build downloads base images (normal)

**Common Build Issues:**
```powershell
# Check Docker daemon status
docker version

# Clean up Docker system if needed
docker system prune -f

# Remove specific images if rebuild needed
docker rmi xydatalabs-orderprocessingsystem-api
docker rmi xydatalabs-orderprocessingsystem-ui
```

### Step 5: Start Services
```powershell
# Start services in detached mode (background)
docker-compose --profile http up -d

# Alternative: Start with logs visible (foreground)
docker-compose --profile http up
```

**Expected Output:**
- Network creation
- Container creation and startup
- Health check confirmations

**Troubleshooting:**
- **Port conflicts**: Check if ports 5000/5002 are already in use
- **Container exits immediately**: Check container logs (see Step 6)
- **Network issues**: Ensure Docker daemon is running
- **Permission issues**: Run PowerShell as Administrator

**Port Conflict Resolution:**
```powershell
# Check what's using the ports
netstat -ano | findstr :5000
netstat -ano | findstr :5002

# Kill process if needed (replace PID with actual process ID)
taskkill /PID [PID] /F
```

### Step 6: Verify Services Status
```powershell
# Check container status
docker-compose ps

# Check detailed container information
docker ps -a
```

**Expected Output:**
```
NAME                                    STATUS                    PORTS
testappxy_orderprocessingsystem-api-1   Up X minutes (healthy)   0.0.0.0:5000->8080/tcp
testappxy_orderprocessingsystem-ui-1    Up X minutes (healthy)   0.0.0.0:5002->8080/tcp
```

**Troubleshooting Status Issues:**
```powershell
# View container logs
docker-compose logs api
docker-compose logs ui

# Follow logs in real-time
docker-compose logs -f api
docker-compose logs -f ui

# Check specific container logs
docker logs testappxy_orderprocessingsystem-api-1
docker logs testappxy_orderprocessingsystem-ui-1
```

### Step 7: Test Application Access
```powershell
# Test API endpoint
curl http://localhost:5000/health
# Or in PowerShell
Invoke-WebRequest -Uri http://localhost:5000 -Method GET

# Test UI
# Open browser to http://localhost:5002
```

**Expected Results:**
- API: Should return health status or API response
- UI: Should display the web application interface

### Step 8: Verify Health Checks
```powershell
# Check health status of all containers
docker-compose ps

# Check detailed health status
docker inspect testappxy_orderprocessingsystem-api-1 --format='{{.State.Health.Status}}'
docker inspect testappxy_orderprocessingsystem-ui-1 --format='{{.State.Health.Status}}'

# View health check logs
docker inspect testappxy_orderprocessingsystem-api-1 --format='{{range .State.Health.Log}}{{.Output}}{{end}}'
docker inspect testappxy_orderprocessingsystem-ui-1 --format='{{range .State.Health.Log}}{{.Output}}{{end}}'

# Manual health check commands
curl -f http://localhost:5000/health || echo "API health check failed"
curl -f http://localhost:5002/health || echo "UI health check failed"
```

**Expected Health Check Results:**
- Status should show "healthy" for both containers
- Health check endpoints should return 200 OK status
- No error messages in health check logs

## Service URLs
- **Web Application (UI)**: http://localhost:5002
- **API Service**: http://localhost:5000
- **API Documentation**: http://localhost:5000/swagger (if configured)

## Management Commands

### Health Check Commands
```powershell
# Quick health status check
docker-compose ps --format table

# Detailed health information
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Wait for healthy status (timeout after 60 seconds)
timeout 60 powershell -command "while ((docker inspect testappxy_orderprocessingsystem-api-1 --format='{{.State.Health.Status}}') -ne 'healthy') { Start-Sleep 5; Write-Host 'Waiting for API to be healthy...' }"
timeout 60 powershell -command "while ((docker inspect testappxy_orderprocessingsystem-ui-1 --format='{{.State.Health.Status}}') -ne 'healthy') { Start-Sleep 5; Write-Host 'Waiting for UI to be healthy...' }"

# Test all endpoints
Write-Host "Testing API health..."
Invoke-WebRequest -Uri http://localhost:5000/health -Method GET -TimeoutSec 10
Write-Host "Testing UI health..."
Invoke-WebRequest -Uri http://localhost:5002/health -Method GET -TimeoutSec 10
```

### View Logs
```powershell
# All services
docker-compose logs

# Specific service
docker-compose logs api
docker-compose logs ui

# Follow logs (real-time)
docker-compose logs -f

# Last 50 lines
docker-compose logs --tail=50
```

### Restart Services
```powershell
# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart api
docker-compose restart ui
```

### Stop Services
```powershell
# Stop all services (containers remain)
docker-compose stop

# Stop and remove containers, networks
docker-compose --profile http down

# Stop and remove everything including volumes
docker-compose --profile http down -v
```

### Rebuild and Restart
```powershell
# Stop, rebuild, and start
docker-compose --profile http down
docker-compose --profile http build
docker-compose --profile http up -d
```

## Troubleshooting Common Issues

### 1. Build Failures
```powershell
# Check Docker daemon
docker info

# Clean build cache
docker builder prune

# Rebuild without cache
docker-compose --profile http build --no-cache
```

### 2. Container Won't Start
```powershell
# Check container logs
docker-compose logs [service-name]

# Check container details
docker inspect [container-name]

# Run container interactively for debugging
docker run -it xydatalabs-orderprocessingsystem-api /bin/bash
```

### 3. Port Issues
```powershell
# Check port usage
netstat -ano | findstr :5000
netstat -ano | findstr :5002

# Use different ports (modify docker-compose.yml)
# Change ports: "5001:8080" instead of "5000:8080"
```

### 4. Network Issues
```powershell
# List Docker networks
docker network ls

# Inspect network
docker network inspect testappxy_orderprocessingsystem_xynetwork

# Recreate network
docker-compose down
docker-compose --profile http up -d
```

### 5. Performance Issues
```powershell
# Check resource usage
docker stats

# Check system resources
docker system df

# Clean up unused resources
docker system prune -a
```

### 6. Health Check Failures
```powershell
# Check if health check endpoints are configured
docker exec testappxy_orderprocessingsystem-api-1 curl -f http://localhost:8080/health
docker exec testappxy_orderprocessingsystem-ui-1 curl -f http://localhost:8080/health

# View health check configuration
docker inspect testappxy_orderprocessingsystem-api-1 --format='{{.Config.Healthcheck}}'
docker inspect testappxy_orderprocessingsystem-ui-1 --format='{{.Config.Healthcheck}}'

# Manual health check test
docker exec testappxy_orderprocessingsystem-api-1 /bin/bash -c "curl -f http://localhost:8080/health && echo 'API Health OK' || echo 'API Health FAILED'"
docker exec testappxy_orderprocessingsystem-ui-1 /bin/bash -c "curl -f http://localhost:8080/health && echo 'UI Health OK' || echo 'UI Health FAILED'"
```

## Development Workflow

### Hot Reload Development
The containers are configured with `dotnet watch` for automatic code reloading:

1. Make code changes in your IDE
2. Save files
3. Application automatically reloads in containers
4. Refresh browser to see changes

### Debugging
```powershell
# Attach to running container
docker exec -it testappxy_orderprocessingsystem-api-1 /bin/bash

# View application files in container
docker exec testappxy_orderprocessingsystem-api-1 ls -la /app
```

## Environment Variables
Key environment variables (configured in docker-compose.yml):
- `ASPNETCORE_ENVIRONMENT=Development`
- `ASPNETCORE_URLS=http://+:8080`

## Health Checks
Both services include health checks:
- **Health Check Command**: `curl -f http://localhost:8080/health || exit 1`
- **Interval**: 30 seconds
- **Timeout**: 10 seconds
- **Retries**: 3
- **Start Period**: 40 seconds

**Health Check Verification:**
```powershell
# Verify health check configuration
docker-compose config | grep -A 10 healthcheck

# Monitor health status in real-time
watch "docker-compose ps"

# Check health endpoint directly
curl http://localhost:5000/health
curl http://localhost:5002/health
```

## Quick Reference Commands

```powershell
# Start everything
docker-compose --profile http up -d

# Wait for healthy status
docker-compose ps --format table

# Quick health check
curl http://localhost:5000/health && curl http://localhost:5002/health

# View status
docker-compose ps

# View logs
docker-compose logs -f

# Stop everything
docker-compose --profile http down

# Clean restart
docker-compose --profile http down && docker-compose --profile http up -d

# Environment-specific startup (recommended)
.\start-docker.ps1 -Environment dev -Profile http
.\start-docker.ps1 -Environment uat -Profile https  
.\start-docker.ps1 -Environment prod -Profile https -CleanCache

# Emergency cleanup
docker-compose down && docker system prune -f

# Full health verification
docker inspect testappxy_orderprocessingsystem-api-1 --format='{{.State.Health.Status}}' && docker inspect testappxy_orderprocessingsystem-ui-1 --format='{{.State.Health.Status}}'
```

## Support Information
- **Created**: July 29, 2025
- **Docker Compose Version**: 2.0+
- **Base Images**: mcr.microsoft.com/dotnet/aspnet:8.0, mcr.microsoft.com/dotnet/sdk:8.0
- **Supported Platforms**: Windows, Linux, macOS

For additional help, check container logs and Docker Desktop dashboard.
