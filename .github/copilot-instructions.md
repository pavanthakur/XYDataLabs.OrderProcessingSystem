# GitHub Copilot — Repository Reference Guide

This file provides GitHub Copilot and other AI assistants with a structured overview of the
**XYDataLabs.OrderProcessingSystem** repository so that every session starts from a common
understanding of the codebase.

> **Session start — do this first, every time:**
> Use the memory tool to read `/memories/repo/active-work.md` before responding to the first
> message. It contains current phase, last session summary, and pending next actions.
> Skip if the user's first message explicitly says to ignore it.

---

## 1. Repository Purpose

A **.NET 8 Clean Architecture** order-processing application used as a **learning project** to
practice Azure cloud deployment, CI/CD automation, and enterprise DevOps patterns.

- **Production URL (dev)**: `https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger`
- **UI (dev)**: `https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net`
- **GitHub repository**: `https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem`

---

## 2. Solution — .NET Projects + Frontend Workspace

| Project | Role |
|---------|------|
| `XYDataLabs.OrderProcessingSystem.API` | ASP.NET Core Web API — thin controllers, composition root, Swagger |
| `XYDataLabs.OrderProcessingSystem.Application` | Hand-rolled CQRS (ICommand/IQuery/IDispatcher), DTOs, pipeline behaviors |
| `XYDataLabs.OrderProcessingSystem.Domain` | Core entities, domain logic (DDD) — zero dependencies |
| `XYDataLabs.OrderProcessingSystem.Gateway` | YARP gateway for local modular routing and frontend/API entry-point experiments |
| `XYDataLabs.OrderProcessingSystem.Infrastructure` | EF Core, SQL Server, data access |
| `XYDataLabs.OrderProcessingSystem.SharedKernel` | Result<T>, constants, observability, multi-tenancy |
| `XYDataLabs.OpenPayAdapter` | OpenPay payment integration |

Frontend workspace:
- `frontend/apps/web` — React + Vite + TypeScript SPA deployed to the Azure UI App Service
- `frontend/packages/api-sdk` — generated API client
- `frontend/packages/tenant-session` — runtime bootstrap and tenant header support

### Test Projects (under `tests/`)

| Project | Role |
|---------|------|
| `XYDataLabs.OrderProcessingSystem.Domain.Tests` | Entity unit tests (xUnit, FluentAssertions) |
| `XYDataLabs.OrderProcessingSystem.Application.Tests` | CQRS handler unit tests (xUnit, Moq, Bogus) |
| `XYDataLabs.OrderProcessingSystem.API.Tests` | Controller unit tests |
| `XYDataLabs.OrderProcessingSystem.Gateway.Tests` | Gateway routing and host-behavior tests |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests` | End-to-end tests (Testcontainers + WebApplicationFactory) |
| `XYDataLabs.OrderProcessingSystem.Architecture.Tests` | NetArchTest layer boundary enforcement |

---

## 3. Repository Directory Layout

```
/
├── .github/
│   ├── app-manifest.json          # GitHub App manifest (permissions config)
│   ├── copilot-instructions.md    # ← THIS FILE (Copilot context)
│   └── workflows/                 # 14 GitHub Actions workflows + companion README docs
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
├── automation/                    # Payment journey automation workspace and dry-run/reporting assets
│
├── frontend/                      # React web/mobile workspace + shared packages
│   ├── apps/
│   └── packages/
│
├── templates/                     # Layer 1 template source and packaging projects
│
├── tests/                         # All test projects (6 projects)
│   ├── XYDataLabs.OrderProcessingSystem.Domain.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.Application.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.API.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.Gateway.Tests/
│   ├── XYDataLabs.OrderProcessingSystem.Integration.Tests/
│   └── XYDataLabs.OrderProcessingSystem.Architecture.Tests/
│
├── docs/
│   ├── README.md                  # Canonical documentation hub
│   ├── DEVELOPER-OPERATING-MODEL.md # Guided reading order and maintenance rules
│   ├── architecture/decisions/    # ADRs (ADR-000 through ADR-018)
│   ├── guides/                    # Deployment, configuration, and development guides
│   ├── internal/                  # Active progress tracker and internal backlog
│   ├── learning/                  # Curriculum, implementation notes, learning reference
│   ├── reference/                 # Quick commands and operations navigation
│   └── runbooks/                  # Operational runbooks
│
├── TROUBLESHOOTING-INDEX.md       # ← Quick troubleshooting guide with links
├── ARCHITECTURE-EVOLUTION.md      # 14-phase monolith → microservices roadmap
├── XYDataLabs.OrderProcessingSystem.Gateway/ # YARP gateway project
├── test-bootstrap-dry-run.ps1     # Dry-run test for bootstrap workflow
├── test-pre-deployment-validation.ps1  # Local test for pre-deployment validation
├── test-recommended-next-steps.ps1     # Test recommended next steps after bootstrap
└── XYDataLabs.OrderProcessingSystem.sln
```

---

## 4. GitHub Actions Workflows (14 workflows)

All workflows live in `.github/workflows/`. Each has a companion `README-*.md` in the same folder.

| Workflow file | Name | Trigger | Purpose |
|---------------|------|---------|---------|
| `ci.yml` | CI - Build and Test | Pull requests to dev/staging/main | PR validation gate: restore, build, and run unit/architecture tests before merge. |
| `azure-initial-setup.yml` | Azure Initial Setup | Manual dispatch | **One-time setup**: Phase 0 (GitHub App), Phase 1a (OIDC), Phase 1b (secrets). Run once per repository. |
| `azure-bootstrap.yml` | Azure Bootstrap & Deploy | Manual dispatch | **Day-to-day**: Phase 2 (infrastructure), API/UI deploy, Phase X (cleanup). Requires Initial Setup first. |
| `configure-github-secrets.yml` | Configure GitHub Secrets | Called by initial-setup | GitHub App validation, OIDC secret configuration (can run independently for troubleshooting). |
| `infra-deploy.yml` | Deploy Azure Infrastructure | Push to dev/staging/main or manual | Deploys Bicep IaC with what-if dry-run support. |
| `validate-deployment.yml` | Pre-Deployment Validation | Called by `infra-deploy` or manually | Reusable workflow: Bicep what-if, OIDC verification, SharedSettings diff. |
| `test-validate-deployment.yml` | Test Pre-Deployment Validation | Manual or PR | Tests the validation workflow independently. |
| `deploy-api-to-azure.yml` | Deploy API to Azure App Service | Push to dev/staging/main (API paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `deploy-ui-to-azure.yml` | Deploy UI to Azure App Service | Push to dev/staging/main (UI paths) | Build → test → publish → Azure OIDC login → deploy → health check |
| `publish-template-package.yml` | Publish Template Package | Manual dispatch | Packs `XYDataLabs.SaaS.Templates`, validates the packaged `dotnet new` smoke flow, uploads the `.nupkg`, and optionally publishes it to NuGet.org or GitHub Packages |
| `validate-template-package-governance.yml` | Validate Template Package Governance | Pull requests for Layer 1 template changes or manual | Forces a `PackageVersion` decision for Layer 1 template changes and runs packaged smoke validation before merge |
| `validate-ai-customization.yml` | Validate AI Customization | Push/PR (shared AI asset paths) or manual | Validates shared Copilot instructions, prompts, agents, and AI governance docs/scripts stay in sync |
| `validate-adrs.yml` | Validate ADR Markdown | Push/PR (ADR/script/config paths) or manual | Markdownlint format + frontmatter schema (filename, H1, `**Status:**`, valid status word) |
| `validate-doc-links.yml` | Validate Docs Links | Push/PR (docs or validator paths) or manual | Validates local markdown links and heading anchors across the canonical `docs/` tree |

### Workflow Categories

| Category | Workflows | Usage |
|----------|-----------|-------|
| **Primary** | `ci.yml`, `azure-initial-setup.yml`, `azure-bootstrap.yml`, `deploy-api-to-azure.yml`, `deploy-ui-to-azure.yml` | Default paths for PR validation, initial setup, day-to-day deployment, and normal API/UI delivery |
| **Support** | `configure-github-secrets.yml`, `infra-deploy.yml`, `publish-template-package.yml`, `validate-template-package-governance.yml`, `validate-deployment.yml`, `test-validate-deployment.yml`, `validate-ai-customization.yml`, `validate-adrs.yml`, `validate-doc-links.yml` | Secondary validation, infra-only entrypoints, package publication, troubleshooting, and governance guardrails |

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

Phase details, OIDC setup steps, deployment guard, and secrets reference: see `.github/workflows/README-AZURE-INITIAL-SETUP.md` and `README-AZURE-BOOTSTRAP.md`.

---

## 5. Infrastructure as Code

| Folder | Scope | Used by |
|--------|-------|---------|
| `infra/` | Subscription-level | `infra-deploy.yml`, `validate-deployment.yml` |
| `bicep/` | Resource-group-level | Manual or ad hoc App Service/Key Vault deployments |

Parameter files follow the pattern `{environment}.json` / `{environment}.parameters.json`.

---

## 6. PowerShell Scripts — `Resources/Azure-Deployment/`

Full script reference: see `Resources/Azure-Deployment/README.md`.

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
| `AZUREAPPSERVICE_CLIENTID` | Environments | OIDC Client ID for Azure login |
| `AZUREAPPSERVICE_TENANTID` | Environments | Azure Tenant ID |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Environments | Azure Subscription ID |
| `OPENPAY_MERCHANT_ID` | Environments | OpenPay merchant ID — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates the target environment before proceeding |
| `OPENPAY_PRIVATE_KEY` | Environments | OpenPay private key — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates the target environment before proceeding |
| `OPENPAY_DEVICE_SESSION_ID` | Environments | OpenPay device session ID — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates the target environment before proceeding |
| `RAZORPAY_MERCHANT_ID` | Environments | Razorpay key ID (e.g. `rzp_test_…`) — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates the target environment before proceeding |
| `RAZORPAY_PRIVATE_KEY` | Environments | Razorpay key secret — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates the target environment before proceeding |
| `OPENPAY_WEBHOOK_SECRET` | Environments | OpenPay HMAC-SHA256 webhook signing secret — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates presence and pushes to Key Vault as `Webhooks--OpenPay--Secret`; without it all incoming OpenPay webhooks are rejected with HTTP 400 |
| `RAZORPAY_WEBHOOK_SECRET` | Environments | Razorpay HMAC-SHA256 webhook signing secret — **set manually** in GitHub Settings → Environments by an authorized person; bootstrap validates presence and pushes to Key Vault as `Webhooks--Razorpay--Secret`; without it all incoming Razorpay webhooks are rejected with HTTP 400 |

> **Note**: `APP_INSTALLATION_ID` is **not** required — it is auto-discovered at runtime.

> **Note**: OpenPay secrets must be added manually in GitHub Settings → Environments. Workflow dispatch inputs are not masked in logs and are not a secure channel for secrets. The target bootstrap job validates that all three OpenPay secrets are present in the selected environment before running infrastructure provisioning; if any are missing it fails with an actionable error and a link to the Environments page.

### Key Vault integration

Key Vault (`kv-orderprocessing-{dev|stg|prod}`) holds application secrets at runtime. The API uses managed
identity to access Key Vault without credentials in config files.

> **Note**: Azure resource names for staging use the abbreviated suffix `stg` (e.g. `rg-orderprocessing-stg`,
> `kv-orderprocessing-stg`), not `staging`. The workflow environment name remains `staging` but all scripts
> map it internally via `$envSuffix = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }`.

---

## 8. Local Development

**First-time setup (after fresh clone):** Run `scripts/setup-local.ps1` once — creates `.env.local`, sets `dotnet user-secrets`, trusts HTTPS dev cert. VS Code will auto-prompt via the `runOn: folderOpen` task. Or run `/XYDataLabs-setup-local` in Copilot Chat.

```powershell
# First-time setup
.\scripts\setup-local.ps1

# Visual Studio F5 (recommended for debugging)
# HTTP profile: API http://localhost:5010/swagger  |  UI http://localhost:5173
# HTTPS profile: API https://localhost:5011/swagger |  UI https://localhost:5174

# Docker — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Docker — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

Port allocations: Local VS API (5010–5011) + UI (5173–5174) · Docker dev (5020–5023) · Docker stg (5030–5033) · Prod (5040–5043).

---

## 9. Copilot Prompts, Instructions, Skills & Agents

### Instruction files (auto-attach by file pattern)
| File | Applies to |
|------|------------|
| `.github/instructions/clean-architecture.instructions.md` | `**/*.cs`, `**/*.csproj` |
| `.github/instructions/ef-migrations.instructions.md` | `**/Infrastructure/**`, `**/Migrations/**` |
| `.github/instructions/multitenant-payment-schema.instructions.md` | `**/Domain/Entities/**/*.cs`, `**/Application/DTO/**/*.cs`, `**/Application/Features/Payments/**/*.cs`, `**/Infrastructure/**/*.cs`, related UI/API/test files |
| `.github/instructions/azure-workflows.instructions.md` | `**/.github/workflows/**` |
| `.github/instructions/bicep.instructions.md` | `**/infra/**`, `**/*.bicep` |
| `.github/instructions/documentation-governance.instructions.md` | `**/docs/*.md`, `**/docs/**/*.md` |
| `.github/instructions/curriculum.instructions.md` | `**/*CURRICULUM*`, `**/docs/learning/curriculum/**` |
| `.github/instructions/architecture.instructions.md` | `**/docs/architecture/**`, `**/*ADR*` |

### Custom agents (select in VS Code Chat agent picker)

| Agent | File | Use when |
|-------|------|----------|
| Azure DevOps | `.github/agents/azure-devops.agent.md` | Working on workflows, Bicep, PowerShell scripts, Docker, OIDC config |
| CQRS Backend | `.github/agents/cqrs-backend.agent.md` | Working on C# domain/application/infrastructure code, CQRS patterns, EF Core |
| Code Reviewer | `.github/agents/code-reviewer.agent.md` | Reviewing changes for architecture compliance, security, tenant safety (read-only) |

### Repo-owned skills

| Skill | File | Use when |
|-------|------|----------|
| Azure Deployment Operations | `.github/skills/azure-deployment-operations/SKILL.md` | Working on Azure bootstrap, deployment workflows, OIDC validation, App Service rollout checks, Bicep preflight, or deployment troubleshooting |
| CQRS Backend Implementation | `.github/skills/cqrs-backend-implementation/SKILL.md` | Working on C# backend code: Domain entities, CQRS handlers, DTOs, Infrastructure data access, API controllers, migrations, or backend test coverage |
| Code Review Guardrails | `.github/skills/code-review-guardrails/SKILL.md` | Reviewing code changes for architecture compliance, tenant safety, security issues, CQRS correctness, migration safety, or missing backend test coverage |
| Completion Check Governance | `.github/skills/completion-check-governance/SKILL.md` | Closing out a task with the repo-standard completion gate: build, tests, secret scan, documentation, automation, Copilot-context checks, and deferral decisions |
| Context Audit Governance | `.github/skills/context-audit-governance/SKILL.md` | Detects stale AI context by diffing memory files, discovery surfaces, and repo facts against the live codebase |

### Reusable agent prompts (type in VS Code Chat → Agent mode)
| Prompt | Command | Purpose |
|--------|---------|--------|
| Day Start | `/XYDataLabs-day-start` | Start of every session — reads active-work.md and reports current phase, last session summary, pending actions, and key file paths. Zero exploration, zero token waste. |
| New Feature Workflow | `/XYDataLabs-new-feature` | Orchestrates end-to-end feature development: entity → CQRS → migration → controller → tests → review → commit → payment verification (conditional). Enforces mandatory 13-step workflow with multitenant support. |
| Day Complete Router | `/XYDataLabs-day-complete` | After each curriculum day or phase-freeze closeout — routes updates to all correct documents, syncs architecture status surfaces, and makes payment automation dry-run validation mandatory when automation scope changed before a phase-close commit |
| Completion Check | `/XYDataLabs-completion-check` | After any feature, task, script, or fix — 6-category quality gate: documented? guardrailed? unit tested? integration tested? automated, including payment automation dry-run matrix when relevant? context current? |
| Docker Start | `/XYDataLabs-docker-start` | Launches the supported Docker and local runtime profiles from one interactive entry point and prints the correct API/UI URLs. |
| Payment Automation | `/XYDataLabs-payment-automation` | Launches the separate payment automation workspace from one interactive entry point for local, Docker, and Azure targets plus local/Docker/Azure matrix runs, including dry-run and tenant selection support. |
| Local Setup | `/XYDataLabs-setup-local` | After a fresh git clone — runs setup-local.ps1, summarises VS F5 and Docker next steps |
| SQL Local Access | `/XYDataLabs-sql-local-access` | Opens or closes Azure SQL firewall for local IP after a fresh bootstrap/deploy. Prints SSMS connection details. |
| Context Audit | `/XYDataLabs-context-audit` | Detects stale AI context by diffing memory files and copilot-instructions against the actual codebase. Run periodically or after major refactors. |

| Log + DB Correlation | `/XYDataLabs-verify-db-logs` | After any payment run on any env/profile — script-first by runtime: calls `scripts/verify-payment-run-physical.ps1` for docker/local or `scripts/verify-payment-run-azure.ps1` for azure, returns the formatted table summary by default, and falls back to manual investigation only when needed. |
| ADR Validation | `/XYDataLabs-validate-adrs` | Before committing changes to any ADR — runs frontmatter schema check + markdownlint locally; documents how to toggle the CI counterpart. |
| Phase Handoff Prompts | `.github/prompts/phase-handoffs/` | Phase-specific architect/developer prompts for external or role-specialized models; Phase 9 uses Deepseek 14B/64k for ADR-021/module-isolation architecture and Qwen 14B/64k for narrow implementation slices. |

---

## 10. Key Documentation Files

| File | Where | What it covers |
|------|-------|---------------|
| `TROUBLESHOOTING-INDEX.md` | Root | Quick links for common GitHub App / OIDC / workflow errors |
| `ARCHITECTURE.md` | Root | Binding tenant, payment identifier, migration, and test standard for future model creation |
| `ARCHITECTURE-EVOLUTION.md` | Root | 14-phase roadmap: Phase 8.7 ✅ (Provider Webhooks), Phase 9 ✅ (YARP Microservices Architecture), Phase 9.5 ✅ (Keycloak portability); Phase 10 next 📅 (Azure transport + DLQ operations) |
| `docs/internal/AZURE-PROGRESS-EVALUATION.md` | docs/internal | Learning progress weeks 1–10, next-step guides |
| `docs/AI-OPERATING-MODEL.md` | docs/ | Canonical protocol for shared AI customization and governance |
| `docs/internal/DEFERRED-WORK-LOG.md` | docs/internal | Shared register for justified deferred work |
| `docs/internal/branch-and-blueprint-strategy.md` | docs/internal | Snapshot tag/branch governance, two-layer template packaging, side-project bootstrap (ADR-018) |
| `docs/architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md` | docs/architecture/decisions | Decision: tag+branch (Path C) snapshots + `dotnet new` NuGet template + GitHub template repo (Layer 1 + Layer 2) |
| `docs/architecture/decisions/ADR-019-central-tenant-registry.md` | docs/architecture/decisions | Decision: `Tenant.PaymentProviderCode` as sole routing authority; `ITenantRegistry` resolver; ALL `PaymentProviders.IsActive = false` |
| `docs/reference/quick-command-reference.md` | docs/ | Command cheat sheet for Azure, Git, Docker, GitHub App |
| `.github/workflows/README.md` | Workflows | Workflow overview, secrets, path triggers |
| `.github/workflows/README-AZURE-INITIAL-SETUP.md` | Workflows | Initial Setup workflow (Phase 0/1a/1b) |
| `.github/workflows/README-AZURE-BOOTSTRAP.md` | Workflows | Bootstrap and deploy workflow guide |
| `.github/workflows/README-CONFIGURE-GITHUB-SECRETS.md` | Workflows | Secrets workflow detail |
| `.github/workflows/README-INFRA-DEPLOY.md` | Workflows | Infrastructure deployment workflow guide |
| `.github/workflows/README-VALIDATE-DEPLOYMENT.md` | Workflows | Pre-deployment validation workflow detail |
| `.github/workflows/README-TEST-VALIDATE-DEPLOYMENT.md` | Workflows | Test pre-deployment validation workflow detail |
| `.github/completion-check-rubric.md` | .github | Non-negotiable versus deferrable rubric for `/XYDataLabs-completion-check` |
| `docs/README.md` | docs/ | Documentation hub with links to all guides |
| `docs/reference/operations-quick-links.md` | docs/ | Quick reference links for operations tasks |
| `docs/reference/quick-command-reference.md` | docs/ | Command cheat sheet for Azure, Git, Docker, GitHub App |
| `docs/guides/deployment/quick-start-azure-bootstrap.md` | docs/ | Quick-start guide for Azure bootstrap process |
| `docs/guides/deployment/azure-deployment-guide.md` | docs/ | Complete Azure deployment strategy |
| `docs/guides/configuration/quick-setup-github-app.md` | docs/ | GitHub App quick setup guide |
| `docs/guides/deployment/workflow-separation-architecture.md` | docs/ | Why bootstrap is split into separate workflows |
| `Resources/Azure-Deployment/README.md` | Resources/ | Script index and usage |

---

## 11. Common Troubleshooting Patterns

See `TROUBLESHOOTING-INDEX.md` for symptom-to-remedy quick reference.
