# Configure App Environment - Quick Reference Guide

## Overview

The `configure-app-environment.ps1` script configures Azure App Service environment variables (ASPNETCORE_ENVIRONMENT) for the OrderProcessingSystem applications.

## Script Location

```
./Resources/Azure-Deployment/configure-app-environment.ps1
```

## Usage

### Basic Syntax

```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment <env> [-BaseName <name>] [-GitHubOwner <owner>]
```

### Parameters

| Parameter | Required | Default Value | Valid Values | Description |
|-----------|----------|---------------|--------------|-------------|
| `-Environment` | Yes | - | `dev`, `staging`, `prod` | Target environment to configure |
| `-BaseName` | No | `orderprocessing` | Any string | Base name for Azure resources |
| `-GitHubOwner` | No | `pavanthakur` | Any string | GitHub repository owner |

## Examples

### Example 1: Configure Dev Environment (Default Values)
```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev
```

### Example 2: Configure Dev with Explicit Parameters (As Requested)
```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev -BaseName orderprocessing -GitHubOwner pavanthakur
```

### Example 3: Configure Staging Environment
```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment staging -BaseName orderprocessing -GitHubOwner pavanthakur
```

### Example 4: Configure Production Environment
```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment prod -BaseName orderprocessing -GitHubOwner pavanthakur
```

## What the Script Does

### For Dev Environment
Configures the following Azure resources:

**Resource Group**: `rg-orderprocessing-dev`

**API App Service**: `pavanthakur-orderprocessing-api-xyapp-dev`
- Sets: `ASPNETCORE_ENVIRONMENT=Development`
- URL: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net

**UI App Service**: `pavanthakur-orderprocessing-ui-xyapp-dev`
- Sets: `ASPNETCORE_ENVIRONMENT=Development`
- URL: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

### For Staging Environment
**Resource Group**: `rg-orderprocessing-stg`

**API App Service**: `pavanthakur-orderprocessing-api-xyapp-stg`
- Sets: `ASPNETCORE_ENVIRONMENT=Staging`

**UI App Service**: `pavanthakur-orderprocessing-ui-xyapp-stg`
- Sets: `ASPNETCORE_ENVIRONMENT=Staging`

### For Production Environment
**Resource Group**: `rg-orderprocessing-prod`

**API App Service**: `pavanthakur-orderprocessing-api-xyapp-prod`
- Sets: `ASPNETCORE_ENVIRONMENT=Production`

**UI App Service**: `pavanthakur-orderprocessing-ui-xyapp-prod`
- Sets: `ASPNETCORE_ENVIRONMENT=Production`

## Prerequisites

### 1. Azure CLI Installed
```bash
# Check installation
az --version
```

### 2. Azure Authentication
```bash
# Interactive login
az login

# Or service principal login
az login --service-principal -u <app-id> -p <password-or-cert> --tenant <tenant>
```

### 3. Azure Resources Must Exist
The script requires these resources to be already provisioned:
- Resource Group
- API App Service
- UI App Service

**To provision these resources**, run the bootstrap script first:
```powershell
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -Environment dev -BaseName orderprocessing -GitHubOwner pavanthakur
```

### 4. Required Azure Permissions
Your Azure account needs:
- Read access to the resource group
- Write access to App Service configuration settings

## Execution Flow

The script executes these steps:

```
[1/5] Verifying Azure CLI login...
      ↓
[2/5] Verifying resource group...
      ↓
[3/5] Configuring API App Service environment...
      ↓
[4/5] Configuring UI App Service environment...
      ↓
[5/5] Verifying configuration...
      ↓
✅ Success
```

## Troubleshooting

### Error: "Not logged in to Azure CLI"
**Solution**: Run `az login` before executing the script

### Error: "Resource group does not exist"
**Solution**: Run the bootstrap script first:
```powershell
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -Environment dev
```

### Error: "Failed to configure API/UI app settings"
**Possible causes**:
1. App Service doesn't exist - run bootstrap script
2. Insufficient permissions - verify Azure RBAC roles
3. Wrong resource names - check BaseName and GitHubOwner parameters

### Verification Failed (Settings Don't Match)
**Solution**: 
1. Check for typos in environment names
2. Verify the App Service is running
3. Try configuring again

## Verification

After successful execution, verify the configuration:

### Check App Settings via Azure CLI
```bash
# API App
az webapp config appsettings list \
  --resource-group rg-orderprocessing-dev \
  --name pavanthakur-orderprocessing-api-xyapp-dev \
  --query "[?name=='ASPNETCORE_ENVIRONMENT']"

# UI App
az webapp config appsettings list \
  --resource-group rg-orderprocessing-dev \
  --name pavanthakur-orderprocessing-ui-xyapp-dev \
  --query "[?name=='ASPNETCORE_ENVIRONMENT']"
```

### Test Endpoints
```bash
# API (Swagger)
curl https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger

# UI (Home page)
curl https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net/
```

## Integration with Other Scripts

### Complete Deployment Workflow

1. **Bootstrap Infrastructure**
   ```powershell
   ./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -Environment dev
   ```

2. **Provision Database**
   ```powershell
   ./Resources/Azure-Deployment/provision-azure-sql.ps1 -Environment dev
   ```

3. **Configure App Environment** (This Script)
   ```powershell
   ./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev
   ```

4. **Setup Application Insights**
   ```powershell
   ./Resources/Azure-Deployment/setup-appinsights-dev.ps1 -Environment dev
   ```

5. **Run Database Migrations**
   ```powershell
   ./Resources/Azure-Deployment/run-database-migrations.ps1 -Environment dev
   ```

6. **Deploy Application Code**
   - Use GitHub Actions workflows or manual deployment

## Related Documentation

- **Main Deployment Guide**: `Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md`
- **Bootstrap Script**: `./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`
- **Test End-to-End**: `./Resources/Azure-Deployment/test-enterprise-deployment.ps1`

## Quick Commands

```powershell
# From repository root

# Configure dev environment
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev -BaseName orderprocessing -GitHubOwner pavanthakur

# Check current configuration
az webapp config appsettings list --resource-group rg-orderprocessing-dev --name pavanthakur-orderprocessing-api-xyapp-dev

# Verify login
az account show

# List all environments
az webapp list --query "[?contains(name, 'orderprocessing')].{Name:name, ResourceGroup:resourceGroup, State:state}" -o table
```

## Notes

- The script is idempotent - safe to run multiple times
- Changes take effect immediately (no App Service restart required)
- Environment variables set here override any default values
- ASPNETCORE_ENVIRONMENT affects:
  - Configuration file loading (appsettings.{Environment}.json)
  - Error handling behavior
  - Logging verbosity
  - Developer exception pages

## Success Indicators

When the script completes successfully, you should see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ APP SERVICE ENVIRONMENT CONFIGURED SUCCESSFULLY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment Configuration Complete:
  API App:  https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
  UI App:   https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net
```
