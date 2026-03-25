---
applyTo: "**/infra/**,**/bicep/**,**/*.bicep"
---
# Bicep / IaC Conventions — XYDataLabs.OrderProcessingSystem

## Two IaC Folders
| Folder | Scope | Deploy command |
|--------|-------|----------------|
| `infra/` | Subscription (`targetScope = 'subscription'`) | `az deployment sub create` |
| `bicep/` | Resource Group | `az deployment group create` |

## CRITICAL: infra/main.bicep uses subscription scope
Always use `az deployment sub create` for the `infra/` folder — NOT `az deployment group create`.

```powershell
# Correct — subscription scope
az deployment sub create \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.json

# Wrong — do not use for infra/
# az deployment group create ...
```

## infra/ Module Structure
```
infra/
  main.bicep          ← orchestrates all modules
  modules/
    hosting.bicep     ← App Service Plan + Web Apps
    sql.bicep         ← SQL Server + database
    keyvault.bicep    ← Key Vault + managed identity
    insights.bicep    ← Application Insights
    identity.bicep    ← User-assigned managed identity
```

## Parameter Files
- `infra/parameters/dev.json` — `environment: dev`, `appServiceSku: F1`, `databaseServiceObjective: Basic`, `location: centralindia`
- `infra/parameters/staging.json` — suffix `stg` (not `staging`)
- `infra/parameters/prod.json`

## Resource Naming Convention
- Resource Group: `rg-orderprocessing-{env}`
- App Service Plan: `asp-orderprocessing-{env}`
- API Web App: `pavanthakur-orderprocessing-api-xyapp-{env}`
- UI Web App: `pavanthakur-orderprocessing-ui-xyapp-{env}`
- SQL Server: `orderprocessing-sql-{env}`
- Key Vault: `kv-orderproc-{env}`
- App Insights: `ai-orderprocessing-{env}`

Note: staging uses `stg` suffix in Azure resource names but `staging` as the workflow environment name.

## What-If (Dry Run)
```powershell
az deployment sub what-if \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.json
```
