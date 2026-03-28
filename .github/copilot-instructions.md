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
| `XYDataLabs.OrderProcessingSystem.API` | ASP.NET Core Web API — thin controllers, composition root, Swagger |
| `XYDataLabs.OrderProcessingSystem.UI` | ASP.NET Core MVC — presentation layer |
| `XYDataLabs.OrderProcessingSystem.Application` | Hand-rolled CQRS (ICommand/IQuery/IDispatcher), DTOs, pipeline behaviors |
| `XYDataLabs.OrderProcessingSystem.Domain` | Core entities, domain logic (DDD) — zero dependencies |
| `XYDataLabs.OrderProcessingSystem.Infrastructure` | EF Core, SQL Server, data access |
| `XYDataLabs.OrderProcessingSystem.SharedKernel` | Result<T>, constants, observability, multi-tenancy |
| `XYDataLabs.OpenPayAdapter` | OpenPay payment integration |

### Test Projects (under `tests/`)

| Project | Role |
|---------|------|
| `XYDataLabs.OrderProcessingSystem.Domain.Tests` | Entity unit tests (xUnit, FluentAssertions) |
| `XYDataLabs.OrderProcessingSystem.Application.Tests` | CQRS handler unit tests (xUnit, Moq, Bogus) |
| `XYDataLabs.OrderProcessingSystem.API.Tests` | Controller unit tests |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests` | End-to-end tests (Testcontainers + WebApplicationFactory) |
| `XYDataLabs.OrderProcessingSystem.Architecture.Tests` | NetArchTest layer boundary enforcement |

---

## 3. Repository Directory Layout

```
/
├── .github/
│   ├── app-manifest.json          # GitHub App manifest (permissions config)
│   ├── copilot-instructions.md    # ← THIS FILE (Copilot context)
│   └── workflows/                 # 11 GitHub Actions workflows + 8 README docs
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
│   ├── Configuration/             # sharedsettings.{dev,stg,prod,local}.json
│   └── Docker/                    # start-docker.ps1 + docker-compose.{dev,stg,prod}.yml
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
├── tests/                         # All test projects (5 projects)
│   ├── XYDataLabs.OrderProcessingSystem.Domain.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.Application.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.API.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.Integration.Tests/
│   └── XYDataLabs.OrderProcessingSystem.Architecture.Tests/
│
├── docs/
│   ├── runbooks/                  # Operations runbooks
│   └── architecture/decisions/    # ADRs (ADR-000 through ADR-010)
│
├── TROUBLESHOOTING-INDEX.md       # ← Quick troubleshooting guide with links
├── ARCHITECTURE-EVOLUTION.md      # 14-phase monolith → microservices roadmap
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

## 4. GitHub Actions Workflows (11 workflows)

All workflows live in `.github/workflows/`. Each has a companion `README-*.md` in the same folder.

| Workflow file | Name | Trigger | Purpose |
|---------------|------|---------|---------|
| `azure-initial-setup.yml` | Azure Initial Setup | Manual dispatch | **One-time setup**: Phase 0 (GitHub App), Phase 1a (OIDC), Phase 1b (secrets). Run once per repository. |
| `azure-bootstrap.yml` | Azure Bootstrap & Deploy | Manual dispatch | **Day-to-day**: Phase 2 (infrastructure), API/UI deploy, Phase X (cleanup). Requires Initial Setup first. |
| `configure-github-secrets.yml` | Configure GitHub Secrets | Called by initial-setup | GitHub App validation, OIDC secret configuration (can run independently for troubleshooting). |
| `infra-deploy.yml` | Deploy Azure Infrastructure | Push to dev/staging/main or manual | Deploys Bicep IaC with what-if dry-run support. |
| `validate-deployment.yml` | Pre-Deployment Validation | Called by `infra-deploy` or manually | Reusable workflow: Bicep what-if, OIDC verification, SharedSettings diff. |
| `test-validate-deployment.yml` | Test Pre-Deployment Validation | Manual or PR | Tests the validation workflow independently. |
| `deploy-api-to-azure.yml` | Deploy API to Azure App Service | Push to dev/staging/main (API paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `deploy-ui-to-azure.yml` | Deploy UI to Azure App Service | Push to dev/staging/main (UI paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `deploy-and-verify.yml` | Deploy and Verify (Secure Config) | Push to dev/main/stg or manual | Full end-to-end: infra + app deploy + post-deploy health verification |
| `docker-health.yml` | Docker Startup Health | Push to main, PR to main | Validates `Resources/Docker/start-docker.ps1` smoke test |
| `validate-adrs.yml` | Validate ADR Markdown | Push/PR (ADR/script/config paths) or manual | Markdownlint format + frontmatter schema (filename, H1, `**Status:**`, valid status word) |

### Branch → Environment Mapping

| Branch | Environment | Azure resource suffix |
|--------|-------------|-----------------------|
| `dev` | dev | `-dev` |
| `staging` | staging | `-stg` |
| `main` | prod | `-prod` |

### Workflow Split — Two Workflows

Setup and day-to-day operations are split into two focused workflows:

| Workflow | Phases | Default inputs |
|----------|--------|---------------|
| **Azure Initial Setup** (`azure-initial-setup.yml`) | Phase 0, 1a, 1b | All enabled, environment=`all` |
| **Azure Bootstrap & Deploy** (`azure-bootstrap.yml`) | Phase 2, Deploy, Phase X | All enabled except cleanup, environment=`dev` |

#### Phase Summary

| Phase | Workflow | Input flag | What it does |
|-------|----------|-----------|--------------|
| **Phase 0** | Initial Setup | `setupGitHubApp = true` | Shows GitHub App creation instructions. |
| **Phase 1a** | Initial Setup | `setupOidc = true` | Creates/updates Microsoft Entra ID App Registration + federated OIDC credentials via `setup-github-oidc.ps1`. Always runs in `dev` environment context. |
| **Phase 1b** | Initial Setup | `configureSecrets = true` | Calls `configure-github-secrets.yml` to store OIDC values as GitHub repo/env secrets using the GitHub App token. |
| **Phase 2** | Bootstrap & Deploy | `bootstrapInfra = true` | Runs `bootstrap-enterprise-infra.ps1` — resource group, App Service, SQL, Key Vault. |
| **Phase 2** | Bootstrap & Deploy | `deployApi / deployUi` | Dispatches `deploy-api-to-azure.yml` / `deploy-ui-to-azure.yml`. **Blocked** if the bootstrap job for the target environment failed. |
| **Phase X** | Bootstrap & Deploy | `cleanupInfra = true` | ⚠️ **DESTRUCTIVE**: Stops and deletes App Services, then deletes the entire Resource Group. |

### Phase 1a + 1b — One-Time OIDC Prerequisite

Phase 1a and Phase 1b are **one-time setup steps** that must complete before Phase 2 or Phase X
can authenticate with Azure. They create the OIDC trust between GitHub and Azure:

| Step | What it creates |
|------|-----------------|
| **Phase 1a** | Azure AD App Registration + federated identity credentials (`environment:dev`, `environment:staging`, `environment:prod`, branch refs) |
| **Phase 1b** | GitHub environment secrets (`AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`) for dev, staging, and prod |

**How to run (recommended — one-time per repository):**
1. Go to **Actions → Azure Initial Setup → Run workflow**
2. All defaults are correct (environment=`all`, Phase 1a + 1b enabled)
3. Click **Run workflow** and wait for completion

> **Note:** `setup-oidc` always uses `environment: dev` context (hardcoded) because all environments
> share the same Azure AD App Registration.

### Deployment Guard

The `trigger-deployments` job depends on bootstrap job results. When `bootstrapInfra` is selected,
API/UI deployments are **blocked** unless the bootstrap job for the target environment succeeds.
If the Azure Initial Setup workflow was never run, bootstrap fails at credential validation and
deployments are automatically prevented.

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

Required repository secrets (set by Azure Initial Setup): `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`.

Required for GitHub App token (set in Phase 0 of Azure Initial Setup): `APP_ID`, `APP_PRIVATE_KEY`.

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
| `bootstrap-enterprise-infra.ps1` | **Main bootstrap**: resource group, App Service Plan, Web Apps, App Insights, Key Vault + managed identity, OIDC |
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

`Resources/Configuration/sharedsettings.{dev,stg,prod,local}.json` — loaded by `appsettings.json`
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

Key Vault (`kv-orderproc-{dev|stg|prod}`) holds application secrets at runtime. The API uses managed
identity to access Key Vault without credentials in config files.

> **Note**: Azure resource names for staging use the abbreviated suffix `stg` (e.g. `rg-orderprocessing-stg`,
> `kv-orderproc-stg`), not `staging`. The workflow environment name remains `staging` but all scripts
> map it internally via `$envSuffix = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }`.

---

## 8. Local Development

**First-time setup (after fresh clone):** Run `scripts/setup-local.ps1` once — creates `.env.local`, sets `dotnet user-secrets`, trusts HTTPS dev cert. VS Code will auto-prompt via the `runOn: folderOpen` task. Or run `/XYDataLabs-setup-local` in Copilot Chat.

```powershell
# First-time setup
.\scripts\setup-local.ps1

# Visual Studio F5 (recommended for debugging)
# API: http://localhost:5010/swagger  |  UI: http://localhost:5012

# Docker — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Docker — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

Port allocations: Local VS (5010–5013) · Docker dev (5020–5023) · Docker stg (5030–5033) · Prod (5040–5043).

---

## 9. Copilot Prompts, Instructions & Agents

### Instruction files (auto-attach by file pattern)
| File | Applies to |
|------|------------|
| `.github/instructions/clean-architecture.instructions.md` | `**/*.cs`, `**/*.csproj` |
| `.github/instructions/ef-migrations.instructions.md` | `**/Infrastructure/**`, `**/Migrations/**` |
| `.github/instructions/multitenant-payment-schema.instructions.md` | `**/Domain/Entities/**/*.cs`, `**/Application/DTO/**/*.cs`, `**/Application/Features/Payments/**/*.cs`, `**/Infrastructure/**/*.cs`, related UI/API/test files |
| `.github/instructions/azure-workflows.instructions.md` | `**/.github/workflows/**` |
| `.github/instructions/bicep.instructions.md` | `**/infra/**`, `**/*.bicep` |
| `.github/instructions/curriculum.instructions.md` | `**/*CURRICULUM*`, `**/05-Self-Learning/**` |
| `.github/instructions/architecture.instructions.md` | `**/docs/architecture/**`, `**/*ADR*` |

### Instruction auto-injection matrix

When editing a file, multiple instruction files may fire simultaneously based on overlapping `applyTo` patterns.
This matrix shows which instructions auto-attach for common file locations:

| File location | clean-arch | ef-migrations | multitenant | azure-workflows | bicep | architecture | curriculum |
|---------------|:----------:|:-------------:|:-----------:|:---------------:|:-----:|:------------:|:----------:|
| `Domain/Entities/*.cs` | ✓ | | ✓ | | | | |
| `Application/Features/**/*.cs` | ✓ | | ✓ | | | | |
| `Application/DTO/**/*.cs` | ✓ | | ✓ | | | | |
| `Infrastructure/**/*.cs` | ✓ | ✓ | ✓ | | | | |
| `Infrastructure/Migrations/*` | ✓ | ✓ | ✓ | | | | |
| `API/Controllers/*.cs` | ✓ | | ✓ | | | | |
| `SharedKernel/**/*.cs` | ✓ | | | | | | |
| `tests/Architecture.Tests/*.cs` | ✓ | | ✓ | | | | |
| `.github/workflows/*.yml` | | | | ✓ | | | |
| `infra/**/*.bicep` | | | | | ✓ | | |
| `docs/architecture/decisions/*` | | | | | | ✓ | |
| `Documentation/05-Self-Learning/*` | | | | | | | ✓ |

### Custom agents (select in VS Code Chat agent picker)

| Agent | File | Use when |
|-------|------|----------|
| Azure DevOps | `.github/agents/azure-devops.agent.md` | Working on workflows, Bicep, PowerShell scripts, Docker, OIDC config |
| CQRS Backend | `.github/agents/cqrs-backend.agent.md` | Working on C# domain/application/infrastructure code, CQRS patterns, EF Core |
| Code Reviewer | `.github/agents/code-reviewer.agent.md` | Reviewing changes for architecture compliance, security, tenant safety (read-only) |

### Reusable agent prompts (type in VS Code Chat → Agent mode)
| Prompt | Command | Purpose |
|--------|---------|--------|
| New Feature Workflow | `/XYDataLabs-new-feature` | Orchestrates end-to-end feature development: entity → CQRS → migration → controller → tests → review → commit → payment verification (conditional). Enforces mandatory 13-step workflow with multitenant support. |
| Day Complete Router | `/XYDataLabs-day-complete` | After each curriculum day — routes updates to all correct documents, suggests commit |
| Completion Check | `/XYDataLabs-completion-check` | After any feature, task, script, or fix — 6-category quality gate: documented? guardrailed? unit tested? integration tested? automated? context current? |
| Local Setup | `/XYDataLabs-setup-local` | After a fresh git clone — runs setup-local.ps1, summarises VS F5 and Docker next steps |
| SQL Local Access | `/XYDataLabs-sql-local-access` | Opens or closes Azure SQL firewall for local IP after a fresh bootstrap/deploy. Prints SSMS connection details. |
| Context Audit | `/XYDataLabs-context-audit` | Detects stale AI context by diffing memory files and copilot-instructions against the actual codebase. Run periodically or after major refactors. |

| Log + DB Correlation | `/XYDataLabs-verify-db-logs` | After any payment run on any env/profile — reads today's physical log files, extracts charge IDs automatically, runs DB queries, and produces a correlated API log → UI log → DB pass/fail report. |
| ADR Validation | `/XYDataLabs-validate-adrs` | Before committing changes to any ADR — runs frontmatter schema check + markdownlint locally; documents how to toggle the CI counterpart. |

> **Quick prompt tip:** `Ctrl+Shift+I` → select Agent mode → type `/XYDataLabs-new-feature`, `/XYDataLabs-completion-check`, `/XYDataLabs-setup-local`, `/XYDataLabs-day-complete`, `/XYDataLabs-sql-local-access`, `/XYDataLabs-context-audit`, `/XYDataLabs-verify-db-logs`, or `/XYDataLabs-validate-adrs`
>
> **Prompt reference:** See `.github/prompts/README.md` for when to use each prompt, prerequisites, and operational notes.
>
> **Maintenance rule:** When adding or changing any reusable prompt in `.github/prompts/`, also update `.github/prompts/README.md` and any operational docs that point users to required manual post-deploy steps.
> When adding or changing any agent in `.github/agents/`, also update the Custom agents table above.

---

## 10. Key Documentation Files

| File | Where | What it covers |
|------|-------|---------------|
| `TROUBLESHOOTING-INDEX.md` | Root | Quick links for common GitHub App / OIDC / workflow errors |
| `ARCHITECTURE.md` | Root | Binding tenant, payment identifier, migration, and test standard for future model creation |
| `ARCHITECTURE-EVOLUTION.md` | Root | 14-phase roadmap: Phases 1-6 ✅ complete, Phase 7 next 📅 |
| `AZURE-PROGRESS-EVALUATION.md` | Root | Learning progress weeks 1–10, next-step guides |
| `AZURE-TOP-7-SERVICES-ANALYSIS.md` | Root | Analysis of 7 key Azure services used in this project |
| `GITHUB-APP-DELETION-SUMMARY.md` | Root | GitHub App automation and deletion procedures |
| `GITHUB-APP-QUICK-REFERENCE.md` | Root | GitHub App CLI commands cheat sheet |
| `IMPLEMENTATION-COMPLETE.md` | Root | GitHub App implementation summary |
| `.github/workflows/README.md` | Workflows | Workflow overview, secrets, path triggers |
| `.github/workflows/README-AZURE-BOOTSTRAP.md` | Workflows | Bootstrap & Deploy workflow deep-dive |
| `.github/workflows/README-AZURE-INITIAL-SETUP.md` | Workflows | Initial Setup workflow (Phase 0/1a/1b) |
| `.github/workflows/README-AZURE-BOOTSTRAP-SETUP.md` | Workflows | Step-by-step bootstrap setup guide |
| `.github/workflows/README-CONFIGURE-GITHUB-SECRETS.md` | Workflows | Secrets workflow detail |
| `.github/workflows/README-INFRA-DEPLOY.md` | Workflows | Infrastructure deployment workflow guide |
| `.github/workflows/README-VALIDATE-DEPLOYMENT.md` | Workflows | Pre-deployment validation workflow detail |
| `.github/workflows/README-TEST-VALIDATE-DEPLOYMENT.md` | Workflows | Test pre-deployment validation workflow detail |
| `Documentation/README.md` | Documentation/ | Documentation hub with links to all guides |
| `Documentation/Operations-Quick-Links-README.md` | Documentation/ | Quick reference links for operations tasks |
| `Documentation/QUICK-COMMAND-REFERENCE.md` | Documentation/ | Command cheat sheet for Azure, Git, Docker |
| `Documentation/QUICK-START-AZURE-BOOTSTRAP.md` | Documentation/ | Quick-start guide for Azure bootstrap process |
| `Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md` | Documentation/ | Complete Azure deployment strategy |
| `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md` | Documentation/ | GitHub App quick setup guide |
| `Documentation/GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md` | Documentation/ | Why bootstrap is split into separate workflows |
| `Resources/Azure-Deployment/README.md` | Resources/ | Script index and usage |

---

## 11. Common Troubleshooting Patterns

| Symptom | First place to check |
|---------|---------------------|
| Workflow exits with code 1 on GitHub App step | `TROUBLESHOOTING-INDEX.md` — check if `APP_ID`/`APP_PRIVATE_KEY` are present; `gh api /app` requires JWT, not installation token |
| `AADSTS700016` during Azure login | Federated credential missing for branch — run `fix-federated-credential.ps1` |
| `AADSTS700213` during Azure login | Federated credential missing for environment — run `Azure Initial Setup` workflow with `environment=all`. Bootstrap jobs include a `Diagnose Azure Login Failure` step that detects this automatically and prints remediation steps in the workflow summary. |
| `DEPLOYMENT BLOCKED` in bootstrap | OIDC not configured — run `Azure Initial Setup` workflow with `environment=all` first |
| API/UI deployment skipped after bootstrap failure | Deployment guard blocks dispatches when bootstrap fails — fix the bootstrap error first |
| Secrets show ❌ Missing | Ensure workflow runs with correct environment (dev/staging/prod), not "all" |
| Bootstrap infra fails | Check OIDC secrets are configured (`Azure Initial Setup` must run before `Azure Bootstrap & Deploy`) |
| `APP_INSTALLATION_ID` errors | Not needed — auto-discovered; remove any manual configuration |
| Branch/env mismatch error | Use `dev` branch for `dev` env, `staging` for `staging`, `main` for `prod`. |
| What-if fails on Bicep | Run `validate-deployment.yml` independently to see full error output |
