# 🚀 Week 3-4: Practical Azure Deployment Exercises

## **📖 Complete Deployment Guide**

For detailed step-by-step instructions with full configuration details, troubleshooting, and OIDC setup, refer to:

**[Azure Deployment Guide](../../../Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md)**

This guide includes:
- ✅ Complete OIDC authentication setup with `Resources/Azure-Deployment/setup-github-oidc.ps1`
- ✅ GitHub Actions workflow configuration
- ✅ Federated identity credential configuration
- ✅ Production environment and secrets setup
- ✅ Deployment verification and troubleshooting
- ✅ Security best practices and maintenance procedures

---

## **📅 Integration with Serverless & Functions Module**

These deployment exercises complement your serverless learning and provide hands-on Azure App Service experience.

---

## **🎯 DEPLOYMENT LEARNING OBJECTIVES**

By the end of Week 3-4, you will be able to:
- ✅ Deploy ASP.NET Core applications to Azure App Service
- ✅ Configure GitHub Actions CI/CD workflows
- ✅ Manage Azure resources using Azure Portal and CLI
- ✅ Implement application settings and connection strings
- ✅ Monitor deployed applications with Application Insights

---

## **📋 EXERCISE 1: Deploy API to Azure App Service (Days 15-16)**

### **Prerequisites:**
- Azure subscription (Free tier is sufficient)
- GitHub account with repository access
- Azure CLI installed locally

### **Step 1: Create Azure Resources (Day 15 - Morning)**

Optional: Start fresh (delete existing)
```powershell
az group delete --name rg-orderprocessing-dev --yes
```
This permanently deletes the resource group and all contained resources. Use only if you want a clean reset.

#### **Using Azure Portal (Beginner-Friendly):**

1. **Create Resource Group:**
   ```
   Name: rg-orderprocessing-dev
   Region: Central India
   ```

2. **Create App Service Plan:**
   ```
   Name: asp-orderprocessing-dev
   Region: Central India
   Pricing Tier: F1 (Free) or B1 (Basic)
   Operating System: Windows
   ```

3. **Create Web App for API:**
   ```
   Name: orderprocessing-api-xyapp
   Runtime Stack: .NET 8 (LTS)
   App Service Plan: asp-orderprocessing-dev
   ```

#### **Using Azure CLI (Alternative):**

```powershell
# Login to Azure
az login

# Create Resource Group
az group create --name rg-orderprocessing-dev --location centralindia

# Create App Service Plan (Free tier, Windows)
az appservice plan create --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku F1 --location centralindia

# Create Web App for API with .NET 8 runtime
az webapp create --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --plan asp-orderprocessing-dev --runtime "dotnet:8"

# Create Web App for UI with .NET 8 runtime
az webapp create --name orderprocessing-ui-xyapp --resource-group rg-orderprocessing-dev --plan asp-orderprocessing-dev --runtime "dotnet:8"
```

**Important:** The `--runtime "dotnet:8"` parameter configures .NET 8 (LTS) runtime on Windows App Service Plans. If you encounter transient connection errors (Error 10054), the webapp may still be created successfully - verify with:
```powershell
az webapp show --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --query "name" -o tsv
```

Quick verification (after creation):
```powershell
# List resources in the group
az resource list --resource-group rg-orderprocessing-dev --output table

# Open the web app URL in your browser
Start-Process "https://orderprocessing-api-xyapp.azurewebsites.net"
```
Expected: The table lists `asp-orderprocessing-dev` (serverFarms) and `orderprocessing-api-xyapp` (sites); the browser shows the default Azure page.

**Note:** The App Service Plan defaults to Windows (no need for `--is-linux false` flag).

**✅ Checkpoint:** Verify Web App is created and shows default Azure landing page.

#### **Verify .NET 8 Runtime Configuration:**

```powershell
# Check runtime configuration
az webapp config show --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --query "{NetFrameworkVersion:netFrameworkVersion, LinuxFxVersion:linuxFxVersion}" -o json
```

**Expected output:** `"NetFrameworkVersion": "v8.0"` confirms .NET 8 runtime is configured.

**Note:** If runtime shows default value (v4.0) instead of v8.0, configure via Azure Portal:
1. Navigate to: https://portal.azure.com
2. Go to: **Resource Groups** → `rg-orderprocessing-dev` → `orderprocessing-api-xyapp`
3. **Settings** → **Configuration** → **General settings**
4. Set **Stack:** `.NET` and **.NET version:** `8 (LTS)`
5. Click **Save**

**✅ Verification:**
```powershell
# List all resources
az resource list --resource-group rg-orderprocessing-dev --output table

# Open web app in browser
Start-Process "https://orderprocessing-api-xyapp.azurewebsites.net"
```

---

### **Step 2: Configure Application Settings (Day 15 - Evening)**

1. **In Azure Portal, navigate to your Web App**
2. **Go to Configuration > Application Settings**
3. **Add the following settings:**

```json
{
  "ASPNETCORE_ENVIRONMENT": "Production",
  "Logging__LogLevel__Default": "Information",
  "AllowedHosts": "*"
}
```

4. **Configure Connection Strings (if using database):**
   - For now, use in-memory database
   - We'll add Azure SQL in Week 11-12

**✅ Checkpoint:** Application settings saved successfully.

---

### **Step 3: Set Up GitHub Actions Deployment (Day 16 - Morning)**

1. **In Azure Portal, go to your Web App**
2. **Navigate to Deployment Center**
3. **Select GitHub as source**
4. **Authorize GitHub access**
5. **Select your repository and branch**
6. **Azure will auto-generate a workflow file**

**Important:** Azure will create secrets automatically:
- `AZURE_WEBAPP_PUBLISH_PROFILE` or
- `AZUREAPPSERVICE_CLIENTID_*` (for federated credentials)

---

### **Step 4: Customize Workflow for Your Project (Day 16 - Evening)**

Create `.github/workflows/deploy-api-to-azure.yml`:

```yaml
name: Deploy API to Azure App Service

on:
  push:
    branches:
      - main
    paths:
      - 'XYDataLabs.OrderProcessingSystem.API/**'
      - 'XYDataLabs.OrderProcessingSystem.Application/**'
      - 'XYDataLabs.OrderProcessingSystem.Domain/**'
      - 'XYDataLabs.OrderProcessingSystem.Infrastructure/**'
      - 'XYDataLabs.OrderProcessingSystem.Utilities/**'
  workflow_dispatch:

env:
  DOTNET_VERSION: '8.x'
  AZURE_WEBAPP_NAME: 'orderprocessing-api-xyapp'
  AZURE_WEBAPP_PACKAGE_PATH: './publish'
  PROJECT_PATH: 'XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj'

jobs:
  build:
    runs-on: windows-latest
    permissions:
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Restore dependencies
        run: dotnet restore ${{ env.PROJECT_PATH }}

      - name: Build
        run: dotnet build ${{ env.PROJECT_PATH }} --configuration Release --no-restore

      - name: Publish
        run: dotnet publish ${{ env.PROJECT_PATH }} --configuration Release --no-build --output ${{ env.AZURE_WEBAPP_PACKAGE_PATH }}

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: dotnet-app
          path: ${{ env.AZURE_WEBAPP_PACKAGE_PATH }}

  deploy:
    runs-on: windows-latest
    needs: build
    permissions:
      id-token: write
      contents: read
    environment:
      name: 'Production'
      url: ${{ steps.deploy-to-webapp.outputs.webapp-url }}

    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: dotnet-app

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
          tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
          subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}

      - name: Deploy to Azure Web App
        id: deploy-to-webapp
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          package: .
```

**✅ Checkpoint:** Push to GitHub and verify workflow runs successfully.

---

### **Step 5: Test Deployed API (Day 17 - Morning)**

1. **Get your API URL:**
   ```
   https://orderprocessing-api-xyapp.azurewebsites.net
   ```

2. **Test Swagger endpoint:**
   ```
   https://orderprocessing-api-xyapp.azurewebsites.net/swagger
   ```

3. **Test API endpoints with Postman:**
   - Create a new collection
   - Import Swagger JSON
   - Test all endpoints

**✅ Checkpoint:** API is accessible and all endpoints work.

---

## **📋 EXERCISE 2: Deploy UI to Azure App Service (Days 17-18)**

### **Step 1: Create Web App for UI (Day 17 - Evening)**

```powershell
# Create Web App for UI with .NET 8 runtime
az webapp create --name orderprocessing-ui-xyapp --resource-group rg-orderprocessing-dev --plan asp-orderprocessing-dev --runtime "dotnet:8"
```

**Verify runtime configuration:**
```powershell
az webapp config show --name orderprocessing-ui-xyapp --resource-group rg-orderprocessing-dev --query "netFrameworkVersion" -o tsv
```
Expected: `v8.0`

---

### **Step 2: Configure UI Application Settings (Day 18 - Morning)**

Add these settings in Azure Portal:

```json
{
  "ASPNETCORE_ENVIRONMENT": "Production",
  "ApiSettings__BaseUrl": "https://orderprocessing-api-xyapp.azurewebsites.net"
}
```

---

### **Step 3: Create UI Deployment Workflow (Day 18 - Evening)**

Create `.github/workflows/deploy-ui-to-azure.yml`:

```yaml
name: Deploy UI to Azure App Service

on:
  push:
    branches:
      - main
    paths:
      - 'XYDataLabs.OrderProcessingSystem.UI/**'
  workflow_dispatch:

env:
  DOTNET_VERSION: '8.x'
  AZURE_WEBAPP_NAME: 'orderprocessing-ui-xyapp'
  AZURE_WEBAPP_PACKAGE_PATH: './publish'
  PROJECT_PATH: 'XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj'

jobs:
  build-and-deploy:
    runs-on: windows-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Restore dependencies
        run: dotnet restore ${{ env.PROJECT_PATH }}

      - name: Build and Publish
        run: dotnet publish ${{ env.PROJECT_PATH }} --configuration Release --output ${{ env.AZURE_WEBAPP_PACKAGE_PATH }}

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
          tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
          subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          package: ${{ env.AZURE_WEBAPP_PACKAGE_PATH }}
```

**✅ Checkpoint:** UI deploys and can access the API successfully.

---

## **📋 EXERCISE 3: Add Application Insights (Day 19 - Morning)**

**📖 Complete Setup Guide:** For detailed Application Insights configuration, monitoring, and best practices, refer to:

**[Application Insights Setup Guide](../../../Documentation/02-Azure-Learning-Guides/APPLICATION_INSIGHTS_SETUP.md)**

This guide includes:
- ✅ Step-by-step Application Insights resource creation
- ✅ Connection string configuration for API and UI
- ✅ Code instrumentation with NuGet packages
- ✅ Custom telemetry tracking and logging
- ✅ Dashboard creation and alert configuration
- ✅ Performance monitoring and troubleshooting

---

### **Step 1: Create Application Insights**

```powershell
# Create Application Insights
az monitor app-insights component create --app orderprocessing-insights --location centralindia --resource-group rg-orderprocessing-dev --application-type web
```

### **Step 2: Get Instrumentation Key**

```powershell
az monitor app-insights component show --app orderprocessing-insights --resource-group rg-orderprocessing-dev --query instrumentationKey
```

### **Step 3: Add to Application Settings**

In both API and UI Web Apps, add:

```json
{
  "APPLICATIONINSIGHTS_CONNECTION_STRING": "InstrumentationKey=YOUR_KEY_HERE"
}
```

### **Step 4: Add Application Insights to Your Code**

In both API and UI projects:

```csharp
// Program.cs
builder.Services.AddApplicationInsightsTelemetry();
```

**✅ Checkpoint:** Application Insights showing telemetry data.

---

## **📋 EXERCISE 4: Monitoring & Troubleshooting (Day 19-20)**

### **Essential Monitoring Tasks:**

1. **View Application Logs:**
   - Azure Portal > Web App > Monitoring > Log stream

2. **Check Performance Metrics:**
   - Application Insights > Performance
   - View response times and dependencies

3. **Set Up Alerts:**
   - Create alert for HTTP 500 errors
   - Create alert for high response time

4. **Enable Diagnostic Logging:**
   ```powershell
   az webapp log config --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --application-logging filesystem --level information
   ```

**✅ Checkpoint:** Monitoring dashboard configured and alerts working.

---

## **📋 EXERCISE 5: Deployment Slots & Staging (Day 20 - Advanced)**

### **Create Staging Slot:**

```powershell
az webapp deployment slot create --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --slot staging
```

### **Deploy to Staging First:**

Update your workflow to deploy to staging:

```yaml
- name: Deploy to Staging Slot
  uses: azure/webapps-deploy@v3
  with:
    app-name: ${{ env.AZURE_WEBAPP_NAME }}
    slot-name: 'staging'
    package: .
```

### **Swap Slots After Testing:**

```powershell
az webapp deployment slot swap --name orderprocessing-api-xyapp --resource-group rg-orderprocessing-dev --slot staging --target-slot production
```

**✅ Checkpoint:** Blue-green deployment working with slots.

---

## **🎯 WEEK 3-4 DEPLOYMENT SUCCESS CRITERIA**

### **✅ Must Complete:**
- [ ] API deployed to Azure App Service
- [ ] UI deployed to Azure App Service
- [ ] GitHub Actions CI/CD working
- [ ] Application Insights monitoring enabled
- [ ] Both apps communicating successfully

### **✅ Optional (Advanced):**
- [ ] Deployment slots configured
- [ ] Custom domain configured
- [ ] SSL certificate added
- [ ] Azure Front Door or CDN configured

---

## **📊 Deployment Knowledge Checklist**

Rate your understanding (1-10):

- [ ] Azure App Service concepts: ___/10
- [ ] GitHub Actions workflows: ___/10
- [ ] Application configuration: ___/10
- [ ] Monitoring and diagnostics: ___/10
- [ ] Deployment strategies: ___/10

**Overall Deployment Competency**: ___/50

---

## **🚀 Next Steps: Week 5-6 (DevOps & CI/CD)**

In Week 5-6, you'll enhance this foundation with:
- Infrastructure as Code (Bicep/Terraform)
- Azure DevOps Pipelines
- Automated testing in CI/CD
- Container-based deployments

---

## **💡 Troubleshooting Common Issues**

### **Issue: 404 Not Found**
- **Solution:** Check that published files are in wwwroot for UI
- Verify API routes are configured correctly

### **Issue: 500 Internal Server Error**
- **Solution:** Check Application Insights logs
- Verify connection strings and app settings
- Enable detailed error messages in staging

### **Issue: Workflow Fails on Build**
- **Solution:** Verify project path is correct
- Check .NET version matches runtime
- Ensure all NuGet packages restore correctly

### **Issue: Apps Can't Communicate**
- **Solution:** Check CORS configuration
- Verify API BaseUrl in UI settings
- Check network security groups (NSG)

---

**🎉 Congratulations! You've completed practical Azure deployment exercises and have a live application running in the cloud!**
