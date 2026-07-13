# GitHub Actions Workflows - CI/CD Automation

This directory contains GitHub Actions workflows for automated CI/CD deployment across the historical App Service path and the current Phase 10 Azure Container Apps path using OIDC authentication.

> **Phase 10 note:** The active deployment, image build, and validation flows are the container-app workflows (`phase10-deploy-orchestrator.yml`, `infra-deploy.yml`, `build-phase10-images.yml`, and the Phase 10 smoke runbook). Legacy App Service workflows remain only for historical compatibility and should not be treated as the target runtime model for Phase 10.

> **Repo-wide enterprise rule:** Prefer Azure-native identity and runtime services when practical. Use OIDC for Azure login, the GitHub App for repository-secret automation, ACR for Azure runtime image pulls, and Front Door/WAF for public ingress when needed. Treat SQL and Redis as requirement-driven services, not defaults. Document any GHCR bridge or other exception explicitly with a closure plan. Every deployable workflow should preserve env-suffixed naming, cleanup symmetry, source-level retention, and traceable summary links.

## Workflow Inventory

Current assessment:

- Total workflow YAMLs in `.github/workflows`: `20`
- Actively useful today: `17`
- Legacy compatibility only: `3`
- Not a workflow file: `Copilot cloud agent`

Use this rule before removing anything:

- If a workflow is still referenced by docs, scripts, badges, or another workflow, keep it until the dependency is retired.
- If you want to remove a workflow, test the matching workflow or script path first so you know the current behavior and failure mode.

### Naming Convention

- Workflows marked `(Internal)` are child or reusable workflows.
- They are intended to be called by `phase10-deploy-orchestrator.yml` or trusted automation, not run directly as the primary operator path.
- The wrapper workflow is the only manual Phase 10 entrypoint.

### Phase 10 Structure

| Workflow | Category | Direct Click? | Purpose |
|---|---|---|---|
| `00 Phase 10 Docker Dev HTTP End-to-End` | Validation | Sometimes | Mirrors the local Docker Dev HTTP hook in CI |
| `01 Phase 10 Azure Deploy Orchestrator` | Wrapper | Yes | Manual Phase 10 entrypoint that runs build, deploy, or cleanup and prints the operator summary |
| `02 Phase 10 Azure Runtime Smoke` | Validation | Yes, after deploy | Verifies Gateway health, Gateway-routed API bootstrap, UI reachability, and UI API proxy bootstrap |
| `03 Phase 10 Azure Transport Smoke` | Validation | Yes, after runtime smoke | Publishes, consumes, dead-letters, and replays a controlled Service Bus smoke flow |
| `build-phase10-images.yml` | Internal | No | Builds and publishes the Phase 10 service images |
| `infra-deploy.yml` | Internal | No | Deploys or cleans up the Phase 10 Azure stack and returns live URLs |
| `phase10-retention-cleanup.yml` | Internal housekeeping | No for deploy | Scheduled/manual cleanup for old GHCR package versions and workflow artifacts |
| `azure-initial-setup.yml` | Bootstrap | Yes | One-time GitHub App + OIDC + secrets setup |
| `azure-bootstrap.yml` | Historical | No for Phase 10 | Legacy App Service compatibility path only |
| `deploy-api-to-azure.yml` | Historical | No for Phase 10 | Legacy App Service API deployment only |
| `deploy-ui-to-azure.yml` | Historical | No for Phase 10 | Legacy App Service UI deployment only |

### Phase 10 Sequence

Use the numbered workflows in this order:

| Order | Workflow | Use it for |
|---|---|---|
| `00` | `00 Phase 10 Docker Dev HTTP End-to-End` | Local/CI parity for the containerized service graph, before Azure work |
| `01` | `01 Phase 10 Azure Deploy Orchestrator` | Build, deploy, dry run, or cleanup for the Azure Phase 10 stack |
| `02` | `02 Phase 10 Azure Runtime Smoke` | Prove gateway health, routed API runtime config, and UI readiness after deploy |
| `03` | `03 Phase 10 Azure Transport Smoke` | Prove Service Bus publish/consume, DLQ forwarding, and replay after runtime smoke |

### Default Review Stance

Before approving any workflow or infrastructure change, ask:

1. Is the Azure login path passwordless and OIDC-based?
2. Is the runtime registry Azure-native unless there is a documented exception?
3. Is there a matching cleanup path and retention policy?
4. Do the resource names stay env-suffixed and predictable?
5. Do the workflow summary and child jobs expose traceable links?
6. If we are bridging with GHCR, is ACR recorded as the follow-up implementation?

### Which Workflow Should I Click?

| If you want to... | Click this workflow |
|---|---|
| Verify the local Docker Dev HTTP hook in CI | `00 Phase 10 Docker Dev HTTP End-to-End` |
| Run Phase 10 deploy, dry run, or cleanup from GitHub UI | `01 Phase 10 Azure Deploy Orchestrator` |
| Prove Phase 10 Gateway/API/UI runtime behavior after deploy | `02 Phase 10 Azure Runtime Smoke` |
| Prove Phase 10 Service Bus publish/consume/DLQ/replay after runtime smoke | `03 Phase 10 Azure Transport Smoke` |
| Build and publish Phase 10 images indirectly | `01 Phase 10 Azure Deploy Orchestrator` |
| Deploy or clean up the Azure Phase 10 stack indirectly | `01 Phase 10 Azure Deploy Orchestrator` |
| Clean old Phase 10 GHCR versions and workflow artifacts | Let `Phase 10 Retention Cleanup (Internal)` run on schedule; run manually only for housekeeping |
| Do one-time GitHub App and OIDC bootstrap | `azure-initial-setup.yml` |
| Work on archived App Service compatibility only | `azure-bootstrap.yml`, `deploy-api-to-azure.yml`, or `deploy-ui-to-azure.yml` |

### Phase 10 Workflow Responsibilities

| Workflow | Click target | Owns RG creation | Builds images | Deploys app | Cleanup | Current or legacy |
|---|---|---|---|---|---|---|
| `00 Phase 10 Docker Dev HTTP End-to-End` | Optional validation | No | Local/runner build only | Local Docker only | Local Docker cleanup | Current validation |
| `01 Phase 10 Azure Deploy Orchestrator` | Primary Phase 10 click target | Routes to internal deploy workflow | Routes to internal image workflow | Routes to internal deploy workflow | Routes Azure RG cleanup when `cleanupInfra=true` | Current wrapper |
| `02 Phase 10 Azure Runtime Smoke` | Post-deploy smoke | No | No | No | No | Current validation |
| `03 Phase 10 Azure Transport Smoke` | Post-runtime-smoke transport proof | No | No | No | No | Current validation |
| `Build Phase 10 Service Images (Internal)` | Do not click for normal deploy | No | Yes | No | No | Current internal |
| `Deploy Azure Phase 10 Resources (Internal)` | Do not click for normal deploy | Yes | No | Yes | Yes | Current internal |
| `Phase 10 Retention Cleanup (Internal)` | Housekeeping only | No | No | No | GHCR/artifact retention only | Current internal |
| `Azure Bootstrap & Deploy` | Do not use for Phase 10 | Legacy App Service stack | No | Legacy App Service only | Legacy App Service RG path | Legacy |
| `Deploy API to Azure App Service` | Do not use for Phase 10 | No | No | Legacy API only | No | Legacy |
| `Deploy React Frontend to Azure App Service` | Do not use for Phase 10 | No | No | Legacy UI only | No | Legacy |

For detailed operator steps, use [Phase 10 Azure Smoke Runbook](../../docs/runbooks/phase10-azure-smoke.md). For the local equivalent of workflow `00`, use either:

```powershell
npm --prefix automation run xydatalabs-test-docker-local-e2e-dev
```

or the VS Code task:

```text
1 Run: xydatalabs-test-docker-local-e2e-dev (Docker Dev HTTP E2E)
```

| Workflow | Usage | Keep / Remove | Test before removal? |
|----------|-------|---------------|----------------------|
| `validate-prompts.yml` | Prompt file governance and secret-pattern checks | Keep | Yes, if changing the validator path |
| `azure-bootstrap.yml` | Legacy App Service bootstrap/deploy/cleanup | Keep for legacy compatibility | Yes |
| `azure-initial-setup.yml` | One-time GitHub App, OIDC, and secrets bootstrap | Keep | Only if refactoring initial setup |
| `build-phase10-images.yml` | Builds/pushes Phase 10 container images | Keep as internal reusable workflow | Yes, if changing image contracts |
| `ci.yml` | Main PR build/test/frontend validation gate | Keep | Yes, if changing CI flow |
| `configure-github-secrets.yml` | Secret configuration and troubleshooting support | Keep | Yes, if changing setup flow |
| `Copilot cloud agent` | Not a workflow file in this repo | N/A | N/A |
| `deploy-api-to-azure.yml` | Legacy App Service API deployment | Keep for legacy compatibility | Yes |
| `deploy-ui-to-azure.yml` | Legacy App Service UI deployment | Keep for legacy compatibility | Yes |
| `drift-check.yml` | Broad repository drift scanning | Keep unless you intentionally drop drift scanning | Yes |
| `infra-deploy.yml` | Active Phase 10 Azure Container Apps deployment | Keep as internal reusable workflow | Yes, if changing IaC flow |
| `phase10-deploy-orchestrator.yml` | Manual Phase 10 wrapper for build + deploy or cleanup | Keep as the only direct Phase 10 entrypoint | Yes, if changing wrapper flow |
| `phase10-azure-runtime-smoke.yml` | Manual Phase 10 runtime/API/UI smoke after deploy | Keep as the direct post-deploy runtime proof | Yes, if changing gateway/API/UI runtime contracts |
| `phase10-azure-transport-smoke.yml` | Manual Phase 10 transport/operator smoke after deploy | Keep as the direct post-deploy transport proof | Yes, if changing Service Bus topology or smoke contracts |
| `phase10-docker-dev-http-e2e.yml` | CI mirror of the local Phase 10 Docker hook | Keep | Yes, if changing hook or log paths |
| `phase10-retention-cleanup.yml` | Scheduled/manual Phase 10 GHCR and artifact housekeeping | Keep | Yes, if changing retention thresholds |
| `validate-deployment.yml` | Reusable pre-deployment validation | Keep | Yes, if changing validation rules |
| `publish-template-package.yml` | Template packaging / publishing | Keep | Yes, before publishing-path changes |
| `test-validate-deployment.yml` | Tests the validation workflow itself | Keep | Yes, definitely |
| `validate-adrs.yml` | ADR governance | Keep | Yes, if changing ADR rules |
| `validate-ai-customization.yml` | AI/prompt governance | Keep | Yes, if changing AI assets |
| `validate-doc-links.yml` | Docs link/anchor validation | Keep | Yes, if changing docs rules |
| `validate-template-package-governance.yml` | Template package governance | Keep | Yes, if changing template versioning |

## 📋 Overview

This repo uses a small set of primary operational workflows, with additional support workflows for setup, validation, and troubleshooting.

| Workflow | Triggers On | Deploys To | Description |
|----------|-------------|------------|-------------|
| `ci.yml` | Pull requests to dev/staging/main | Validation only | PR build/test gate for the .NET solution plus React frontend typecheck, tests, and build |
| `azure-initial-setup.yml` | Manual | One-time setup | **[See README-AZURE-INITIAL-SETUP.md](./README-AZURE-INITIAL-SETUP.md)** - Phase 0 (GitHub App), Phase 1a (OIDC), Phase 1b (secrets) |
| `azure-bootstrap.yml` | Manual | Legacy App Service stack | **[See README-AZURE-BOOTSTRAP.md](./README-AZURE-BOOTSTRAP.md)** - Phase 2 (infrastructure), API/UI deploy, Phase X (cleanup) |
| `configure-github-secrets.yml` | Called by initial-setup | Secret configuration | **[See README-CONFIGURE-GITHUB-SECRETS.md](./README-CONFIGURE-GITHUB-SECRETS.md)** - GitHub App setup and secret management (can run independently) |
| `phase10-deploy-orchestrator.yml` | Manual | dev/staging/prod | **[See README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)** - Wrapper that drives the Phase 10 image build plus infra deploy/cleanup flows |
| `phase10-azure-runtime-smoke.yml` | Manual after deploy | dev/staging/prod | Runs the Phase 10 Gateway/API/UI runtime smoke and writes a pass/fail operator summary |
| `phase10-azure-transport-smoke.yml` | Manual after deploy | dev/staging/prod | Runs the Phase 10 Service Bus publish, consume, DLQ forwarding, and replay smoke and writes a pass/fail operator summary |
| `infra-deploy.yml` | Reusable internal workflow | dev/staging/prod | Internal Phase 10 Bicep deployment and cleanup workflow with alias planning and guarded alias binding |
| `build-phase10-images.yml` | Push to service host paths or wrapper-called internal workflow | GHCR | Builds and pushes the Phase 10 container images for gateway, orders, inventory, notifications, and UI |
| `phase10-docker-dev-http-e2e.yml` | Manual or PR changes to Phase 10 Docker hook paths | Validation only | Runs the local Docker Dev HTTP end-to-end hook in CI and uploads the same Phase 10 logs used by the VS Code task and runbook |
| `validate-deployment.yml` | Called by infra-deploy | Reusable workflow | **[See README-VALIDATE-DEPLOYMENT.md](./README-VALIDATE-DEPLOYMENT.md)** - Pre-deployment validation workflow |
| `test-validate-deployment.yml` | Manual or PR changes | Test only | **[Quick Start](./QUICK-START-TEST-VALIDATION.md)** \| **[Full Docs](./README-TEST-VALIDATE-DEPLOYMENT.md)** - Tests validation workflow independently |
| `deploy-api-to-azure.yml` | API/Backend code changes | All branches (dev/staging/main) | Legacy App Service deployment path for the API |
| `deploy-ui-to-azure.yml` | React frontend changes | All branches (dev/staging/main) | Legacy App Service deployment path for the UI, including browser smoke against the tenant bootstrap flow |
| `publish-template-package.yml` | Manual | Artifact only or package registry | **[See README-PUBLISH-TEMPLATE-PACKAGE.md](./README-PUBLISH-TEMPLATE-PACKAGE.md)** - Packs `XYDataLabs.SaaS.Templates`, validates the packaged `dotnet new` smoke flow, uploads the `.nupkg`, and optionally publishes it |
| `validate-template-package-governance.yml` | Pull requests for Layer 1 template changes, or manual | Validation only | **[See README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md](./README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md)** - Forces a `PackageVersion` decision for Layer 1 template changes and runs packaged smoke validation |
| `validate-adrs.yml` | ADR file, script, or lint config changes | Push/PR to main/dev/staging, or manual | **[See README-VALIDATE-ADRS.md](./README-VALIDATE-ADRS.md)** — Validates ADR filename pattern, H1 heading, `**Status:**` frontmatter, and markdownlint rules |
| `validate-ai-customization.yml` | Shared AI customization changes | Push/PR to main/dev/staging, or manual | Validates shared Copilot instructions, prompts, agents, operating-model docs, and their discovery surfaces |
| `validate-doc-links.yml` | Docs or validator changes | Push/PR to main/dev/staging, or manual | Validates local markdown links and heading anchors for the canonical `docs/` tree |

### Phase 10 Hook Mapping

The `phase10-docker-dev-http-e2e.yml` workflow is the CI mirror of the local Phase 10 hook:

- Local entrypoint: `scripts/run-phase10-docker-dev-e2e-hook.ps1`
- Preferred automation alias: `npm --prefix automation run xydatalabs-test-docker-local-e2e-dev`
- Compatibility automation alias: `npm --prefix automation run run:docker:dev:http:e2e-hook`
- VS Code task: `1 Run: xydatalabs-test-docker-local-e2e-dev (Docker Dev HTTP E2E)`
- CI entrypoint: `.github/workflows/phase10-docker-dev-http-e2e.yml`
- GitHub summary pointers:
  - `TestResults/Playwright/phase10-docker-http/latest-playwright-smoke.txt`
  - `TestResults/Playwright/phase10-docker-http/latest-playwright-full-validation.txt`
  - `TestResults/Playwright/phase10-docker-http/<timestamp>_endtoend/summary.json`
  - `phase10-docker-dev-http-e2e-${{ github.run_id }}-${{ github.run_attempt }}`

Use the local hook for interactive debugging and the CI workflow to prove the same sequence still passes on a runner and produces the expected artifacts.

### Workflow Categories

**Primary workflows** are the workflows the team should think about first for normal delivery and operations:

| Workflow | Role |
|----------|------|
| `ci.yml` | PR gate for build and unit/architecture test validation |
| `azure-initial-setup.yml` | One-time repository and OIDC bootstrap |
| `azure-bootstrap.yml` | Legacy App Service day-to-day environment bootstrap and coordinated deployment entrypoint |
| `build-phase10-images.yml` | Phase 10 container image build/push internal reusable workflow for GHCR |
| `phase10-deploy-orchestrator.yml` | Phase 10 manual wrapper that drives build + deploy or cleanup |
| `phase10-azure-runtime-smoke.yml` | Phase 10 post-deploy Gateway/API/UI runtime validation |
| `phase10-azure-transport-smoke.yml` | Phase 10 post-deploy Service Bus publish/consume/DLQ/replay validation |
| `phase10-docker-dev-http-e2e.yml` | Phase 10 Docker Dev HTTP merge gate and artifact-producing validation path |
| `deploy-api-to-azure.yml` | Legacy API deployment path retained for the App Service stack |
| `deploy-ui-to-azure.yml` | Legacy React frontend deployment path retained for the App Service stack |

**Support workflows** exist for specialized validation, secondary entrypoints, or troubleshooting rather than the default delivery path:

| Workflow | Role |
|----------|------|
| `configure-github-secrets.yml` | Secondary/manual secret configuration and GitHub App troubleshooting path |
| `infra-deploy.yml` | Phase 10 infra-only internal reusable workflow with env-aware alias planning |
| `publish-template-package.yml` | Manual package publication path for the Layer 1 `dotnet new` template after packaged smoke validation |
| `validate-template-package-governance.yml` | Automatic PR guardrail that requires a package-version decision and packaged smoke validation for Layer 1 template changes |
| `validate-deployment.yml` | Reusable preflight validation called by infra deployment |
| `test-validate-deployment.yml` | Independent test harness for validation workflow changes |
| `validate-adrs.yml` | Documentation governance for ADR changes |
| `validate-ai-customization.yml` | Governance guardrail for shared AI operating assets |
| `validate-doc-links.yml` | Lightweight guardrail for canonical docs navigation integrity |

### Branch-to-Environment Mapping

| Git Branch | API Deployment Target | React Frontend Target |
|------------|----------------------|-----------------------|
| `dev` | orderprocessing-api-xyapp-dev | orderprocessing-ui-xyapp-dev |
| `staging` | orderprocessing-api-xyapp-stg | orderprocessing-ui-xyapp-stg |
| `main` | orderprocessing-api-xyapp-prod | orderprocessing-ui-xyapp-prod |

The table above intentionally shows both surfaces. The legacy App Service workflows remain for historical compatibility, while Phase 10 infra publishes Container Apps plus ingress endpoints from the Bicep deployment summary, and `build-phase10-images.yml` publishes the distinct gateway/orders/inventory/notifications/UI runtime images for those apps.

For Phase 10, the expected click path is:

1. Optionally run `00 Phase 10 Docker Dev HTTP End-to-End` for local/CI container parity.
2. Open `01 Phase 10 Azure Deploy Orchestrator`.
3. Run the wrapper manually for `dev`, `staging`, or `prod`.
4. Let it call `build-phase10-images.yml` and `infra-deploy.yml` internally.
5. Run `02 Phase 10 Azure Runtime Smoke` for the same environment.
6. Run `03 Phase 10 Azure Transport Smoke` for the same environment.
7. Use `cleanupInfra=true` when you want teardown instead of deployment.

In plain terms:

| Number | What it means |
|---|---|
| `00` | Local parity check. Use it when you want the Docker container graph to behave like the current Phase 10 Azure shape. |
| `01` | Azure delivery entrypoint. Use it for deploy, dry run, or cleanup. |
| `02` | Runtime proof. Use it after Azure deploy to verify gateway/API/UI behavior. |
| `03` | Transport proof. Use it after runtime smoke to verify Service Bus fan-out, DLQ, and replay. |

The runtime and transport smoke workflows resolve their resource group, gateway, UI, and Service Bus targets from the selected environment. They do not ask for a region input.

When the wrapper calls `infra-deploy.yml`, the key inputs are:

| Input | Purpose |
|-------|---------|
| `environment` | Selects `dev`, `staging`, or `prod` |
| `location` | Azure region for the deployment |
| `dryRun` | Runs what-if only when enabled |
| `publicDomain` | Optional DNS suffix for friendly aliases such as `api-dev.contoso.com` |
| `bindAliases` | Enables alias planning and direct binding checks |
| `aliasMode` | Chooses either `direct` ACA custom-domain binding or `frontdoor` alias planning |

If `bindAliases=true`, supply a real `publicDomain`. The workflow will fail fast instead of using a placeholder domain.

Workflow YAML still enforces this policy explicitly.
Azure deployment scripts consume the same defaults from `Resources/Azure-Deployment/branch-policy.json`; if governance changes, update the workflow guards and the shared policy file together.

---

## 🔐 Required GitHub Secrets

Before workflows can execute, the following secrets must be configured:

**Repository secrets**

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `APP_ID` | GitHub App ID | GitHub App setup |
| `APP_PRIVATE_KEY` | GitHub App private key | GitHub App setup |
| `NUGET_API_KEY` | NuGet.org publish key for `XYDataLabs.SaaS.Templates` | Create in NuGet.org account settings (required only when publishing to NuGet.org) |

**Environment secrets** (`dev`, `staging`, `prod`)

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AZUREAPPSERVICE_CLIENTID` | Azure AD App Registration Client ID | Azure Initial Setup (Phase 1b) |
| `AZUREAPPSERVICE_TENANTID` | Azure AD Tenant ID | Azure Initial Setup (Phase 1b) |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Azure Subscription ID | Azure Initial Setup (Phase 1b) |

### Automatic Secret Configuration

If you ran Azure Initial Setup successfully, the environment OIDC secrets are **already configured**.

Verify at: `Settings → Environments → dev/staging/prod`

### Manual Secret Configuration

If automatic configuration failed:

1. Run **Azure Initial Setup** with `configureSecrets=true`
2. **Navigate to**: Repository → Settings → Environments
3. **Open each environment** and confirm the three `AZUREAPPSERVICE_*` secrets are present

---

## 🚀 Workflow Execution

### Automatic Triggers

Workflows trigger automatically based on **what code changed**:

```bash
# Change API code and push → triggers deploy-api-to-azure.yml
git add XYDataLabs.OrderProcessingSystem.API/
git commit -m "feat: Update API endpoint"
git push origin dev  # Deploys API only to dev environment

# Change a Phase 10 service host and push → triggers build-phase10-images.yml
git add XYDataLabs.OrderProcessingSystem.Orders.API/
git commit -m "feat: Update Orders host"
git push origin dev  # Builds and pushes the Orders image to GHCR

# Change React web code and push → triggers deploy-ui-to-azure.yml
git add frontend/
git commit -m "feat: Update React payment flow"
git push origin dev  # Deploys the React frontend to the dev UI App Service

# Change API plus React frontend → triggers BOTH deploy workflows in parallel
git add XYDataLabs.OrderProcessingSystem.API/ frontend/
git commit -m "feat: Update API and React frontend"
git push origin dev  # Deploys API and the React frontend to dev environment
```

### Path-Based Triggering

**API Workflow** (`deploy-api-to-azure.yml`) triggers on changes to:
- `XYDataLabs.OrderProcessingSystem.API/**`
- `XYDataLabs.OrderProcessingSystem.Application/**`
- `XYDataLabs.OrderProcessingSystem.Domain/**`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/**`
- `XYDataLabs.OrderProcessingSystem.SharedKernel/**`

**UI Workflow** (`deploy-ui-to-azure.yml`) triggers on changes to:
- `frontend/**`
- `Resources/Configuration/**`
- `.github/workflows/deploy-ui-to-azure.yml`

### Pull Request Behavior

**IMPORTANT**: Workflows do **NOT** trigger on Pull Request events.

- ❌ Opening a PR does **not** trigger deployment
- ❌ Merging a PR via GitHub UI does **not** trigger deployment (unless merge creates a push event)
- ✅ Merging via command line with push **does** trigger deployment:
  ```bash
  git checkout staging
  git merge dev
  git push origin staging  # ← This triggers deploy-staging.yml
  ```

### Manual Triggers

Workflows can be triggered manually via GitHub Actions UI:

1. Navigate to: **Actions** tab → Select workflow
2. Click **Run workflow** button
3. Select branch → Click **Run workflow**

---

## 📦 Workflow Stages

The API workflow and the React frontend workflow execute in 2 stages:

### Stage 1: Build (Windows Runner)
- ✅ Checkout code
- ✅ Setup Node.js 20
- ✅ Restore npm workspace dependencies
- ✅ Run frontend typecheck
- ✅ Run frontend regression tests
- ✅ Build the React production artifact with the environment-specific API base URL
- ✅ Upload build artifact

### Stage 2: Deploy (Windows Runner)
- ✅ Determine target environment (dev/staging/prod) from branch name
- ✅ Download build artifact
- ✅ Login to Azure using OIDC (passwordless authentication)
- ✅ Deploy to environment-specific Azure Web App
- ✅ Run SPA route health checks (API: `/health/ready`, frontend: `/customers`)
- ✅ Run a browser smoke check that seeds a stale tenant and verifies the deployed UI still resolves the API bootstrap tenant
- ✅ Display deployment URLs

---

## 🔍 Monitoring Deployments

### View Workflow Runs

Navigate to: https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions

### Workflow Status Badges

Add to README.md:

```markdown
## Deployment Status

[![Deploy Dev](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-dev.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-dev.yml)

[![Deploy Staging](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-staging.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-staging.yml)

[![Deploy Production](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-main.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-main.yml)
```

---

## 🛠️ Customization

### Smart Path Filtering

Workflows use **path-based triggering** - they only run when relevant code changes:

**Benefits:**
- ✅ **Efficiency**: Documentation changes don't trigger deployments
- ✅ **Speed**: Only affected components are deployed
- ✅ **Cost**: Fewer workflow minutes consumed
- ✅ **Safety**: Isolated deployments reduce blast radius

**Example Scenarios:**

```bash
# Scenario 1: Only API code changed
# Changed: XYDataLabs.OrderProcessingSystem.API/Controllers/OrderController.cs
# Result: Only deploy-api-to-azure.yml runs ✅

# Scenario 2: Only web frontend code changed  
# Changed: frontend/apps/web/src/App.tsx
# Result: Only deploy-ui-to-azure.yml runs ✅

# Scenario 3: Shared domain model changed
# Changed: XYDataLabs.OrderProcessingSystem.Domain/Entities/Order.cs
# Result: BOTH workflows run (API and UI depend on Domain) ✅

# Scenario 4: Documentation updated
# Changed: docs/README.md
# Result: NO workflows run (documentation changes ignored) ✅
```

### Changing Web App Names

If you used custom names during bootstrap, update `app-name` in workflows:

```yaml
- name: Deploy to Azure Web App (API)
  uses: azure/webapps-deploy@v3
  with:
    app-name: 'YOUR-CUSTOM-API-NAME-dev'  # ← Update here
    package: ./api
```

---

## 🔒 Security Best Practices

### OIDC Authentication

Workflows use **OpenID Connect (OIDC)** for Azure authentication:

- ✅ No long-lived secrets stored in GitHub
- ✅ Short-lived tokens (1 hour expiration)
- ✅ Federated credentials tied to specific branches
- ✅ Principle of least privilege (Contributor role on Resource Group only)

### Permissions

Workflows require minimal permissions:

```yaml
permissions:
  id-token: write    # Required for OIDC token request
  contents: read     # Required to checkout code
```

### Service Principal Scope

The OIDC service principal has:
- **Role**: Contributor
- **Scope**: Resource Group level only (not subscription-wide)
- **Branches**: Separate federated credentials derived from the shared branch policy (currently dev, staging, main)

---

## 🧪 Testing Workflows

### Test Without Deployment

To test workflow syntax without deploying:

1. **Fork the repository** to your personal account
2. **Update workflow files** with your test app names
3. **Push to test branch**
4. **Observe workflow execution** (it will fail at deployment but validate syntax)

### Local Workflow Validation

Install `act` to run workflows locally:

```bash
# Install act (Windows)
winget install nektos.act

# Test dev workflow
act push -W .github/workflows/deploy-dev.yml
```

**Note**: Local execution won't have Azure credentials, but validates syntax.

---

## 🐛 Troubleshooting

### Workflow Not Triggering

**Problem**: Pushed to branch but workflow didn't run

**Solutions**:
1. ✅ Check branch name matches the enforced workflow mapping (`dev`, `staging`, `main` by default)
2. ✅ Verify push succeeded: `git push origin dev --verbose`
3. ✅ Check if changes were only in ignored documentation paths (`docs/` or other `.md` files)
4. ✅ View Actions tab for any disabled workflows

### Authentication Failed

**Problem**: `Error: Login failed with Error: AADSTS700016: Application not found`

**Solutions**:
1. ✅ Verify GitHub secrets are configured correctly
2. ✅ Check OIDC App Registration exists in Azure AD
3. ✅ Verify federated credentials for branch exist
4. ✅ Re-run `bootstrap-enterprise-infra.ps1` to recreate OIDC setup

### Deployment Failed

**Problem**: Build succeeded but deployment failed

**Solutions**:
1. ✅ Check Azure Web App exists and is running
2. ✅ Verify app name in workflow matches actual Azure resource
3. ✅ Check RBAC role assignments (Service Principal needs Contributor role)
4. ✅ Review Azure App Service logs for deployment errors

### Build Failed

**Problem**: Build stage fails with compilation errors

**Solutions**:
1. ✅ Verify solution builds locally: `dotnet build XYDataLabs.OrderProcessingSystem.sln`
2. ✅ Check all NuGet packages are restored
3. ✅ Review build logs in GitHub Actions for specific error
4. ✅ Ensure .NET 8 SDK is used (workflow specifies `dotnet-version: '8.0.x'`)

---

## 📚 Additional Resources

### GitHub Actions Documentation
- [GitHub Actions Overview](https://docs.github.com/actions)
- [Workflow Syntax](https://docs.github.com/actions/reference/workflow-syntax-for-github-actions)
- [Azure Login Action](https://github.com/marketplace/actions/azure-login)
- [Azure WebApps Deploy Action](https://github.com/Azure/webapps-deploy)

### Azure Documentation
- [Azure OIDC with GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [Azure App Service Deployment](https://learn.microsoft.com/azure/app-service/deploy-github-actions)
- [Federated Identity Credentials](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)

### Internal Documentation
- **[Infrastructure Deployment Guide](./README-INFRA-DEPLOY.md)** ⭐ Manual Bicep deployment with dry run
- [Quick Start Azure Bootstrap](../../docs/guides/deployment/quick-start-azure-bootstrap.md)
- [Azure Deployment Guide](../../docs/guides/deployment/azure-deployment-guide.md)
- [Master Curriculum](../../docs/learning/curriculum/1_MASTER_CURRICULUM.md)

---

## 📝 Workflow Change Log

| Date | Workflow | Change | Author |
|------|----------|--------|--------|
| 2025-11-21 | test-validate-deployment.yml | Added test workflow for pre-deployment validation | GitHub Copilot |
| 2025-11-20 | All | Initial creation with OIDC authentication | GitHub Copilot |

---

## ✅ Next Steps

### For Testing Validation Workflow (New!)
**👉 Start here to test pre-deployment validation:**
1. **Read the guide**: [README-TEST-VALIDATE-DEPLOYMENT.md](./README-TEST-VALIDATE-DEPLOYMENT.md)
2. **Run validation test**: Go to Actions → Test Pre-Deployment Validation → Run workflow
3. **Review test results**: Check for configuration drift or issues

### For Infrastructure Deployment
**👉 After validation tests pass:**
1. **Read the guide**: [README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)
2. **Run the wrapper**: Go to Actions → Phase 10 Deploy Orchestrator → Run workflow
3. **Dry run first**: Set `dryRun = true`
4. **Deploy or cleanup**: Set `dryRun = false` and choose `cleanupInfra` as needed

### For Application Deployment
After infrastructure is deployed:

1. **Verify secrets configured**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

2. **Test dev workflow**:
   ```bash
   git checkout dev
   git commit --allow-empty -m "test: Trigger dev workflow"
   git push origin dev
   ```

3. **Monitor workflow**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

4. **Verify deployment**:
   - Legacy App Service URL if you are exercising the old stack
   - Phase 10 Container Apps ingress URL from the infra deployment summary if you are exercising the current stack

5. **Promote to staging** (after dev validation):
   ```bash
   git checkout staging
   git merge dev
   git push origin staging
   ```

---

**Questions or Issues?** 
- Validation Testing: See [README-TEST-VALIDATE-DEPLOYMENT.md](./README-TEST-VALIDATE-DEPLOYMENT.md)
- Pre-Deployment Validation: See [README-VALIDATE-DEPLOYMENT.md](./README-VALIDATE-DEPLOYMENT.md)
- Infrastructure: See [README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)
- Application Deployment: Check [Quick Start Azure Bootstrap](../../docs/guides/deployment/quick-start-azure-bootstrap.md)
- Full Learning Path: [Master Curriculum](../../docs/learning/curriculum/1_MASTER_CURRICULUM.md)
