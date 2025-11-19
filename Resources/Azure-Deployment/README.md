# Azure Deployment Scripts

This folder intentionally avoids duplicating documentation. Please use the single source of truth:

- Documentation → 02-Azure-Learning-Guides → `AZURE_DEPLOYMENT_GUIDE.md`

Quick start (from repo root):

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
Set-Location R:\GitGetPavan\TestAppXY_OrderProcessingSystem
.
Resources\Azure-Deployment\test-enterprise-deployment.ps1 -Environment dev
```

Key scripts referenced by the guide:
- `bootstrap-enterprise-infra.ps1` → Baseline RG/Plan/WebApps and OIDC
- `provision-azure-sql.ps1` → Azure SQL server/db + connection strings
- `run-database-migrations.ps1` → EF migrations with SQL fallback
- `setup-appinsights-dev.ps1` → Workspace-based AI + diagnostics + auto-instrumentation
- `test-enterprise-deployment.ps1` → Orchestrates an end-to-end from-scratch test

For details, troubleshooting, and validation steps, see the main guide.
