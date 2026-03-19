---
mode: agent
description: Run SQL Managed Identity setup after a clean deployment or first-time environment setup. Creates the contained SQL user for the App Service and grants db_datareader/writer/ddladmin.
---

Ask the user: "Which environment do you need to set up SQL Managed Identity for? (dev / staging / prod)"

Based on their answer, execute the following steps in order:

## Step 1 — Verify prerequisites

Check that the App Service managed identity exists:
```powershell
az webapp identity show `
  --name pavanthakur-orderprocessing-api-xyapp-<env> `
  --resource-group rg-orderprocessing-<envSuffix> `
  --query "{principalId:principalId, tenantId:tenantId}" -o json
```
> staging suffix is `stg`, not `staging` (e.g. `rg-orderprocessing-stg`)

If this returns null/empty, the Bicep deployment hasn't run yet — tell the user to run the bootstrap workflow first.

## Step 2 — Ensure SqlServer module is installed

```powershell
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    Install-Module SqlServer -AllowClobber -Scope CurrentUser -Force
}
```

## Step 3 — Run the setup script

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\setup-sql-managed-identity.ps1 -Environment <dev|staging|prod>
```

The script will:
1. Get the App Service managed identity principal ID
2. Acquire an Azure AD access token for Azure SQL (uses your `az login` session)
3. Create a contained user in the database
4. Grant `db_datareader`, `db_datawriter`, `db_ddladmin`

## Step 4 — Verify the API connects

After the script completes, restart the App Service and confirm no auth errors:
```powershell
az webapp restart `
  --name pavanthakur-orderprocessing-api-xyapp-<env> `
  --resource-group rg-orderprocessing-<envSuffix>
```

Then hit: `https://pavanthakur-orderprocessing-api-xyapp-<env>.azurewebsites.net/api/orders`

A `200 OK` (even empty `[]`) confirms SQL auth is working.

---

## When is this needed?

| Situation | Run? |
|-----------|------|
| First-time setup of a new environment | ✅ Yes |
| Full resource group teardown + recreate (`cleanupInfra: true` then bootstrap) | ✅ Yes |
| App Service deleted & recreated manually | ✅ Yes |
| Regular `git push` / CI redeploy | ❌ No |
| Bicep incremental redeploy (existing RG) | ❌ No |

> **Important**: `aadAdminObjectId` and `aadAdminLogin` in the parameter files never need updating — they are your permanent Azure AD user identifiers (your Object ID in Azure AD). Only the SQL contained user inside the database is lost on a clean deploy.

> **Prerequisite**: You must be logged in as the Azure AD admin set in `aadAdminObjectId` in the parameter file. Run `az login` if unsure.
