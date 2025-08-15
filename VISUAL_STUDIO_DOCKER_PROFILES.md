# Visual Studio Launch Profiles Guide

## Overview

The API and UI projects include both **Docker** and **Non-Docker** launch profiles that allow you to start different environments directly from Visual Studio. Each profile type uses a sophisticated two-stage architecture to ensure proper environment setup.

## 🎯 Profile Types Overview

| **Profile Type** | **Purpose** | **Database** | **Ports** | **Setup Script** |
|-----------------|-------------|--------------|-----------|------------------|
| **Non-Docker** | Local development | OrderProcessingSystem_Local | 5010-5013 | `set-local-env.ps1` |
| **Docker** | Containerized environments | OrderProcessingSystem_{Env} | 5020+, 5030+, 5040+ | `start-docker.ps1` |

## 🔄 Two-Stage Launch Architecture

### Why Two Stages Are Needed

Both Docker and Non-Docker profiles use a **two-stage architecture** to ensure proper environment setup:

#### **Stage 1: Environment Setup**
- **Non-Docker**: Runs `set-local-env.ps1` to configure `.env` file with local settings
- **Docker**: Runs `start-docker.ps1` to setup containers and environment-specific configuration

#### **Stage 2: Application Launch**  
- **Non-Docker**: Calls `dotnet run --launch-profile {profile}-direct` with prepared environment
- **Docker**: Containers start with properly configured environment

### Example: Non-Docker HTTP Profile

```json
// Stage 1 Profile: Environment Setup
"http": {
  "commandName": "Executable",
  "executablePath": "powershell.exe",
  "commandLineArgs": "cd '$(SolutionDir)'; .\\set-local-env.ps1 -ProjectType API -Profile http; Start-Sleep 2; cd '.\\XYDataLabs.OrderProcessingSystem.API'; dotnet run --launch-profile http-direct",
  "launchBrowser": true,
  "launchUrl": "http://localhost:5010/swagger"
}

// Stage 2 Profile: Direct Application Launch  
"http-direct": {
  "commandName": "Project",
  "launchBrowser": false,
  "environmentVariables": {
    "SHAREDSETTINGS_PATH": "Resources/Configuration/sharedsettings.local.json"
  },
  "applicationUrl": "http://localhost:5010"
}
```

### What Happens When You Press F5:

1. **Visual Studio** calls the main profile (`http`, `https`, or `docker-*`)
2. **PowerShell script** executes to setup environment
3. **Environment configuration** updates (`.env` file, database connections)
4. **Application launches** with properly prepared environment
5. **Browser opens** to the correct URL

## 📋 Available Profiles

### Non-Docker Profiles (Local Development)

#### API Project Non-Docker Profiles
- **http**: Local development with HTTP (port 5010) → calls `http-direct`
- **https**: Local development with HTTPS (port 5011) → calls `https-direct`
- **http-direct**: Direct HTTP launch (used internally by `http` profile)
- **https-direct**: Direct HTTPS launch (used internally by `https` profile)

#### UI Project Non-Docker Profiles  
- **http**: Local development with HTTP (port 5012) → calls `http-direct`
- **https**: Local development with HTTPS (port 5013) → calls `https-direct`
- **http-direct**: Direct HTTP launch (used internally by `http` profile)
- **https-direct**: Direct HTTPS launch (used internally by `https` profile)

**Features:**
- **Database**: Uses `OrderProcessingSystem_Local` on localhost:1433
- **Configuration**: Uses `sharedsettings.local.json`
- **Environment Setup**: Automatic via `set-local-env.ps1`
- **F5 Debugging**: Full breakpoint support in Visual Studio

### Docker Profiles (Containerized Environments)

#### API Project Docker Profiles
- **docker-dev-http**: Start development environment with HTTP (port 5020)
- **docker-dev-https**: Start development environment with HTTPS (port 5021)
- **docker-uat-http**: Start UAT environment with HTTP (port 5030)
- **docker-uat-https**: Start UAT environment with HTTPS (port 5031)
- **docker-prod-http**: Start production environment with HTTP (port 5040)
- **docker-prod-https**: Start production environment with HTTPS (port 5041)

#### UI Project Docker Profiles
- **docker-dev-http**: Start development environment with HTTP (port 5022)
- **docker-dev-https**: Start development environment with HTTPS (port 5023)
- **docker-uat-http**: Start UAT environment with HTTP (port 5032)
- **docker-uat-https**: Start UAT environment with HTTPS (port 5033)
- **docker-prod-http**: Start production environment with HTTP (port 5042)
- **docker-prod-https**: Start production environment with HTTPS (port 5043)

**Features:**
- **Databases**: Environment-specific (`OrderProcessingSystem_Dev`, `OrderProcessingSystem_UAT`, `OrderProcessingSystem_Prod`)
- **Configuration**: Uses environment-specific `sharedsettings.{env}.json`
- **Environment Setup**: Automatic via `start-docker.ps1 -Environment {env} -Profile {profile} -CleanCache`
- **Container Debugging**: Attach to process debugging available

## How to Use

### From Visual Studio

1. **Select Launch Profile**:
   - In Visual Studio, click the dropdown next to the "Start" button
   - Choose one of the Docker profiles (e.g., "docker-dev-http")

2. **Start Environment**:
   - Click "Start" or press F5
   - Visual Studio will execute the PowerShell script
   - Browser will automatically open to the correct URL

3. **Monitor Progress**:
   - Watch the Output window for Docker startup progress
   - Containers will start with clean cache for reliable environment

### Profile Details

Each Docker profile includes:
- **Executable**: `powershell.exe`
- **Arguments**: `.\start-docker.ps1 -Environment {env} -Profile {profile} -CleanCache`
- **Working Directory**: Solution root directory
- **Auto Browser**: Opens to correct URL with proper port
- **Clean Cache**: Ensures fresh container startup

### Port Mapping

| Environment | API HTTP | API HTTPS | UI HTTP | UI HTTPS |
|-------------|----------|-----------|---------|----------|
| **Local (Non-Docker)** | 5010 | 5011 | 5012 | 5013 |
| **dev (Docker)**     | 5020     | 5021      | 5022    | 5023     |
| **uat (Docker)**     | 5030     | 5031      | 5032    | 5033     |
| **prod (Docker)**    | 5040     | 5041      | 5042    | 5043     |

## 🔧 Troubleshooting

### Why Do We Need Two Profiles (e.g., `http` and `http-direct`)?

**The Problem**: Visual Studio launch profiles cannot dynamically update configuration files before starting the application.

**The Solution**: Two-stage architecture
1. **Stage 1 (`http`)**: Runs PowerShell script to setup environment
2. **Stage 2 (`http-direct`)**: Starts application with prepared environment

**Without this approach**:
- ❌ Wrong database connections (Dev vs Local)
- ❌ Port conflicts between Docker and non-Docker
- ❌ Static configuration that doesn't adapt

**With two-stage approach**:
- ✅ Dynamic environment setup
- ✅ Database isolation (Local vs Dev vs UAT vs Prod)
- ✅ Correct port allocation
- ✅ Clean separation between Docker and non-Docker

### Common Issues

#### "Profile Not Found" Error
```
Error: Could not find launch profile 'http-direct'
```
**Solution**: The `http-direct` profiles are internal - only select `http`, `https`, or `docker-*` profiles from the dropdown.

#### Wrong Database Connection  
```
Error: Cannot connect to OrderProcessingSystem_Dev
```
**Solution**: 
- For **non-Docker**: Should use `OrderProcessingSystem_Local`
- For **Docker**: Should use `OrderProcessingSystem_{Environment}`
- Check that the correct profile was selected (not mixed Docker/non-Docker)

#### Port Already in Use
```
Error: Port 5010 is already in use
```
**Solution**: 
- Stop any running instances
- For Docker: `.\start-docker.ps1 -Environment dev -Profile http -Down`
- For non-Docker: Stop debugging in Visual Studio

#### PowerShell Execution Policy Error
```
Error: Execution of scripts is disabled
```
**Solution**: 
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Best Practices

1. **Use the Right Profile Type**:
   - **Local development/debugging**: Use `http` or `https` profiles
   - **Container testing**: Use `docker-dev-*` profiles
   - **UAT testing**: Use `docker-uat-*` profiles

2. **Environment Isolation**:
   - Each profile type uses its own database
   - No conflicts between development modes
   - Safe to switch between profiles

3. **Debugging**:
   - **Non-Docker**: Full F5 debugging with breakpoints
   - **Docker**: Use "Attach to Process" for container debugging

## 📚 Related Documentation

- **DOCKER_COMPREHENSIVE_GUIDE.md**: Complete Docker setup and troubleshooting
- **NON_DOCKER_TESTING_CHECKLIST.md**: Step-by-step testing for non-Docker profiles
- **README.md**: Quick start guide for all development scenarios

## Examples

### Development Workflow
1. Select "docker-dev-http" from API project
2. Press F5 to start development Docker environment
3. Browser opens to http://localhost:5020/swagger
4. UI automatically available at http://localhost:5022

### UAT Testing
1. Select "docker-uat-https" from API project
2. Start environment for secure UAT testing
3. Browser opens to https://localhost:5031/swagger
4. UI available at https://localhost:5033

### Production Testing
1. Select "docker-prod-http" from API project
2. Start production-like environment
3. Browser opens to http://localhost:5040/swagger
4. UI available at http://localhost:5042

## Benefits

### Developer Experience
- **One-Click Start**: Launch complete Docker environment from Visual Studio
- **No Terminal Required**: No need to manually run PowerShell commands
- **Auto Browser**: Automatically opens to correct URL
- **Clean Environment**: Each start includes cache cleanup for reliability

### Environment Isolation
- **Unique Ports**: Each environment uses dedicated ports
- **Simultaneous Environments**: Run multiple environments simultaneously
- **Proper Configuration**: Each environment uses its specific settings

### Consistency
- **Same Command**: Uses the same `start-docker.ps1` script as manual execution
- **Enterprise Features**: Full access to enterprise mode and cleanup options
- **Standardized**: Consistent with existing Docker workflow

## Troubleshooting

### Profile Not Visible
- Ensure you've saved the launchSettings.json file
- Restart Visual Studio if profiles don't appear
- Check JSON syntax in launchSettings.json

### PowerShell Execution Policy
If you get execution policy errors:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Working Directory Issues
- Profiles use `$(SolutionDir)` to ensure correct working directory
- Script assumes it's in the solution root directory
- Verify `start-docker.ps1` exists in solution root

### Port Conflicts
- Check if ports are already in use
- Stop other Docker containers if needed
- Use different environment if ports conflict

## Advanced Usage

### Custom Parameters
To add custom parameters (like `-EnterpriseMode`), modify the `commandLineArgs` in launchSettings.json:
```json
"commandLineArgs": "-Command \"cd '$(SolutionDir)'; .\\start-docker.ps1 -Environment dev -Profile http -CleanCache -EnterpriseMode\""
```

### Debugging
- Check Visual Studio Output window for execution details
- Monitor Docker Desktop for container status
- Use PowerShell terminal for detailed troubleshooting

## Related Documentation

- **DOCKER_COMPREHENSIVE_GUIDE.md**: Complete Docker usage guide
- **DOCKER_PORT_ALLOCATION.md**: Port allocation scheme details
- **start-docker.ps1**: PowerShell script documentation
