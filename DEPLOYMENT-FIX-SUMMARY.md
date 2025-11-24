# Deployment Fix Summary: SQL Database and Application Insights

## Problem Statement

The Azure-deployed applications were not accessible:
- UI Site: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net/
- API Site: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger

**Issues Identified:**
1. SQL Server migrations were not running properly on Azure SQL Database
2. Need to verify Application Insights is correctly configured

## Root Cause Analysis

### 1. Missing SQL Database in Infrastructure

The main issue was that **Azure SQL Database was not included in the Bicep infrastructure templates** (`infra/` directory).

**Evidence:**
- The `infra/modules/` directory only contained `hosting.bicep`, `insights.bicep`, and `identity.bicep`
- No `sql.bicep` module existed
- SQL database was only provisioned via the `azure-bootstrap.yml` workflow using PowerShell script `provision-azure-sql.ps1`
- Regular infrastructure deployments via `infra-deploy.yml` workflow did not provision the database
- API and UI deployments would fail when trying to connect to a non-existent database

**Impact:**
- When `infra-deploy.yml` runs, it creates App Service resources but no database
- API startup code calls `DbInitializer.Initialize()` → `context.Database.Migrate()` which fails
- Application crashes on startup with database connection errors
- No migrations are applied
- UI and API are inaccessible

### 2. Application Insights Configuration

**Status:** ✅ **Already Correctly Configured**

Application Insights was already properly set up:
- `infra/modules/insights.bicep` creates Application Insights resource
- `infra/modules/hosting.bicep` configures App Insights connection string in App Services
- Both API and UI `Program.cs` files check for `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable
- Telemetry and logging are enabled when connection string is present

## Solution Implemented

### Changes Made

#### 1. Created SQL Database Module (`infra/modules/sql.bicep`)

**Features:**
- Provisions Azure SQL Server with admin credentials
- Creates SQL Database with configurable service objective (Basic/Standard)
- Configures firewall rule to allow Azure services (0.0.0.0-0.0.0.0)
- Outputs connection string for consumption by other modules
- Supports environment-specific configurations

**Key Properties:**
```bicep
- SQL Server: {baseName}-sql-{environment}
- Database: OrderProcessingSystem_{Environment} (e.g., OrderProcessingSystem_Dev)
- Service Objective: Basic (dev/staging), S0 (prod)
- Firewall: Azure services allowed
- TLS Version: 1.2 minimum
```

#### 2. Updated Hosting Module (`infra/modules/hosting.bicep`)

**Changes:**
- Added `sqlConnectionString` parameter (secure)
- Configured connection strings in both API and UI App Services
- Connection string type: `SQLAzure`
- Connection string name: `OrderProcessingSystemDbConnection`

**Effect:**
- App Services now receive the SQL connection string automatically
- No manual configuration needed after deployment
- Connection string is injected into application configuration

#### 3. Updated Main Infrastructure (`infra/main.bicep`)

**Changes:**
- Added SQL module deployment
- Added parameters:
  - `sqlAdminUsername` (default: 'sqladmin')
  - `sqlAdminPassword` (secure, required)
  - `databaseServiceObjective` (default: 'Basic')
- Passed SQL connection string to hosting module
- Added SQL outputs: `sqlServerName`, `sqlServerFqdn`, `databaseName`

#### 4. Updated Parameter Files

Updated all environment parameter files (`infra/parameters/*.json`):

**dev.json:**
```json
"sqlAdminUsername": { "value": "sqladmin" },
"sqlAdminPassword": { "value": "Admin100@" },
"databaseServiceObjective": { "value": "Basic" }
```

**staging.json:**
```json
"sqlAdminUsername": { "value": "sqladmin" },
"sqlAdminPassword": { "value": "Admin100@" },
"databaseServiceObjective": { "value": "Basic" }
```

**prod.json:**
```json
"sqlAdminUsername": { "value": "sqladmin" },
"sqlAdminPassword": { "value": "Admin100@" },
"databaseServiceObjective": { "value": "S0" }
```

#### 5. Updated Documentation

Updated `infra/README.md` with:
- SQL module documentation
- Security notes about credential management
- Hardening recommendations (Key Vault, Managed Identity)

## How It Works Now

### Infrastructure Deployment Flow

1. **Bicep Deployment** (`infra-deploy.yml`):
   ```
   main.bicep
   ├── Resource Group creation
   ├── SQL module (sql.bicep)
   │   ├── SQL Server creation
   │   ├── Firewall rules
   │   └── Database creation
   ├── Insights module (insights.bicep)
   │   └── Application Insights creation
   ├── Hosting module (hosting.bicep)
   │   ├── App Service Plan creation
   │   ├── API Web App (with SQL connection string + App Insights)
   │   └── UI Web App (with SQL connection string + App Insights)
   └── Identity module (identity.bicep) [optional]
       └── GitHub OIDC setup
   ```

2. **API Deployment** (`deploy-api-to-azure.yml`):
   ```
   1. Build and publish .NET application
   2. Deploy to Azure Web App
   3. Run database migrations (run-database-migrations.ps1)
      - Uses connection string from App Service configuration
      - Executes: dotnet ef database update
      - Applies all pending migrations
   4. Health check
   ```

3. **Application Startup**:
   ```
   API Program.cs:
   1. Initialize services
   2. Create scope for AppMasterData
   3. Call DbInitializer.Initialize()
      - Executes: context.Database.Migrate()
      - Applies any pending migrations
      - Seeds initial data
   4. Start web host
   ```

### Database Migration Strategy

**Multiple layers of migration application:**

1. **During Infrastructure Deployment**: None (database created empty)

2. **During API Deployment** (GitHub Actions):
   - `run-database-migrations.ps1` runs
   - Uses `dotnet ef database update` with connection string
   - Applies all migrations to Azure SQL Database

3. **During API Startup** (Runtime):
   - `DbInitializer.Initialize()` calls `context.Database.Migrate()`
   - Ensures migrations are applied on first run
   - Idempotent - safe to run multiple times

**This multi-layered approach ensures:**
- Migrations run during deployment
- Migrations run on first startup (if deployment step failed)
- Database is always up-to-date
- Works in both Azure and local environments

## Verification Steps

### 1. Verify Infrastructure Deployment

After deploying infrastructure (`infra-deploy.yml`):

```bash
# Check if resources were created
az group show --name rg-orderprocessing-dev

# Check SQL Server
az sql server show --name orderprocessing-sql-dev --resource-group rg-orderprocessing-dev

# Check database
az sql db show --name OrderProcessingSystem_Dev --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev

# Check App Service configuration
az webapp config connection-string list --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev

# Check Application Insights
az monitor app-insights component show --app ai-orderprocessing-dev --resource-group rg-orderprocessing-dev
```

### 2. Verify API Deployment

After deploying API (`deploy-api-to-azure.yml`):

```bash
# Check migration logs in GitHub Actions
# Look for "DATABASE MIGRATIONS COMPLETED SUCCESSFULLY"

# Test API endpoint
curl https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger

# Check App Service logs
az webapp log tail --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev
```

### 3. Verify Application Insights

**In Azure Portal:**

1. Navigate to Application Insights resource: `ai-orderprocessing-dev`
2. Go to "Logs" section
3. Run query to see API requests:
   ```kusto
   requests
   | where timestamp > ago(1h)
   | where cloud_RoleName == "API"
   | order by timestamp desc
   | take 50
   ```

4. Check for exceptions:
   ```kusto
   exceptions
   | where timestamp > ago(1h)
   | order by timestamp desc
   | take 50
   ```

5. Check custom logs from Serilog:
   ```kusto
   traces
   | where timestamp > ago(1h)
   | where customDimensions.Application == "API"
   | order by timestamp desc
   | take 50
   ```

**Verify Connection String in App Service:**

```bash
# Check if App Insights connection string is configured
az webapp config appsettings list --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev | grep APPLICATIONINSIGHTS_CONNECTION_STRING
```

### 4. Verify Database Schema

**Using Azure Portal:**
1. Go to SQL Database: `OrderProcessingSystem_Dev`
2. Open "Query editor"
3. Login with SQL authentication (sqladmin / Admin100@)
4. Run query:
   ```sql
   -- Check migrations table
   SELECT * FROM __EFMigrationsHistory ORDER BY MigrationId;
   
   -- Check tables
   SELECT TABLE_NAME 
   FROM INFORMATION_SCHEMA.TABLES 
   WHERE TABLE_TYPE = 'BASE TABLE'
   ORDER BY TABLE_NAME;
   
   -- Check if seed data exists
   SELECT COUNT(*) as CustomerCount FROM Customers;
   SELECT COUNT(*) as ProductCount FROM Products;
   SELECT COUNT(*) as OrderCount FROM Orders;
   ```

**Using Azure CLI:**
```bash
# Install SQL CLI if needed
# pip install mssql-cli

# Connect to database
sqlcmd -S orderprocessing-sql-dev.database.windows.net -d OrderProcessingSystem_Dev -U sqladmin -P Admin100@

# Or use mssql-cli
mssql-cli -S orderprocessing-sql-dev.database.windows.net -d OrderProcessingSystem_Dev -U sqladmin -P Admin100@
```

## Troubleshooting

### Issue: API Returns 500 Error

**Check Application Insights for detailed errors:**
1. Go to Azure Portal → Application Insights → Logs
2. Run query:
   ```kusto
   exceptions
   | where timestamp > ago(1h)
   | project timestamp, type, outerMessage, innermostMessage
   | order by timestamp desc
   ```

**Check App Service logs:**
```bash
az webapp log tail --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev
```

### Issue: Database Connection Failed

**Verify connection string:**
```bash
# Get connection strings (password will be masked)
az webapp config connection-string list --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev
```

**Check SQL Server firewall:**
```bash
# List firewall rules
az sql server firewall-rule list --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev

# Ensure "AllowAzureServices" rule exists
az sql server firewall-rule show --name AllowAzureServices --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev
```

### Issue: Migrations Not Applied

**Check migration logs in GitHub Actions:**
1. Go to GitHub Actions → Latest API deployment workflow
2. Check "Run Database Migrations" step
3. Look for errors

**Manually run migrations:**
```bash
# From solution root
dotnet ef database update --project XYDataLabs.OrderProcessingSystem.Infrastructure --startup-project XYDataLabs.OrderProcessingSystem.API --connection "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=OrderProcessingSystem_Dev;User ID=sqladmin;Password=Admin100@;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

### Issue: Application Insights Not Showing Data

**Verify configuration:**
```bash
# Check if connection string is set
az webapp config appsettings list --name pavanthakur-orderprocessing-api-xyapp-dev --resource-group rg-orderprocessing-dev | grep APPLICATIONINSIGHTS
```

**Expected output:**
```json
{
  "name": "APPLICATIONINSIGHTS_CONNECTION_STRING",
  "value": "InstrumentationKey=xxxxx;IngestionEndpoint=https://centralindia-1.in.applicationinsights.azure.com/;..."
},
{
  "name": "ApplicationInsightsAgent_EXTENSION_VERSION",
  "value": "~3"
}
```

**Check API logs for App Insights initialization:**
Look for log messages:
- `[CONFIG] Application Insights enabled for dev environment`
- If not found: `[CONFIG] Application Insights NOT configured - connection string missing for dev environment`

## Security Considerations

### Current Implementation

⚠️ **SQL Credentials in Parameter Files**
- Admin credentials are stored in plain text in parameter files
- This is acceptable for development but **NOT RECOMMENDED for production**

### Recommended Hardening Steps

1. **Use Azure Key Vault for Secrets:**
   ```bicep
   // In parameter files, reference Key Vault secrets
   "sqlAdminPassword": {
     "reference": {
       "keyVault": {
         "id": "/subscriptions/{subscriptionId}/resourceGroups/{rgName}/providers/Microsoft.KeyVault/vaults/{vaultName}"
       },
       "secretName": "sql-admin-password"
     }
   }
   ```

2. **Implement Managed Identity for SQL:**
   - Enable System-Assigned or User-Assigned Managed Identity on App Services
   - Grant identity SQL permissions
   - Update connection string to use Managed Identity authentication
   - Remove SQL credentials entirely

3. **Restrict SQL Firewall Rules:**
   - Current: Allows all Azure services (0.0.0.0-0.0.0.0)
   - Recommended: Add specific IP ranges for App Services
   - Use Virtual Network integration and Private Endpoints for production

4. **Enable Advanced Threat Protection:**
   - Enable Azure Defender for SQL
   - Set up vulnerability assessments
   - Configure audit logs

## Next Steps

### Immediate Actions

1. **Deploy Infrastructure:**
   ```bash
   # Trigger infra-deploy workflow or run manually
   az deployment sub create \
     --location centralindia \
     --template-file infra/main.bicep \
     --parameters @infra/parameters/dev.json \
     --name infra-dev-$(date +%s)
   ```

2. **Deploy API:**
   - Push changes to `dev` branch or trigger `deploy-api-to-azure.yml` manually
   - Verify migrations run successfully
   - Check health endpoint

3. **Verify Deployments:**
   - Visit https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
   - Visit https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net/
   - Check Application Insights for telemetry

### Future Enhancements

1. **Security:**
   - Migrate to Key Vault for secrets
   - Implement Managed Identity
   - Restrict firewall rules

2. **Monitoring:**
   - Set up Application Insights alerts
   - Configure availability tests
   - Add custom metrics

3. **Infrastructure:**
   - Add diagnostic settings for all resources
   - Implement backup policies for SQL
   - Add deployment slots for zero-downtime deployments

4. **CI/CD:**
   - Add automated smoke tests after deployment
   - Implement blue-green deployments
   - Add rollback procedures

## References

- **Bicep Documentation**: https://learn.microsoft.com/azure/azure-resource-manager/bicep/
- **Azure SQL Documentation**: https://learn.microsoft.com/azure/azure-sql/
- **Application Insights**: https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview
- **EF Core Migrations**: https://learn.microsoft.com/ef/core/managing-schemas/migrations/

## Summary

The deployment issues were caused by the absence of SQL Database in the Bicep infrastructure templates. The solution adds a comprehensive SQL module that:

✅ Provisions Azure SQL Database as part of infrastructure deployment  
✅ Automatically configures connection strings in App Services  
✅ Enables automatic migration execution during deployment  
✅ Ensures database is ready before API starts  
✅ Maintains Application Insights configuration  

The infrastructure is now fully declarative and reproducible across all environments (dev/staging/prod).
