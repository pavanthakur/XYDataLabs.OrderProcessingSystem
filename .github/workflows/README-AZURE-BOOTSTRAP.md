# Azure Bootstrap & Deploy Workflow

Day-to-day workflow for Azure infrastructure provisioning, application deployment, and environment cleanup.

## 🎯 Purpose

This workflow (`azure-bootstrap.yml`) handles **infrastructure and deployment operations** for the Order Processing System. It provisions Azure resources (Phase A), triggers API/UI deployments, and can tear down environments (Phase X).

> ⚠️ **Prerequisite**: The [Azure Initial Setup](README-AZURE-INITIAL-SETUP.md) workflow must have completed successfully before this workflow can run. That workflow handles Phase 0 (GitHub App), Phase 1a (OIDC), and Phase 1b (GitHub secrets) — all one-time setup steps.

> 📖 **Full guide**: See [`Documentation/QUICK-START-AZURE-BOOTSTRAP.md`](../../Documentation/QUICK-START-AZURE-BOOTSTRAP.md) for the complete reference including architecture diagrams, parameter reference, and step-by-step sequences.

---

## ⚠️ Prerequisites

Before running this workflow, the following must already be in place:

| Prerequisite | Set by | How to verify |
|-------------|--------|---------------|
| `APP_ID` + `APP_PRIVATE_KEY` repo secrets | Phase 0 (manual) | `Settings → Secrets → Actions` |
| `AZUREAPPSERVICE_CLIENTID` secret | Azure Initial Setup (Phase 1a + 1b) | `Settings → Secrets → Actions` |
| `AZUREAPPSERVICE_TENANTID` secret | Azure Initial Setup (Phase 1a + 1b) | `Settings → Secrets → Actions` |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` secret | Azure Initial Setup (Phase 1a + 1b) | `Settings → Secrets → Actions` |
| Azure AD App Registration with federated credentials | Azure Initial Setup (Phase 1a) | `az ad app list --display-name "GitHub-Actions-OIDC"` |

If any `AZUREAPPSERVICE_*` secret is missing, the `validate-inputs` job will **fail immediately** with guidance to run the Azure Initial Setup workflow first.

See [`README-AZURE-INITIAL-SETUP.md`](README-AZURE-INITIAL-SETUP.md) for the one-time setup instructions.

---

## 🚀 Quick Start

**First-time setup** (if OIDC secrets don't exist yet):
1. Run the **Azure Initial Setup** workflow first — see [README-AZURE-INITIAL-SETUP.md](README-AZURE-INITIAL-SETUP.md)
2. Return here after it completes successfully

**Bootstrap infrastructure** (day-to-day):

1. Go to **Actions → Azure Bootstrap & Deploy → Run workflow**
2. Set **"Use workflow from"** to the branch matching your target environment
3. Configure inputs:

| Input | Value | Notes |
|-------|-------|-------|
| `environment` | `dev` | Start with dev to validate cheaply |
| `bootstrapInfra` | ✅ `true` | Provisions all Azure resources |
| `deployApi` | ✅ `true` | Triggers API deployment after bootstrap |
| `deployUi` | ✅ `true` | Triggers UI deployment after bootstrap |
| `cleanupInfra` | `false` | Never combine with bootstrap |

4. Click **Run workflow**

> **Branch must match environment**: `dev` branch → dev, `staging` branch → staging, `main` branch → prod. This is strictly enforced — mismatches are rejected.

---

## 📋 Workflow Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | `dev` | Target: `dev` / `staging` / `prod` / `all`. Branch must match: `dev`→dev, `staging`→staging, `main`→prod. |
| `bootstrapInfra` | boolean | `true` | **Phase A** — Provisions Resource Group, App Service Plan, Web Apps, App Insights, Azure SQL, Key Vault + managed identity. |
| `deployApi` | boolean | `true` | **Deploy** — Triggers `deploy-api-to-azure.yml` after bootstrap succeeds (or independently if bootstrap is not selected). |
| `deployUi` | boolean | `true` | **Deploy** — Triggers `deploy-ui-to-azure.yml` after bootstrap succeeds (or independently if bootstrap is not selected). |
| `cleanupInfra` | boolean | `false` | **Phase X (DESTRUCTIVE)** — Deletes UI App, API App, then entire Resource Group. ⚠️ Irreversible. Do NOT combine with bootstrap. |

---

## 🔄 Workflow Jobs

### 1. `validate-inputs`
**Runs when**: always (workflow_dispatch only)

- Validates `environment` selection
- **Enforces strict branch/environment match** — `dev` branch for dev, `staging` for staging, `main` for prod
- **Checks OIDC secrets directly** (`${{ secrets.AZUREAPPSERVICE_CLIENTID }}`, etc.)
- Prints a **Phase Readiness Pre-Flight Summary** showing what will run and whether prerequisites are met
- **Fails fast** when OIDC secrets are missing — prints clear guidance to run the Azure Initial Setup workflow first

> **All operations in this workflow require OIDC credentials.** If `AZUREAPPSERVICE_*` secrets don't exist, `validate-inputs` fails immediately with a remediation message — before any other job runs.

### 2. `bootstrap-dev` / `bootstrap-staging` / `bootstrap-prod` (Phase A)
**Runs when**: `bootstrapInfra=true` AND environment matches  
**Needs**: `validate-inputs`

**Azure login (3-step pattern per environment)**:
```
Step 1: Validate that CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID are present
Step 2: azure/login@v2  — passwordless OIDC authentication
Step 3: az account show — verify login succeeded before making changes
```

**Credentials**: Uses `secrets.AZUREAPPSERVICE_*` directly from the environment context — no fallback to job outputs from other jobs.

**Actions**:
- Authenticates to Azure using OIDC (`AZUREAPPSERVICE_*` environment secrets)
- Runs `bootstrap-enterprise-infra.ps1`
- Creates: Resource Group, App Service Plan, API + UI Web Apps, Application Insights, Azure SQL, Key Vault
- Enables system-assigned managed identity on App Services
- Assigns Contributor RBAC to the OIDC service principal
- Dev, Staging, and Prod jobs run in parallel when `environment=all`

### 3. `cleanup-dev` / `cleanup-staging` / `cleanup-prod` (Phase X — DESTRUCTIVE)
**Runs when**: `cleanupInfra=true` AND environment matches  
**Needs**: `validate-inputs`

- Authenticates to Azure using OIDC (`AZUREAPPSERVICE_*` environment secrets)
- Stops and deletes UI App Service (blocking)
- Stops and deletes API App Service (blocking)
- Deletes the entire Resource Group (`az group delete --no-wait`)
- ⚠️ **Irreversible** — all resources in the resource group are destroyed (SQL, Key Vault, App Insights, App Service Plan)

### 4. `summary`
**Runs**: always (after bootstrap and cleanup jobs complete)  
**Needs**: `bootstrap-dev`, `bootstrap-staging`, `bootstrap-prod`, `cleanup-dev`, `cleanup-staging`, `cleanup-prod`

- Aggregates results from bootstrap and cleanup jobs
- Displays overall status table in the workflow run summary
- Shows success / skipped / failure per job
- When any bootstrap job fails, includes a **failure diagnosis** section with likely causes (e.g., missing federated credentials) and remediation steps pointing to the Azure Initial Setup workflow

### 5. `trigger-deployments`
**Runs when**: `deployApi=true` or `deployUi=true`, AND deployment guard passes  
**Needs**: `summary`, `bootstrap-dev`, `bootstrap-staging`, `bootstrap-prod`

**Deployment guard logic**:
- When `bootstrapInfra=true`: Deployments are **blocked** unless the bootstrap job for the target environment succeeded. This prevents deploying to environments where infrastructure provisioning failed.
- When `bootstrapInfra=false` (deploy-only run): Deployments proceed without bootstrap checks — assumes infrastructure already exists.

**Actions**:
- Dispatches `deploy-api-to-azure.yml` via `workflow_dispatch` (if `deployApi=true`)
- Dispatches `deploy-ui-to-azure.yml` via `workflow_dispatch` (if `deployUi=true`)
- Deployment workflows determine their target environment from the branch name
- Adds a deployment summary with links to the triggered workflow runs

---

## 🎬 Usage Scenarios

### Scenario 1: First Bootstrap (After Initial Setup)

After the Azure Initial Setup workflow has completed:

```yaml
environment: dev
bootstrapInfra: true    # Provision all Azure resources
deployApi: true         # Deploy API after bootstrap
deployUi: true          # Deploy UI after bootstrap
cleanupInfra: false
```

### Scenario 2: Bootstrap Only (No Deployment)

```yaml
environment: dev
bootstrapInfra: true
deployApi: false
deployUi: false
cleanupInfra: false
```

### Scenario 3: Deploy Only (Infrastructure Already Exists)

```yaml
environment: dev
bootstrapInfra: false   # Skip — infra already provisioned
deployApi: true
deployUi: true
cleanupInfra: false
```

### Scenario 4: Add Staging Environment

OIDC credentials are already stored — just provision staging infrastructure:

```yaml
# Run from 'staging' branch
environment: staging
bootstrapInfra: true
deployApi: true
deployUi: true
cleanupInfra: false
```

### Scenario 5: Bootstrap All Environments

```yaml
# Run from any branch with environment=all
environment: all
bootstrapInfra: true
deployApi: true
deployUi: true
cleanupInfra: false
```

### Scenario 6: Tear Down an Environment

```yaml
environment: dev
bootstrapInfra: false   # Never combine with cleanup
deployApi: false
deployUi: false
cleanupInfra: true      # ⚠️ DESTRUCTIVE — deletes everything
```

---

## ⚠️ Post-Clean-Deploy Checklist (After Bootstrap + API Deploy)

Prompt reference for manual post-deploy commands:
- [Prompt README](../../.github/prompts/README.md)

After a **full clean deployment** (resource group deleted and recreated), the bootstrap workflow automatically recreates the SQL contained user for the App Service managed identity.

**Bootstrap handles this automatically — no manual steps required:**
```powershell
# Managed identity SQL setup is automated inside azure-bootstrap.yml:
# - setup-sql-managed-identity.ps1 is called on every bootstrap run
# - No manual /sql-mi-setup step needed
```

| Step | Action | Required after clean deploy? |
|------|--------|-----------------------------|
| 1 | Run `azure-bootstrap.yml` (bootstrapInfra + deployApi) | ✅ |
| 2 | Verify `/api/orders` returns 200 (not 500) | ✅ |
| 3 | Optional: open SQL firewall for local SSMS via `/xylab-sql-local-access` | Optional |

Short validation check in SSMS:

```sql
SELECT login_name, program_name
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
    AND database_id = DB_ID('OrderProcessingSystem_Dev')
```

Expected result:
- After bootstrap completes and the API is called, you should see a `Core Microsoft SqlClient Data Provider` row with a GUID-like `login_name` instead of `sqladmin`.
- That GUID-like `login_name` is the expected token-based Azure AD / managed identity session and is a valid success signal.

### If SQL Managed Identity Setup Fails With Entra Permission Error

If bootstrap reaches `Configure SQL Managed Identity Database User` but fails with either of these messages:

- `Could not resolve managed identity appId`
- `ERROR: Insufficient privileges to complete the operation.`

the existing `GitHub-Actions-OIDC` app registration is missing Microsoft Entra read permission needed to resolve the App Service managed identity `appId/clientId`.

Azure Portal fix:

1. Go to `Azure Portal -> Microsoft Entra ID -> App registrations`
2. Open `GitHub-Actions-OIDC`
3. Open `API permissions`
4. Click `Add a permission`
5. Choose `Microsoft Graph`
6. Choose `Application permissions`
7. Add `Application.Read.All`
8. Click `Grant admin consent`
9. Wait 1 to 3 minutes
10. Re-run `Azure Bootstrap & Deploy`

If the error still persists, repeat the same flow and also add `Directory.Read.All`, grant admin consent, wait briefly, and re-run the workflow.

Do not run cleanup for this issue. The resources are already provisioned; only the Entra permission gap needs to be fixed.

> See [TROUBLESHOOTING-INDEX.md](../../TROUBLESHOOTING-INDEX.md#sql-managed-identity-day-35) for full details on the symptom and fix.
>
> See [Prompt README](../../.github/prompts/README.md) for available prompts (`/xylab-day-complete`, `/xylab-sql-local-access`, `/xylab-context-audit`).

---

## 🔍 Monitoring & Troubleshooting

### View Workflow Progress

1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
2. Click on "Azure Bootstrap & Deploy"
3. Expand each job to see real-time logs

### Common Issues

#### validate-inputs fails: "OIDC SECRETS MISSING"

**Cause**: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, or `AZUREAPPSERVICE_SUBSCRIPTIONID` are not configured.

**Fix**: Run the **Azure Initial Setup** workflow first:
1. Go to **Actions → Azure Initial Setup → Run workflow**
2. All defaults are correct (`environment=all`, Phase 1a + 1b enabled)
3. Click **Run workflow** and wait for completion
4. Re-run this workflow after Initial Setup completes

#### validate-inputs fails: "BRANCH MISMATCH ERROR"

**Cause**: The "Use workflow from" branch does not match the selected environment.

**Fix**: Set "Use workflow from" to the correct branch:
- `dev` branch → `dev` environment
- `staging` branch → `staging` environment
- `main` branch → `prod` environment

#### AADSTS700213: No matching federated identity record

**Cause**: The Azure AD App Registration is missing the federated credential for the target environment. This typically occurs when the Azure Initial Setup workflow was run for `dev` only, not `all`.

**Fix**: Re-run the Azure Initial Setup workflow with `environment=all` to create federated credentials for all environments.

#### Bootstrap fails with "DEPLOYMENT BLOCKED"

**Cause**: The OIDC credentials exist at the repository level but not at the environment level, or the federated credential subject doesn't match.

**Fix**:
1. Re-run Azure Initial Setup with `environment=all`
2. Verify federated credentials: `az ad app federated-credential list --id <app-object-id>`

#### "Resource Group creation timeout"

- Check Azure subscription quotas
- Verify region availability (`centralindia`)
- Re-run workflow after verifying Azure status

#### Deployments skipped after bootstrap failure

**Cause**: The deployment guard blocks API/UI dispatches when the bootstrap job for the target environment fails.

**Fix**: Fix the bootstrap error first, then re-run the workflow. Check the summary job output for a failure diagnosis with likely causes and remediation steps.

#### Configure SQL Managed Identity Database User fails with "Insufficient privileges"

**Cause**: The `GitHub-Actions-OIDC` app can authenticate to Azure but cannot read Microsoft Entra service principal metadata required by `setup-sql-managed-identity.ps1`.

**Fix**:
1. `Azure Portal -> Microsoft Entra ID -> App registrations`
2. Open `GitHub-Actions-OIDC`
3. `API permissions -> Add a permission -> Microsoft Graph -> Application permissions`
4. Add `Application.Read.All`
5. Click `Grant admin consent`
6. Wait 1 to 3 minutes and re-run bootstrap
7. If still failing, also add `Directory.Read.All`, grant consent, wait briefly, and re-run

### Verify Setup Completion

```bash
# List provisioned Azure resource groups
az group list --query "[?starts_with(name, 'rg-orderprocessing')].name"

# Verify App Services exist
az webapp list --query "[?contains(name, 'orderprocessing')].{Name:name, State:state}" -o table

# Check Key Vault
az keyvault list --query "[?starts_with(name, 'kv-orderproc')].{Name:name, Location:location}" -o table

# Verify OIDC secrets are configured (prerequisites)
gh secret list --repo pavanthakur/XYDataLabs.OrderProcessingSystem
```

---

## 🔐 Security Considerations

### Authentication

| Operation | Method | Interactive? |
|-----------|--------|-------------|
| Phase A (bootstrap) | `azure/login@v2` (OIDC) | ❌ No — fully automated |
| Phase X (cleanup) | `azure/login@v2` (OIDC) | ❌ No — fully automated |
| Deploy triggers | `GITHUB_TOKEN` | ❌ No — automatic |

No passwords, PATs, or certificates are stored. Azure authentication uses OIDC token exchange via `AZUREAPPSERVICE_*` environment secrets.

### Required Permissions

**Azure Subscription** (for bootstrap):
- Owner or Contributor + User Access Administrator
- Required to create resource groups, App Services, SQL, Key Vault, and assign Contributor RBAC to the OIDC service principal

**GitHub** (for deployment triggers):
- `contents: write`, `id-token: write`, `actions: write` — workflow permissions
- `GITHUB_TOKEN` is sufficient for dispatching deployment workflows

### Secret Usage

This workflow reads secrets — it does **not** create or modify them. Secret management is handled by the [Azure Initial Setup](README-AZURE-INITIAL-SETUP.md) workflow.

| Secret | Used by | Purpose |
|--------|---------|---------|
| `AZUREAPPSERVICE_CLIENTID` | Bootstrap + cleanup jobs | OIDC client ID for `azure/login@v2` |
| `AZUREAPPSERVICE_TENANTID` | Bootstrap + cleanup jobs | Azure tenant ID |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Bootstrap + cleanup jobs | Azure subscription ID |
| `APP_ID` | Bootstrap jobs (optional) | GitHub App token generation for enhanced operations |
| `APP_PRIVATE_KEY` | Bootstrap jobs (optional) | GitHub App private key |

---

## 📊 Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│  User triggers workflow via GitHub UI                                │
│  Selects: environment, bootstrapInfra, deployApi, deployUi, cleanup  │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   validate-inputs    │
                    │  (always runs)       │
                    │  ✓ Branch/env match  │
                    │  ✓ OIDC secrets check│
                    │  ✓ Pre-flight summary│
                    └──────────┬───────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                     │
          ▼                    ▼                     ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  bootstrap-dev   │ │ bootstrap-staging│ │  bootstrap-prod  │
│  (Phase A)       │ │  (Phase A)      │ │  (Phase A)       │
│  ① Validate creds│ │  ① Validate creds│ │  ① Validate creds│
│  ② azure/login   │ │  ② azure/login  │ │  ② azure/login   │
│  ③ Run bootstrap │ │  ③ Run bootstrap│ │  ③ Run bootstrap  │
└────────┬─────────┘ └────────┬────────┘ └────────┬──────────┘
         │                    │                    │
         ├────────────────────┼────────────────────┤
         │                    │                    │
         ▼                    ▼                    ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  cleanup-dev     │ │ cleanup-staging  │ │  cleanup-prod    │
│  (Phase X ⚠️)    │ │  (Phase X ⚠️)    │ │  (Phase X ⚠️)    │
│  DESTRUCTIVE     │ │  DESTRUCTIVE     │ │  DESTRUCTIVE     │
└────────┬─────────┘ └────────┬────────┘ └────────┬──────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │       summary        │
                   │   (always runs)      │
                   │   Aggregates results │
                   │   Failure diagnosis  │
                   └──────────┬───────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │  trigger-deployments │
                   │  (if deploy selected)│
                   │  ① Deployment guard  │
                   │  ② Dispatch API wf   │
                   │  ③ Dispatch UI wf    │
                   └──────────────────────┘
```

> **Note**: Bootstrap and cleanup jobs only run for the selected environment(s). When `environment=all`, all three run in parallel.

---

## ✅ Success Criteria

After bootstrap succeeds:

- [ ] Resource groups `rg-orderprocessing-dev` / `rg-orderprocessing-stg` / `rg-orderprocessing-prod` created in Azure
- [ ] App Service Plans and Web Apps provisioned
- [ ] Azure SQL Server + Database provisioned
- [ ] Key Vault (`kv-orderproc-{dev|stg|prod}`) provisioned
- [ ] Application Insights created
- [ ] System-assigned managed identity enabled on App Services
- [ ] RBAC (Contributor) assigned to OIDC service principal

After deployment triggers succeed:

- [ ] `deploy-api-to-azure.yml` dispatched and API accessible at target environment
- [ ] `deploy-ui-to-azure.yml` dispatched and UI accessible at target environment

---

## 📚 Related Documentation

| Document | Location |
|----------|----------|
| **Azure Initial Setup** (prerequisite) | [`README-AZURE-INITIAL-SETUP.md`](README-AZURE-INITIAL-SETUP.md) |
| Full Quick Start Guide | [`Documentation/QUICK-START-AZURE-BOOTSTRAP.md`](../../Documentation/QUICK-START-AZURE-BOOTSTRAP.md) |
| Workflow Separation Architecture | [`Documentation/GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md`](../../Documentation/GITHUB-WORKFLOW-SEPARATION-ARCHITECTURE.md) |
| Configure GitHub Secrets | [`README-CONFIGURE-GITHUB-SECRETS.md`](README-CONFIGURE-GITHUB-SECRETS.md) |
| Azure Deployment Guide | [`Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md`](../../Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md) |
| Bootstrap Script | `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1` |
| Troubleshooting Index | [`TROUBLESHOOTING-INDEX.md`](../../TROUBLESHOOTING-INDEX.md) |

---

**Last Updated**: 2026-03-19  
**Workflow Version**: Current (`azure-bootstrap.yml` — "Azure Bootstrap & Deploy")  
**Maintainer**: GitHub Copilot
