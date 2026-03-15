# GitHub Copilot — Repository Reference Guide

This file provides GitHub Copilot and other AI assistants with a structured overview of the
**XYDataLabs.OrderProcessingSystem** repository so that every session starts from a common
understanding of the codebase.

---

## 1. Repository Purpose

A **.NET 8 Clean Architecture** order-processing application used as a **learning project** to
practice Azure cloud deployment, CI/CD automation, and enterprise DevOps patterns.

- **Production URL (dev)**: `https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger`
- **UI (dev)**: `https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net`
- **GitHub repository**: `https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem`

---

## 2. Solution — .NET Projects

| Project | Role |
|---------|------|
| `XYDataLabs.OrderProcessingSystem.API` | ASP.NET Core Web API — orders, customers, payments, Swagger |
| `XYDataLabs.OrderProcessingSystem.UI` | ASP.NET Core MVC — presentation layer |
| `XYDataLabs.OrderProcessingSystem.Application` | Use cases, DTOs, MediatR |
| `XYDataLabs.OrderProcessingSystem.Domain` | Core entities, domain logic (DDD) |
| `XYDataLabs.OrderProcessingSystem.Infrastructure` | EF Core, SQL Server, data access |
| `XYDataLabs.OrderProcessingSystem.Utilities` | Shared helpers and cross-cutting concerns |
| `XYDataLabs.OpenPayAdapter` | OpenPay payment integration |
| `XYDataLabs.OrderProcessingSystem.UnitTest` | xUnit, Moq, Bogus, FluentAssertions tests |

---

## 3. Repository Directory Layout

```
/
├── .github/
│   ├── app-manifest.json          # GitHub App manifest (permissions config)
│   ├── copilot-instructions.md    # ← THIS FILE (Copilot context)
│   └── workflows/                 # 9 GitHub Actions workflows + 8 README docs
│
├── Documentation/                 # All markdown documentation (organised)
│   ├── README.md                  # Main documentation hub
│   ├── 01-Project-Overview/       # Project setup and how-to-run
│   ├── 02-Azure-Learning-Guides/  # Azure deployment, Docker, App Insights
│   ├── 03-Configuration-Guides/   # GitHub App, Key Vault, secrets setup
│   ├── 04-Enterprise-Architecture/# ACA migration plan, weekly learning plan
│   ├── 05-Self-Learning/          # 18-week Azure curriculum + progress tracking
│   ├── GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md  # Workflow separation rationale
│   ├── Operations-Quick-Links-README.md             # Quick operations reference links
│   ├── QUICK-COMMAND-REFERENCE.md                  # Command cheat sheet
│   ├── QUICK-START-AZURE-BOOTSTRAP.md              # Quick-start bootstrap guide
│   └── Archive/                   # Historical / superseded documentation
│
├── Resources/
│   ├── Azure-Deployment/          # 27 PowerShell automation scripts (see §6)
│   ├── BuildConfiguration/        # BannedSymbols, CodeAnalysis.ruleset, MSBuild props
│   ├── Configuration/             # sharedsettings.{dev,uat,prod,local}.json
│   └── Docker/                    # start-docker.ps1 + docker-compose.{dev,uat,prod}.yml
│
├── bicep/                         # Bicep IaC for subscription-scoped deployment
│   ├── appservice-with-kv.bicep
│   └── parameters/                # {dev,staging,prod}.parameters.json
│
├── infra/                         # Bicep IaC for resource-group-scoped deployment
│   ├── main.bicep
│   ├── modules/
│   └── parameters/                # {dev,staging,prod}.json
│
├── scripts/                       # Utility scripts (GitHub App setup, secrets)
│   ├── setup-github-app-from-manifest.ps1
│   ├── configure-secrets-and-run.ps1
│   └── validate-github-app-config.ps1
│
├── docs/runbooks/                 # Operations runbooks
│
├── TROUBLESHOOTING-INDEX.md       # ← Quick troubleshooting guide with links
├── ARCHITECTURE-EVOLUTION.md      # Monolith → Microservices roadmap
├── AZURE-PROGRESS-EVALUATION.md   # Learning progress tracker (weeks 1–10)
├── AZURE-TOP-7-SERVICES-ANALYSIS.md  # Analysis of 7 key Azure services
├── GITHUB-APP-DELETION-SUMMARY.md    # GitHub App automation and deletion procedures
├── GITHUB-APP-QUICK-REFERENCE.md  # GitHub App commands quick reference
├── IMPLEMENTATION-COMPLETE.md     # GitHub App implementation summary
├── test-bootstrap-dry-run.ps1     # Dry-run test for bootstrap workflow
├── test-pre-deployment-validation.ps1  # Local test for pre-deployment validation
├── test-recommended-next-steps.ps1     # Test recommended next steps after bootstrap
└── XYDataLabs.OrderProcessingSystem.sln
```

---

## 4. GitHub Actions Workflows (9 workflows)

All workflows live in `.github/workflows/`. Each has a companion `README-*.md` in the same folder.

| Workflow file | Name | Trigger | Purpose |
|---------------|------|---------|---------|
| `azure-bootstrap.yml` | Azure Bootstrap Setup | Manual dispatch | **Master orchestration**: Phase 0 (GitHub App), Phase 1 (OIDC + secrets), Phase 2 (infra + deploy). Entry point for first-time setup. |
| `configure-github-secrets.yml` | Configure GitHub Secrets | Manual or called by bootstrap | GitHub App validation, OIDC secret configuration (can run independently for troubleshooting). |
| `infra-deploy.yml` | Deploy Azure Infrastructure | Push to dev/staging/main or manual | Deploys Bicep IaC with what-if dry-run support. |
| `validate-deployment.yml` | Pre-Deployment Validation | Called by `infra-deploy` or manually | Reusable workflow: Bicep what-if, OIDC verification, SharedSettings diff. |
| `test-validate-deployment.yml` | Test Pre-Deployment Validation | Manual or PR | Tests the validation workflow independently. |
| `deploy-api-to-azure.yml` | Deploy API to Azure App Service | Push to dev/staging/main (API paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `deploy-ui-to-azure.yml` | Deploy UI to Azure App Service | Push to dev/staging/main (UI paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `deploy-and-verify.yml` | Deploy and Verify (Secure Config) | Push to dev/main/uat or manual | Full end-to-end: infra + app deploy + post-deploy health verification |
| `docker-health.yml` | Docker Startup Health | Push to main, PR to main | Validates `Resources/Docker/start-docker.ps1` smoke test |

### Branch → Environment Mapping

| Branch | Environment | Azure resource suffix |
|--------|-------------|-----------------------|
| `dev` | dev | `-dev` |
| `staging` | staging | `-stg` |
| `main` | prod | `-prod` |

### Azure Bootstrap Workflow — Phase Summary

| Phase | Input flag | What it does |
|-------|-----------|--------------|
| **Phase 0** | `setupGitHubApp = true` | Shows GitHub App creation instructions. Requires `APP_ID` + `APP_PRIVATE_KEY` secrets to already exist to show "Phase 0 configured correctly" banner. |
| **Phase 1** | `setupOidc = true` | Creates/updates Microsoft Entra ID App Registration + federated OIDC credentials via `setup-github-oidc.ps1`. |
| **Phase 1** | `configureSecrets = true` | Calls `configure-github-secrets.yml` to store OIDC values as GitHub repo/env secrets using the GitHub App token. |
| **Phase 2** | `bootstrapInfra = true` | Runs `bootstrap-enterprise-infra.ps1` — resource group, App Service, SQL, Key Vault. |
| **Phase 2** | `deployApi / deployUi` | Calls `run-database-migrations.ps1` then deploys binaries. |

### OIDC Authentication Pattern

Workflows use **passwordless OIDC** (not stored secrets):
```yaml
permissions:
  id-token: write   # request OIDC token
  contents: read
steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
      tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
      subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}
```

Required repository secrets (set by Phase 1): `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`.

Required for GitHub App token (set in Phase 0): `APP_ID`, `APP_PRIVATE_KEY`.

---

## 5. Infrastructure as Code

| Folder | Scope | Used by |
|--------|-------|---------|
| `infra/` | Subscription-level | `infra-deploy.yml`, `validate-deployment.yml` |
| `bicep/` | Resource-group-level | `deploy-and-verify.yml` |

Parameter files follow the pattern `{environment}.json` / `{environment}.parameters.json`.

---

## 6. PowerShell Scripts — `Resources/Azure-Deployment/`

| Script | Purpose |
|--------|---------|
| `bootstrap-enterprise-infra.ps1` | **Main bootstrap**: resource group, App Service, SQL, Key Vault, OIDC |
| `setup-github-oidc.ps1` | Create/update Entra ID app + federated OIDC credentials |
| `configure-github-secrets.ps1` | Store OIDC values as GitHub repo/env secrets |
| `configure-app-environment.ps1` | Set App Service application settings per environment |
| `enable-managed-identity.ps1` | Enable system-assigned managed identity on App Services |
| `provision-azure-sql.ps1` | Provision SQL Server + database |
| `populate-keyvault-secrets.ps1` | Store application secrets in Key Vault |
| `run-database-migrations.ps1` | Execute EF Core migrations against target environment |
| `manage-appservice-slots.ps1` | Blue-green deployment slot management |
| `wait-appservice-ready.ps1` | Poll until App Service is healthy |
| `verify-azure-setup.ps1` | Verify all Azure resources are configured correctly |
| `verify-app-insights.ps1` | Verify Application Insights configuration |
| `verify-deployment-endpoints.ps1` | Health-check API and UI endpoints |
| `verify-oidc-credentials.ps1` | Verify GitHub OIDC federated credentials exist for all environments |
| `check-app-registration.ps1` | Verify Azure AD app registration exists |
| `fix-federated-credential.ps1` | Fix/recreate OIDC federated credentials |
| `diagnose-keyvault-access.ps1` | Diagnose Key Vault access issues |
| `validate-parameters-whatif.ps1` | Bicep what-if analysis for infra changes |
| `validate-sharedsettings-diff.ps1` | Check consistency across environment config files |
| `validate-bootstrap-logic.ps1` | Validate bootstrap script logic before execution |
| `validate-workflow-config.ps1` | Validate workflow parameter configuration |
| `setup-appinsights-dev.ps1` | Dev-specific Application Insights setup |
| `inspect-and-cleanup-appinsights-managed-rg.ps1` | Clean App Insights managed resource group |
| `query-app-insights-errors.ps1` | Query application errors from App Insights |
| `test-retry-logic.ps1` | Test retry mechanism in scripts |
| `test-branch-env-mapping.ps1` | Test branch-to-environment mapping |
| `test-enterprise-deployment.ps1` | End-to-end enterprise deployment test |

---

## 7. Configuration Strategy

### Multi-environment settings

`Resources/Configuration/sharedsettings.{dev,uat,prod,local}.json` — loaded by `appsettings.json`
via the `ASPNETCORE_ENVIRONMENT` variable.

### GitHub App vs OIDC Secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `APP_ID` | Repository | GitHub App numeric ID (for token generation) |
| `APP_PRIVATE_KEY` | Repository | GitHub App private key (.pem content) |
| `AZUREAPPSERVICE_CLIENTID` | Repository + Environments | OIDC Client ID for Azure login |
| `AZUREAPPSERVICE_TENANTID` | Repository + Environments | Azure Tenant ID |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Repository + Environments | Azure Subscription ID |

> **Note**: `APP_INSTALLATION_ID` is **not** required — it is auto-discovered at runtime.

### Key Vault integration

Key Vault (`kv-orderproc-{env}`) holds application secrets at runtime. The API uses managed
identity to access Key Vault without credentials in config files.

---

## 8. Local Development

```powershell
# Visual Studio F5 (recommended for debugging)
# API: http://localhost:5010/swagger  |  UI: http://localhost:5012

# Docker — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Docker — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

Port allocations: Local VS (5010–5013) · Docker dev (5020–5023) · UAT (5030–5033) · Prod (5040–5043).

---

## 9. Key Documentation Files

| File | Where | What it covers |
|------|-------|---------------|
| `TROUBLESHOOTING-INDEX.md` | Root | Quick links for common GitHub App / OIDC / workflow errors |
| `ARCHITECTURE-EVOLUTION.md` | Root | Phase 1 (monolith ✅) → Phase 2 (YARP microservices 📅) |
| `AZURE-PROGRESS-EVALUATION.md` | Root | Learning progress weeks 1–10, next-step guides |
| `AZURE-TOP-7-SERVICES-ANALYSIS.md` | Root | Analysis of 7 key Azure services used in this project |
| `GITHUB-APP-DELETION-SUMMARY.md` | Root | GitHub App automation and deletion procedures |
| `GITHUB-APP-QUICK-REFERENCE.md` | Root | GitHub App CLI commands cheat sheet |
| `IMPLEMENTATION-COMPLETE.md` | Root | GitHub App implementation summary |
| `.github/workflows/README.md` | Workflows | Workflow overview, secrets, path triggers |
| `.github/workflows/README-AZURE-BOOTSTRAP.md` | Workflows | Bootstrap workflow deep-dive |
| `.github/workflows/README-CONFIGURE-GITHUB-SECRETS.md` | Workflows | Secrets workflow detail |
| `Documentation/README.md` | Documentation/ | Documentation hub with links to all guides |
| `Documentation/Operations-Quick-Links-README.md` | Documentation/ | Quick reference links for operations tasks |
| `Documentation/QUICK-COMMAND-REFERENCE.md` | Documentation/ | Command cheat sheet for Azure, Git, Docker |
| `Documentation/QUICK-START-AZURE-BOOTSTRAP.md` | Documentation/ | Quick-start guide for Azure bootstrap process |
| `Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md` | Documentation/ | Complete Azure deployment strategy |
| `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md` | Documentation/ | GitHub App quick setup guide |
| `Documentation/GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md` | Documentation/ | Why bootstrap is split into separate workflows |
| `Resources/Azure-Deployment/README.md` | Resources/ | Script index and usage |

---

## 10. Common Troubleshooting Patterns

| Symptom | First place to check |
|---------|---------------------|
| Workflow exits with code 1 on GitHub App step | `TROUBLESHOOTING-INDEX.md` — check if `APP_ID`/`APP_PRIVATE_KEY` are present; `gh api /app` requires JWT, not installation token |
| `AADSTS700016` during Azure login | Federated credential missing for branch — run `fix-federated-credential.ps1` |
| Secrets show ❌ Missing | Ensure workflow runs with correct environment (dev/staging/prod), not "all" |
| Bootstrap infra fails | Check OIDC secrets are configured (Phase 1 must run before Phase 2) |
| `APP_INSTALLATION_ID` errors | Not needed — auto-discovered; remove any manual configuration |
| Branch/env mismatch error | Use `dev` branch for `dev` env, `staging` for `staging`, `main` for `prod` |
| What-if fails on Bicep | Run `validate-deployment.yml` independently to see full error output |
