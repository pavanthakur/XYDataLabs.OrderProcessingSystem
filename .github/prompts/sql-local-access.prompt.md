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
| Password | `Admin100@` |

Remind the user:
- The rule `dev-machine` is re-used each time (upsert-safe — same name overwrites)
- Always close with `-Close` when done local work
- Day 35 (Managed Identity) will eliminate the need for this rule for the App Service — but local SSMS still needs it until you use Entra auth locally
