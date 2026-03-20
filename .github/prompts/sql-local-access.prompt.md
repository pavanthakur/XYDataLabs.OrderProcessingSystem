---
mode: agent
description: Open or close Azure SQL firewall for local SSMS/sqlcmd access after a fresh bootstrap or deploy
---

Ask the user: "Which environment do you need SQL access for? (dev / staging) — and do you want to open or close the firewall?"

Based on their answer:

**To OPEN the firewall:**
Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment <dev|staging>
```

**To CLOSE the firewall:**
Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment <dev|staging> -Close
```

After running, confirm the result and display the SSMS connection details:

| Field | Value |
|-------|-------|
| Server | `orderprocessing-sql-<env>.database.windows.net` |
| Database | `OrderProcessingSystem_Dev` |
| Auth | SQL Server Authentication |
| Login | `sqladmin` |
| Password | Retrieve from Key Vault: `az keyvault secret show --vault-name kv-orderprocessing-<env> --name sql-admin-password --query value -o tsv` |

Remind the user:
- The rule `dev-machine` is re-used each time (upsert-safe — same name overwrites)
- Always close with `-Close` when done local work
- The SQL admin password is auto-generated and stored in Key Vault — never committed to source control
