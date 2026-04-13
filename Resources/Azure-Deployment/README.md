# Azure Deployment Scripts

This folder intentionally avoids duplicating documentation. Please use the single source of truth:

- `docs/guides/deployment/azure-deployment-guide.md`

Quick start (from repo root):

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
Set-Location Q:\GIT\TestAppXY_OrderProcessingSystem
.\Resources\Azure-Deployment\test-enterprise-deployment.ps1 -Environment dev
```

Shared branch policy for Azure deployment scripts:
- `branch-policy.json` -> script-side source of truth for branch-to-environment defaults
- `branch-policy.ps1` -> helper functions used by OIDC, bootstrap, and validation scripts

Current default policy:
- `dev` branch -> `dev` environment
- `staging` branch -> `staging` environment
- `main` branch -> `prod` environment

GitHub workflow YAML still enforces the same mapping explicitly. If branch governance changes, update the workflow guards and the shared policy file together.

Key scripts referenced by the guide:
- `bootstrap-enterprise-infra.ps1` → Baseline RG/Plan/WebApps and OIDC
- `provision-azure-sql.ps1` → Azure SQL server/db + SQL Entra admin + passwordless app connection strings
- `run-database-migrations.ps1` → EF migrations with SQL fallback
- `setup-appinsights-dev.ps1` → Workspace-based API App Insights + API auto-instrumentation + API/UI diagnostics to Log Analytics
- `test-enterprise-deployment.ps1` → Orchestrates an end-to-end from-scratch test

For details, troubleshooting, and validation steps, see the main guide.
