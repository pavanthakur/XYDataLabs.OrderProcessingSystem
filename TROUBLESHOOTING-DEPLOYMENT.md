# Troubleshooting Guide: API and UI Deployment Issues

## Problem Summary

After running the Azure Bootstrap workflow, the API and UI applications were not accessible at their Azure App Service URLs:
- **API**: https://{github-owner}-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **UI**: https://{github-owner}-orderprocessing-ui-xyapp-dev.azurewebsites.net/

> **Note**: Replace `{github-owner}` with your GitHub username (e.g., `pavanthakur`)

Additionally, no logs were appearing in Application Insights.

## Root Cause Analysis

### Issue 1: No Application Code Deployed
**Status**: ✅ IDENTIFIED

The Azure Bootstrap workflow (run #19641459307) successfully created the Azure infrastructure:
- Resource Group
- App Service Plan
- API Web App (empty)
- UI Web App (empty)
- Azure SQL Database
- Application Insights

However, **no application code was deployed** to the App Services. The bootstrap only provisions infrastructure; it does not deploy code.

### Issue 2: Deployment Workflows Not Triggered
**Status**: ✅ IDENTIFIED

The deployment workflows (`deploy-api-to-azure.yml` and `deploy-ui-to-azure.yml`) only trigger under these conditions:
1. Push to `main`, `staging`, or `dev` branches with changes to specific paths:
   - API paths: `XYDataLabs.OrderProcessingSystem.API/**`, `Application/**`, `Domain/**`, `Infrastructure/**`, `Utilities/**`
   - UI paths: `XYDataLabs.OrderProcessingSystem.UI/**`, `Application/**`, `Domain/**`, `Infrastructure/**`, `Utilities/**`
2. Manual `workflow_dispatch` trigger

Since the bootstrap ran without subsequent code changes to these paths, the deployments were never triggered.

### Issue 3: Environment Variable Configuration
**Status**: ✅ FIXED

Azure App Services need the `ASPNETCORE_ENVIRONMENT` variable set correctly:
- For `dev` branch → `ASPNETCORE_ENVIRONMENT=Development`
- For `staging` branch → `ASPNETCORE_ENVIRONMENT=Staging`
- For `prod` branch → `ASPNETCORE_ENVIRONMENT=Production`

The application code maps these to internal environment names:
```csharp
var environmentName = builder.Environment.EnvironmentName switch
{
    "Development" => Constants.Environments.Dev,    // Maps to "dev"
    "Staging" => Constants.Environments.Uat,        // Maps to "uat"
    "Production" => Constants.Environments.Production, // Maps to "prod"
    _ => Constants.Environments.Dev
};
```

## Solutions Implemented

### Solution 1: Configure App Service Environment Variables
**File**: `Resources/Azure-Deployment/configure-app-environment.ps1`

A new PowerShell script was created to configure `ASPNETCORE_ENVIRONMENT` on Azure App Services:

```powershell
./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev
```

This script:
1. Verifies Azure CLI authentication
2. Confirms resource group existence
3. Sets `ASPNETCORE_ENVIRONMENT=Development` on API App Service
4. Sets `ASPNETCORE_ENVIRONMENT=Development` on UI App Service
5. Verifies the configuration was applied successfully

### Solution 2: Integrate Environment Configuration into Bootstrap
**File**: `.github/workflows/azure-bootstrap.yml`

Added a new step to the bootstrap workflow that automatically runs after Application Insights verification:

```yaml
- name: Configure App Service Environment
  if: success()
  run: |
    ./Resources/Azure-Deployment/configure-app-environment.ps1 -Environment dev -BaseName orderprocessing -GitHubOwner pavanthakur
```

This ensures environment variables are always configured correctly after bootstrap completes.

### Solution 3: Trigger Deployments
**Files**: 
- `XYDataLabs.OrderProcessingSystem.API/Program.cs`
- `XYDataLabs.OrderProcessingSystem.UI/Program.cs`

Updated comments in both Program.cs files to trigger the deployment workflows:

```csharp
// Azure App Service Deployment - Fix for Application Not Starting
// Deployment Fix: Trigger [API|UI] deployment to Azure App Service (dev environment)
// This deployment ensures the application is properly deployed with Application Insights telemetry
```

These changes will trigger the GitHub Actions workflows when merged to the `dev` branch.

## Deployment Process

### Automatic Deployment (Recommended)
1. **Merge to dev branch**: When this PR is merged to `dev`:
   - `deploy-api-to-azure.yml` will trigger automatically
   - `deploy-ui-to-azure.yml` will trigger automatically
   
2. **Monitor workflows**: Check GitHub Actions for deployment status

3. **Verify applications**:
   - API: https://{github-owner}-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
   - UI: https://{github-owner}-orderprocessing-ui-xyapp-dev.azurewebsites.net/

### Manual Deployment (Alternative)
If automatic deployment doesn't work, manually trigger the workflows:

1. Go to Actions tab in GitHub
2. Select "Deploy API to Azure App Service"
3. Click "Run workflow" → Select `dev` branch → Run
4. Repeat for "Deploy UI to Azure App Service"

## Verification Steps

### 1. Check App Service Status
```powershell
# Check if apps are running (replace {github-owner} with your username)
az webapp show --resource-group rg-orderprocessing-dev --name {github-owner}-orderprocessing-api-xyapp-dev --query "state"
az webapp show --resource-group rg-orderprocessing-dev --name {github-owner}-orderprocessing-ui-xyapp-dev --query "state"
```

### 2. Verify Environment Variables
```powershell
# Check environment variables (replace {github-owner} with your username)
az webapp config appsettings list --resource-group rg-orderprocessing-dev --name {github-owner}-orderprocessing-api-xyapp-dev --query "[?name=='ASPNETCORE_ENVIRONMENT']"
az webapp config appsettings list --resource-group rg-orderprocessing-dev --name {github-owner}-orderprocessing-ui-xyapp-dev --query "[?name=='ASPNETCORE_ENVIRONMENT']"
```

### 3. Test Endpoints
```powershell
# Test API (replace {github-owner} with your username)
Invoke-WebRequest -Uri "https://{github-owner}-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger" -Method Get

# Test UI (replace {github-owner} with your username)
Invoke-WebRequest -Uri "https://{github-owner}-orderprocessing-ui-xyapp-dev.azurewebsites.net/" -Method Get
```

### 4. Check Application Insights
After applications are deployed and receiving traffic:

1. Go to Azure Portal
2. Navigate to Application Insights: `ai-orderprocessing-dev`
3. Check "Logs" for telemetry
4. Check "Failures" for error logs
5. Check "Performance" for request metrics

## Expected Behavior After Fix

### API Application
- ✅ Swagger UI accessible at `/swagger`
- ✅ API endpoints responding with data
- ✅ Application Insights capturing telemetry
- ✅ Database connection working
- ✅ Serilog logging to console and Application Insights

### UI Application
- ✅ Home page accessible at root URL
- ✅ Razor pages rendering correctly
- ✅ Can communicate with API
- ✅ Application Insights capturing telemetry
- ✅ Serilog logging to console and Application Insights

### Application Insights
- ✅ Request telemetry appearing in Logs
- ✅ Dependency tracking (SQL, HTTP)
- ✅ Exception logging
- ✅ Custom events and metrics
- ✅ Performance monitoring

## Common Issues and Solutions

### Issue: "Your web app is running and waiting for your content"
**Cause**: No application code has been deployed to the App Service.

**Solution**: 
1. Check if deployment workflow completed successfully
2. Verify artifact was built and uploaded
3. Check deployment logs for errors
4. Manually trigger deployment workflow if needed

### Issue: Application Insights shows no data
**Cause**: Application hasn't been configured or hasn't received any traffic yet.

**Solution**:
1. Verify `APPLICATIONINSIGHTS_CONNECTION_STRING` is set on App Service
2. Send test requests to the application
3. Wait 2-5 minutes for telemetry to propagate
4. Check Application Insights Live Metrics for real-time data

### Issue: Database connection errors
**Cause**: Connection string not configured or firewall rules blocking access.

**Solution**:
1. Verify connection string is set: Check App Service → Configuration → Connection strings
2. Check SQL Server firewall rules: Ensure "Allow Azure services" is enabled
3. Check if IP needs to be whitelisted
4. Verify credentials are correct

### Issue: Application crashes on startup
**Cause**: Missing dependencies, configuration errors, or code issues.

**Solution**:
1. Check App Service → Diagnose and solve problems → Application Logs
2. Enable detailed logging in Azure Portal
3. Review deployment logs in GitHub Actions
4. Check Kudu console for startup errors: `https://<app-name>.scm.azurewebsites.net/`

## Monitoring and Maintenance

### Regular Health Checks
Create a scheduled task to verify application health:

```powershell
# health-check.ps1
# Replace {github-owner} with your GitHub username
$githubOwner = "{github-owner}"
$apiUrl = "https://$githubOwner-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger"
$uiUrl = "https://$githubOwner-orderprocessing-ui-xyapp-dev.azurewebsites.net/"

$apiResponse = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 30
$uiResponse = Invoke-WebRequest -Uri $uiUrl -Method Get -TimeoutSec 30

if ($apiResponse.StatusCode -eq 200 -and $uiResponse.StatusCode -eq 200) {
    Write-Host "✅ All services healthy" -ForegroundColor Green
} else {
    Write-Host "❌ Service health check failed" -ForegroundColor Red
}
```

### Application Insights Queries

**Check for recent errors**:
```kusto
exceptions
| where timestamp > ago(1h)
| project timestamp, type, outerMessage, operation_Name
| order by timestamp desc
```

**Monitor API response times**:
```kusto
requests
| where timestamp > ago(1h)
| summarize avg(duration), percentile(duration, 95) by operation_Name
| order by avg_duration desc
```

**Track database performance**:
```kusto
dependencies
| where timestamp > ago(1h) and type == "SQL"
| summarize avg(duration), count() by name
| order by avg_duration desc
```

## Additional Resources

- [Azure App Service Documentation](https://docs.microsoft.com/en-us/azure/app-service/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [ASP.NET Core Environment Configuration](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/environments)
- [GitHub Actions Workflows](https://docs.github.com/en/actions/using-workflows)

## Contact and Support

If issues persist after following this guide:
1. Check GitHub Actions workflow logs for detailed error messages
2. Review Azure App Service logs in the Portal
3. Check Application Insights for telemetry and errors
4. Review the repository documentation in `/Documentation` folder
