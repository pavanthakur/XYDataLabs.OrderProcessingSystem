---
agent: agent
description: "Opens or closes the Azure SQL firewall rule for your current local IP (dev, staging, or prod); runs open-local-sql-firewall.ps1 with -Close to revoke, then prints SSMS/sqlcmd connection strings for both main and TenantC databases"
---

Ask the user: "Which environment do you need SQL access for? (dev / staging / prod) — and do you want to open or close the firewall?"

Based on their answer:

**To OPEN the firewall:**
Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment <dev|staging|prod>
```

**To CLOSE the firewall:**
Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment <dev|staging|prod> -Close
```

After running, confirm the result and display the SSMS connection details:

| Field | Value |
|-------|-------|
| Server | `orderprocessing-sql-<envSuffix>.database.windows.net` |
| Database (main) | `OrderProcessingSystem_<Dev\|Stg\|Prod>` |
| Database (TenantC) | `OrderProcessingSystem_TenantC_<Dev\|Stg\|Prod>` |
| Auth | SQL Server Authentication |
| Login | `sqladmin` |
| Password | Retrieve from Key Vault: `az keyvault secret show --vault-name kv-orderprocessing-<envSuffix> --name sql-admin-password --query value -o tsv` |

> **Note**: `staging` maps to suffix `stg` in all Azure resource names — e.g. `orderprocessing-sql-stg`, `kv-orderprocessing-stg`.

Remind the user:
- The rule `dev-machine` is re-used each time (upsert-safe — same name overwrites)
- Always close with `-Close` when done local work
- The SQL admin password is auto-generated and stored in Key Vault — never committed to source control
