# Application Insights - Automated Environment-wise Setup

## Overview

**Last Updated**: November 23, 2025  
**Feature**: Automated Application Insights configuration per environment  
**Integration**: Azure Bootstrap Workflow + App Service automatic instrumentation  
**Environments**: dev, staging, prod (separate App Insights instances)

This document describes the automated Application Insights setup that is now integrated into the Azure bootstrap workflow. This approach follows enterprise best practices for observability and telemetry.

---

## 🏢 Enterprise Application Development Approach

### Why This Approach is Enterprise-Grade

#### 1. **Environment Isolation**
- ✅ **Separate App Insights per environment** (dev, staging, prod)
- ✅ Each environment has its own connection string and instrumentation key
- ✅ Prevents telemetry mixing between environments
- ✅ Enables environment-specific retention policies and quotas

#### 2. **Infrastructure as Code (IaC)**
- ✅ App Insights provisioned via Bicep templates
- ✅ Declarative configuration managed in version control
- ✅ Reproducible across environments
- ✅ Automated via CI/CD pipeline

#### 3. **Secure Secret Management**
- ✅ Connection strings stored as GitHub environment secrets
- ✅ Secrets scoped per environment (dev, staging, prod)
- ✅ Automatic rotation via GitHub App authentication
- ✅ No hardcoded credentials in code or config files

#### 4. **Automatic Instrumentation**
- ✅ SDK integrated at application startup
- ✅ Configuration via environment variables
- ✅ Zero-code-change telemetry collection
- ✅ Consistent logging with Serilog integration

#### 5. **GitOps and Automation**
- ✅ Fully automated deployment pipeline
- ✅ Configuration drift prevention
- ✅ Audit trail via Git commits
- ✅ Self-service infrastructure provisioning

---

## Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   Azure Bootstrap Workflow                       │
│  (.github/workflows/azure-bootstrap.yml)                        │
└────────────┬────────────────────────────────────────────────────┘
             │
             ├─► 1. OIDC Setup (Azure AD Service Principal)
             │
             ├─► 2. Bicep Deployment (Infrastructure as Code)
             │    ├─► Resource Group
             │    ├─► App Service Plan
             │    ├─► App Insights (per environment)
             │    └─► App Services (API + UI)
             │
             ├─► 3. App Insights Configuration
             │    ├─► Retrieve connection string from Azure
             │    ├─► Store as GitHub environment secret
             │    └─► Available to deployment workflows
             │
             └─► 4. Application Deployment
                  ├─► App Service reads APPLICATIONINSIGHTS_CONNECTION_STRING
                  ├─► SDK auto-configures at startup
                  └─► Telemetry flows to environment-specific App Insights
```

### Infrastructure Components

| Component | Purpose | Configuration Source |
|-----------|---------|---------------------|
| **App Insights Instance** | Telemetry collection | `infra/modules/insights.bicep` |
| **Connection String** | SDK authentication | Retrieved from Azure, stored as secret |
| **App Service Settings** | Runtime configuration | `infra/modules/hosting.bicep` |
| **SDK Integration** | Application telemetry | `Program.cs` in API project |

---

## Automated Setup Process

### What Happens During Bootstrap

When you run the Azure bootstrap workflow with `bootstrapInfra = true`:

#### Step 1: Infrastructure Provisioning
The Bicep templates create:
```
- Resource Group: rg-orderprocessing-{env}
- App Insights:   ai-orderprocessing-{env}
- App Services:   Configure with App Insights settings
```

#### Step 2: App Insights Configuration (New)
After infrastructure is created, the workflow automatically:

1. **Retrieves App Insights metadata** from Azure:
   ```powershell
   az monitor app-insights component show \
     --app ai-orderprocessing-{env} \
     --resource-group rg-orderprocessing-{env}
   ```

2. **Extracts connection string**:
   ```
   InstrumentationKey=12345678-abcd-...;IngestionEndpoint=https://...
   ```

3. **Stores as GitHub environment secret**:
   ```
   Secret Name:  APPLICATIONINSIGHTS_CONNECTION_STRING
   Scope:        Environment (dev/staging/prod)
   Access:       Deployment workflows only
   ```

#### Step 3: Application Configuration
The .NET API application:

1. **Reads connection string** from environment variable:
   ```csharp
   var appInsightsConnectionString = 
       builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"] 
       ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING");
   ```

2. **Configures Application Insights SDK**:
   ```csharp
   builder.Services.AddApplicationInsightsTelemetry(options =>
   {
       options.ConnectionString = appInsightsConnectionString;
       options.EnableAdaptiveSampling = true;
       options.EnableQuickPulseMetricStream = true;
   });
   ```

3. **Logs configuration status** via Serilog:
   ```
   [CONFIG] Application Insights enabled for dev environment
   ```

---

## Manual Verification

### 1. Check GitHub Secrets

Navigate to: `https://github.com/{owner}/{repo}/settings/environments`

For each environment (dev, staging, prod), verify:
- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` secret exists

### 2. Check Azure Portal

1. Navigate to Resource Group: `rg-orderprocessing-{env}`
2. Open App Insights: `ai-orderprocessing-{env}`
3. Verify:
   - ✅ Resource is in "Running" state
   - ✅ Connection string is populated
   - ✅ Instrumentation key is visible

### 3. Check App Service Configuration

1. Navigate to App Service: `{owner}-orderprocessing-api-xyapp-{env}`
2. Go to **Configuration** → **Application settings**
3. Verify:
   - ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` is set
   - ✅ `ApplicationInsightsAgent_EXTENSION_VERSION` = `~3`
   - ✅ `APPINSIGHTS_INSTRUMENTATIONKEY` is set

### 4. Verify Telemetry Collection

After deploying the application:

1. Open App Insights in Azure Portal
2. Go to **Logs** (or **Transaction search**)
3. Run KQL query:
   ```kql
   requests
   | where timestamp > ago(30m)
   | summarize count() by cloud_RoleName, resultCode
   | order by count_ desc
   ```

4. Expected results within 2-5 minutes of first request:
   - ✅ Requests logged with cloud_RoleName
   - ✅ HTTP status codes captured
   - ✅ Duration and dependencies tracked

---

## Troubleshooting

### Scenario 1: App Insights Configuration Step Fails

**Symptom**: Bootstrap completes but App Insights secret not configured

**Possible Causes**:
1. GitHub App not installed on repository
2. GitHub App lacks Secrets: Read and write permission
3. Environment doesn't exist in GitHub

**Resolution**:
```powershell
# Manual configuration fallback
# 1. Get connection string from Azure Portal
# 2. Add to GitHub environment secrets manually:
#    https://github.com/{owner}/{repo}/settings/environments
```

### Scenario 2: Application Not Sending Telemetry

**Symptom**: No telemetry in App Insights after deployment

**Check 1**: Verify connection string is configured
```bash
az webapp config appsettings list \
  --name {app-name} \
  --resource-group rg-orderprocessing-{env} \
  --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value"
```

**Check 2**: Check application logs
```bash
az webapp log tail \
  --name {app-name} \
  --resource-group rg-orderprocessing-{env}
```

Look for:
```
[CONFIG] Application Insights enabled for {env} environment
```

**Check 3**: Verify SDK package is installed
```bash
# In project directory
dotnet list package | grep ApplicationInsights
```

Expected output:
```
Microsoft.ApplicationInsights.AspNetCore    2.22.0
```

### Scenario 3: Telemetry Mixing Between Environments

**Symptom**: Dev traffic appearing in prod App Insights

**Root Cause**: Incorrect connection string configuration

**Resolution**:
1. Verify each environment has separate secrets
2. Check App Service configuration per environment
3. Redeploy affected environment

---

## KQL Query Examples

### Recent Requests by Environment
```kql
requests
| where timestamp > ago(1h)
| extend environment = cloud_RoleName
| summarize
    requestCount = count(),
    avgDuration = avg(duration),
    failureRate = countif(success == false) * 100.0 / count()
  by environment, bin(timestamp, 5m)
| order by timestamp desc
```

### Exception Analysis
```kql
exceptions
| where timestamp > ago(24h)
| extend environment = cloud_RoleName
| summarize
    exceptionCount = count(),
    uniqueTypes = dcount(type)
  by environment, type
| order by exceptionCount desc
```

### Performance Tracking
```kql
requests
| where timestamp > ago(1h)
| extend environment = cloud_RoleName
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99)
  by environment, name
| order by p95 desc
```

---

## Benefits Over Manual Setup

| Aspect | Manual Setup | Automated Setup |
|--------|--------------|-----------------|
| **Provisioning Time** | 15-20 minutes per environment | 2-3 minutes (automated) |
| **Configuration Errors** | High risk (copy-paste) | Low risk (automated) |
| **Secret Management** | Manual updates required | Automatic via workflow |
| **Consistency** | Varies by environment | Identical across environments |
| **Documentation** | Manual maintenance | Self-documenting via IaC |
| **Audit Trail** | Limited | Full Git history |

---

## Related Documentation

- **[AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md)** - Complete Azure deployment guide
- **[QUICK-START-AZURE-BOOTSTRAP.md](../QUICK-START-AZURE-BOOTSTRAP.md)** - Bootstrap workflow quick start
- **[Bootstrap-Workflow-Summary.md](../Bootstrap-Workflow-Summary.md)** - Detailed workflow documentation
- **[APPLICATION_INSIGHTS_SETUP.md](./APPLICATION_INSIGHTS_SETUP.md)** - Legacy manual setup (deprecated)

---

## Best Practices

### ✅ DO
- Use separate App Insights instances per environment
- Store connection strings as environment secrets
- Monitor telemetry within 5 minutes of deployment
- Set up alerts for critical errors and performance degradation
- Configure retention policies per environment (dev: 30 days, prod: 90+ days)

### ❌ DON'T
- Share App Insights instances across environments
- Hardcode connection strings in code or configuration files
- Disable telemetry in production (use sampling instead)
- Expose instrumentation keys in logs or UI
- Mix development and production telemetry

---

## Summary

The automated App Insights setup provides:
- ✅ **Enterprise-grade observability** with environment isolation
- ✅ **Zero-configuration deployment** via GitOps workflow
- ✅ **Secure secret management** with GitHub App integration
- ✅ **Consistent telemetry** across all environments
- ✅ **Audit trail and reproducibility** via Infrastructure as Code

This approach follows Microsoft Azure Well-Architected Framework principles for monitoring, security, and operational excellence.
