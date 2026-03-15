# 🚀 Azure Bootstrap - Quick Start Guide

## 🗺️ High-Level Summary

The **Azure Bootstrap workflow** (`azure-bootstrap.yml`) is a one-stop GitHub Actions workflow that takes a brand-new repository from zero to a fully deployed Azure environment.  
It handles everything — Azure authentication, GitHub secrets, cloud infrastructure, and optionally application deployment — in a single, menu-driven run.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     BOOTSTRAP OVERVIEW                                      │
│                                                                             │
│  PHASE 0 — Manual Prerequisite (~5 min, done ONCE)                         │
│  └── Create GitHub App → Install on repo → Add APP_ID + APP_PRIVATE_KEY    │
│                                ↓                                            │
│  PHASE 1 — One-Time Azure Setup (~4 min, done ONCE after Phase 0)          │
│  ├── setupOidc       → Creates Microsoft Entra ID App Registration          │
│  │                     + Federated credentials for passwordless auth        │
│  └── configureSecrets → Writes AZUREAPPSERVICE_* to GitHub repo + envs     │
│                                ↓                                            │
│  PHASE 2 — Day-to-Day Operations (run as needed)                            │
│  ├── bootstrapInfra  → Resource Groups, App Services, SQL, Key Vault        │
│  ├── deployApi       → API code deployed to Azure App Service               │
│  └── deployUi        → UI code deployed to Azure App Service                │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Key rule**: Complete the phases in order. Phase 0 and Phase 1 are each done **once** — after they are complete, day-to-day operations only use Phase 2.

### When do I run each phase?

| Phase | When to Run | Parameters |
|-------|-------------|------------|
| **Phase 0** | Once — before anything else | Manual only (no workflow run) |
| **Phase 1** | Once — after Phase 0 is complete | `setupOidc` + `configureSecrets` |
| **Phase 2** | Any time — infrastructure and deployments | `bootstrapInfra` + `deployApi` / `deployUi` |

### What gets created automatically vs. what needs manual work

| Resource | Automated? | Phase |
|----------|-----------|-------|
| Microsoft Entra ID App Registration | ✅ Fully automated | Phase 1 (`setupOidc`) |
| Azure Federated OIDC Credentials | ✅ Fully automated | Phase 1 (`setupOidc`) |
| GitHub Environments (dev / staging / prod) | ✅ Fully automated | Phase 1 (`configureSecrets`) |
| GitHub OIDC Secrets (`AZUREAPPSERVICE_*`) | ✅ Fully automated | Phase 1 (`configureSecrets`) |
| Azure Resource Groups, App Services, SQL | ✅ Fully automated | Phase 2 (`bootstrapInfra`) |
| Deploy API code to Azure App Service | ✅ Fully automated | Phase 2 (`deployApi`) |
| Deploy UI code to Azure App Service | ✅ Fully automated | Phase 2 (`deployUi`) |
| **GitHub App** (`APP_ID` + `APP_PRIVATE_KEY`) | ⚠️ **Manual one-time** | Phase 0 |

---

## 📋 Workflow Parameter Reference

Navigate to: **GitHub → Actions → Azure Bootstrap Setup → Run workflow**

Parameters are grouped by the phase they belong to. Enable only the parameters for the phase you are currently running.

---

### 🎯 `environment` — Target Environment *(always required)*
| | |
|---|---|
| **Type** | Choice: `dev` / `staging` / `prod` / `all` |
| **Required** | Yes — every run |
| **Description** | Which Azure environment to provision. `all` provisions dev, staging, and prod in parallel. |
| **Branch rule** | The **"Use workflow from"** branch must match the environment: `dev`→`dev`, `staging`→`staging`, `main`→`prod`. Use any branch for `all`. |
| **Example** | Start with `dev` to validate the setup cheaply before committing to staging/prod. |

---

## 🔑 Phase 1 Parameters — One-Time Setup
> Enable these **once** when setting up a new environment. After Phase 1 is complete, you will not need to run these again unless credentials are lost or rotated.

### `setupOidc` — Setup Azure OIDC
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **Phase** | 🔑 Phase 1 — one-time setup |
| **When to enable** | **First time only.** Also re-run if federated credentials are corrupted or deleted. |
| **What it does** | Logs in to Azure via interactive device code, then creates (or updates) the **`GitHub-Actions-OIDC`** App Registration in Microsoft Entra ID. Creates a Service Principal and configures federated credentials so GitHub Actions can authenticate to Azure without passwords. |
| **Output** | `clientId`, `tenantId`, `subscriptionId` — passed automatically to `configureSecrets`. |
| **Requires** | Azure account with permission to create App Registrations (Application Administrator or Owner). |
| **Skip when** | Secrets `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` already exist and are valid. |
| **Idempotent** | ✅ Yes — re-running adds missing federated credentials without removing existing ones. |

### `oidcAppName` — OIDC App Name *(advanced, optional)*
| | |
|---|---|
| **Type** | String (default: `GitHub-Actions-OIDC`) |
| **Phase** | 🔑 Phase 1 — used only when `setupOidc = true` |
| **When to change** | Only if you need a custom name for the Entra ID App Registration. Leave blank for the default. |

### `configureSecrets` — Configure GitHub Secrets
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **Phase** | 🔑 Phase 1 — one-time setup |
| **When to enable** | After `setupOidc` has run (or OIDC credentials already exist) **and** the GitHub App is installed with `APP_ID` + `APP_PRIVATE_KEY` secrets present. |
| **What it does** | Uses the GitHub App token to write `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, and `AZUREAPPSERVICE_SUBSCRIPTIONID` as both repository secrets and per-environment secrets (auto-creates the GitHub environments if missing). |
| **Prerequisite** | `APP_ID` and `APP_PRIVATE_KEY` repository secrets **must already exist**. See [Phase 0 Setup](#phase-0--manual-prerequisite-5-min-done-once) below. |
| **Idempotent** | ✅ Yes — overwrites existing secrets with current values. |

> 💡 **Tip**: Run `setupOidc` and `configureSecrets` **together in a single workflow execution** — they are designed to chain: OIDC outputs feed directly into secret configuration.

---

## 🔄 Phase 2 Parameters — Day-to-Day Operations
> Enable these whenever you need to provision or update infrastructure and deployments. Safe to run repeatedly.

### `bootstrapInfra` — Bootstrap Infrastructure
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **Phase** | 🔄 Phase 2 — day-to-day |
| **When to enable** | After Phase 1 is complete (or secrets already exist). Re-run any time to reprovision or add resources. |
| **What it creates** | Azure Resource Group, App Service Plan, API Web App, UI Web App, Application Insights, Azure SQL Server + Database, Key Vault, and connection string configuration. |
| **Requires** | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` secrets (from Phase 1). |
| **Idempotent** | ✅ Yes — skips resources that already exist. Safe to re-run to add missing pieces. |

### `deployApi` — Deploy API
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **Phase** | 🔄 Phase 2 — day-to-day |
| **When to enable** | After infrastructure is bootstrapped. Enable to deploy the latest API code. |
| **What it does** | Triggers the `deploy-api-to-azure.yml` workflow for the selected environment after bootstrap completes. |

### `deployUi` — Deploy UI
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **Phase** | 🔄 Phase 2 — day-to-day |
| **When to enable** | After infrastructure is bootstrapped. Enable to deploy the latest UI code. |
| **What it does** | Triggers the `deploy-ui-to-azure.yml` workflow for the selected environment after bootstrap completes. |

---

## 🔍 Optional Parameter

### `enableValidation` — Pre-Flight Validation
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | Recommended for all Phase 2 runs. Validates branch/environment alignment and checks that all Phase 1 secrets are present before proceeding. |
| **What it does** | Validates that branch/environment alignment is correct and that OIDC credentials and GitHub App secrets are all present before proceeding. |
| **Tip** | Disable for the very first Phase 1 run to reduce friction; enable for all Phase 2 runs and beyond. |

---

## ℹ️ Phase 0 Helper Parameter

### `setupGitHubApp` — GitHub App Instructions
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | Enable if `APP_ID` or `APP_PRIVATE_KEY` secrets are missing and you need step-by-step guidance. |
| **What it does** | Checks whether `APP_ID` and `APP_PRIVATE_KEY` secrets already exist and prints setup instructions if they are missing. **It does not create the app.** |
| **Why not automated?** | GitHub's security model requires interactive user approval to create an OAuth/GitHub App. This is by design and cannot be bypassed. |
| **⚠️ Action required** | See [Phase 0 Setup](#phase-0--manual-prerequisite-5-min-done-once) below — this one-time manual step must be completed **before** Phase 1 can succeed. |

---

## 🔐 Phase 0 — Manual Prerequisite: GitHub App Setup

> **This is the only step that cannot be automated.** GitHub requires interactive user authorization to create an app. It takes approximately 5 minutes and only needs to be done **once**.  
> Once complete, you never need to do this again unless the GitHub App or its secrets are lost.

### Step 1: Create the GitHub App

1. Go to: https://github.com/settings/apps/new  
   *(or https://github.com/organizations/YOUR-ORG/settings/apps/new for org repos)*
2. Fill in the form:
   - **App name**: `XYDataLabs-OrderProcessing-Automation` (or any name you choose)
   - **Homepage URL**: `https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem`
   - **Webhook**: Uncheck "Active" (not needed)
3. Under **Repository permissions**, set all of the following:

   | Permission | Level | Purpose |
   |------------|-------|---------|
   | **Actions** | `Read and write` | Trigger and manage workflow runs |
   | **Secrets** | `Read and write` ✅ | Create/update repository secrets *(critical)* |
   | **Workflows** | `Read and write` | Update workflow files |
   | **Pull requests** | `Read and write` | Create PRs for config changes |
   | **Administration** | `Read and write` | Manage repository settings |
   | **Environments** | `Read and write` ✅ | Create/update deployment environments *(critical)* |
   | **Contents** | `Read-only` | Read repository files |
   | **Metadata** | `Read-only` | Read repository metadata |

   > ⚠️ **Permissions are NOT set automatically** — they must be configured at app creation (use `app-manifest.json`) or verified manually for an existing app.  
   > 📍 To verify/update permissions on an existing app: `https://github.com/settings/apps/{your-app-slug}/permissions`

4. Click **Create GitHub App**
5. **Copy the App ID** shown at the top of the settings page

### Step 2: Generate a Private Key

1. On the same app settings page, scroll to **Private keys**
2. Click **Generate a private key**
3. A `.pem` file downloads automatically — **save it securely**
4. Open the file in a text editor — you need its full contents in the next step

### Step 3: Install the App on the Repository

1. In the left sidebar of your app settings page, click **Install App**
2. Click **Install** next to your account
3. Select **Only select repositories** → choose `XYDataLabs.OrderProcessingSystem`
4. Click **Install**

### Step 4: Add Repository Secrets

Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

Add these **2 secrets**:

| Secret Name | Value | Notes |
|-------------|-------|-------|
| `APP_ID` | The numeric App ID from Step 1 | Example: `123456` |
| `APP_PRIVATE_KEY` | Full contents of the `.pem` file | Include the `-----BEGIN...-----` and `-----END...-----` lines |

> **Note**: `APP_INSTALLATION_ID` is no longer required — it is auto-discovered at runtime.

✅ Once these two secrets exist, you are ready to run the bootstrap workflow.

---

## 🚀 From-Scratch Setup: Step-by-Step Sequence

Follow this sequence for a brand-new deployment. Each phase builds on the previous one.

---

### Phase 0 — Manual Prerequisite (~5 min, done once)

Complete the [GitHub App setup](#-phase-0--manual-prerequisite-github-app-setup) above.  
Add `APP_ID` and `APP_PRIVATE_KEY` to repository secrets before proceeding.

✅ **Done when**: Both `APP_ID` and `APP_PRIVATE_KEY` secrets exist at `settings/secrets/actions`.  
🚫 **Do not proceed to Phase 1 until Phase 0 is complete.**

---

### Phase 1 — One-Time Azure Setup (~4 min, done once after Phase 0)

**Goal**: Create the Azure OIDC identity and push credentials into GitHub. This runs **once per environment** — after this, you never need to run `setupOidc` or `configureSecrets` again unless credentials are rotated or lost.

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure parameters — check **only** the Phase 1 boxes:

| Parameter | Value | Notes |
|-----------|-------|-------|
| `environment` | `dev` | Start with dev to validate cheaply |
| `setupOidc` ✅ | `true` | 🔑 Phase 1 — creates Entra ID app + OIDC credentials |
| `oidcAppName` | *(default)* | Leave blank (uses `GitHub-Actions-OIDC`) |
| `setupGitHubApp` | `false` | Already done in Phase 0 |
| `configureSecrets` ✅ | `true` | 🔑 Phase 1 — writes `AZUREAPPSERVICE_*` secrets to GitHub |
| `enableValidation` | `false` | Skip for first run |
| `bootstrapInfra` | `false` | 🔄 Phase 2 — do this separately |
| `deployApi` | `false` | 🔄 Phase 2 |
| `deployUi` | `false` | 🔄 Phase 2 |

4. Click **Run workflow**
5. When the workflow pauses for **device code authentication** (during `setupOidc`):
   - Open https://microsoft.com/devicelogin
   - Enter the code shown in the workflow logs
   - Sign in with your Azure account (must have App Registration permissions)
6. Wait for the job to complete

**What gets created**:
- `GitHub-Actions-OIDC` App Registration in Azure with federated credentials
- GitHub repository secrets: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`
- GitHub environment `dev` with matching environment secrets

✅ **Done when**: All three `AZUREAPPSERVICE_*` secrets appear at `settings/secrets/actions`.  
🚫 **Do not re-run Phase 1 unless credentials are lost or rotated.**

---

### Phase 2 — Day-to-Day Operations (run as needed)

**Goal**: Provision Azure infrastructure and deploy application code. This is what you run regularly — safe to re-run at any time.

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure parameters — check **only** the Phase 2 boxes:

| Parameter | Value | Notes |
|-----------|-------|-------|
| `environment` | `dev` | |
| `setupOidc` | `false` | 🔑 Phase 1 — already done, skip |
| `oidcAppName` | *(default)* | |
| `setupGitHubApp` | `false` | Phase 0 — already done, skip |
| `configureSecrets` | `false` | 🔑 Phase 1 — already done, skip |
| `enableValidation` ✅ | `true` | Recommended — validates Phase 1 is complete before proceeding |
| `bootstrapInfra` ✅ | `true` | 🔄 Phase 2 — creates/updates Azure resources |
| `deployApi` | `false` (or `true`) | 🔄 Phase 2 — enable to deploy API code immediately |
| `deployUi` | `false` (or `true`) | 🔄 Phase 2 — enable to deploy UI code immediately |

4. Click **Run workflow**

**What gets created**: `rg-orderprocessing-dev` resource group with App Service Plan, API + UI Web Apps, Application Insights, Azure SQL Server & Database, Key Vault.

> 💡 **Re-running Phase 2 is safe**: Every resource is idempotent — existing resources are skipped, missing ones are created. Run it any time infrastructure needs to be refreshed.

---

### Phase 2 — Deploying Application Code

After infrastructure is ready, deploy application code:
- **Via Phase 2 bootstrap**: Run workflow with `deployApi = true` and/or `deployUi = true`
- **Via push**: Push to the `dev` branch — deployment workflows trigger automatically
- **Via manual dispatch**: Run `deploy-api-to-azure.yml` or `deploy-ui-to-azure.yml` directly

---

### Quick Reference: What to check for each run

| Goal | `setupOidc` | `configureSecrets` | `bootstrapInfra` | `deployApi` | `deployUi` |
|------|-------------|---------------------|------------------|-------------|------------|
| First-time full setup (Phase 1 + 2) | ✅ | ✅ | ✅ | optional | optional |
| Phase 1 only (OIDC + secrets) | ✅ | ✅ | ❌ | ❌ | ❌ |
| Phase 2 only (infra + deploy) | ❌ | ❌ | ✅ | optional | optional |
| Redeploy code only | ❌ | ❌ | ❌ | ✅ | ✅ |
| Rotate credentials | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## 🔄 Common Scenarios

### Scenario A: Brand-New Dev Environment (Phase 0 already done)
```yaml
# Phase 1 (one-time) + Phase 2 combined in a single run
environment: dev
setupOidc: true          # 🔑 Phase 1 — Create Entra ID app + OIDC
oidcAppName: ""          # Use default (GitHub-Actions-OIDC) — only change if custom name needed
setupGitHubApp: false    # Phase 0 done — skip
configureSecrets: true   # 🔑 Phase 1 — Write Azure creds to GitHub secrets
enableValidation: true   # Validate everything
bootstrapInfra: true     # 🔄 Phase 2 — Provision Azure resources
deployApi: false         # 🔄 Phase 2 — Enable once infra is confirmed healthy
deployUi: false          # 🔄 Phase 2 — Enable once infra is confirmed healthy
```
**Time**: ~15 min | **Use case**: Complete first-time dev environment setup in one go

---

### Scenario B: Add Staging (Phase 1 already done for dev)
```yaml
# Phase 2 only — OIDC and secrets already exist from dev setup
environment: staging      # Switch to staging branch first!
setupOidc: false         # 🔑 Phase 1 done — skip
oidcAppName: ""          # N/A (setupOidc is false)
setupGitHubApp: false    # Phase 0 done — skip
configureSecrets: false  # 🔑 Phase 1 done — skip (or set true to create staging secrets)
enableValidation: true
bootstrapInfra: true     # 🔄 Phase 2 — Provision staging resources
deployApi: false
deployUi: false
```
**Time**: ~10 min | **Use case**: Add staging after dev is already running

---

### Scenario C: Re-provision Infrastructure (Phase 1 already done)
```yaml
# Phase 2 only — credentials are fine, just re-create Azure resources
environment: dev
setupOidc: false         # 🔑 Phase 1 done — credentials still valid
oidcAppName: ""          # N/A (setupOidc is false)
setupGitHubApp: false    # Phase 0 done — skip
configureSecrets: false  # 🔑 Phase 1 done — secrets still valid
enableValidation: false  # Skip for speed
bootstrapInfra: true     # 🔄 Phase 2 — Re-provision Azure resources
deployApi: false
deployUi: false
```
**Time**: ~10 min | **Use case**: Infrastructure was accidentally deleted; OIDC and secrets are intact

---

### Scenario D: Rotate Azure Credentials
```yaml
# Re-run Phase 1 to refresh credentials and secrets
environment: dev
setupOidc: true          # 🔑 Phase 1 — Re-create OIDC credentials
oidcAppName: ""          # Use default unless your app uses a custom name
setupGitHubApp: false
configureSecrets: true   # 🔑 Phase 1 — Update GitHub secrets with new values
enableValidation: false
bootstrapInfra: false    # 🔄 Phase 2 — Skip, infra untouched
deployApi: false
deployUi: false
```
**Time**: ~4 min | **Use case**: Azure credentials rotated; GitHub secrets need updating

---

### Scenario E: Bootstrap All Environments at Once
```yaml
# Phase 1 + Phase 2 for all environments simultaneously
environment: all          # Use any branch
setupOidc: true          # 🔑 Phase 1 — Creates credentials for dev + staging + prod
oidcAppName: ""          # Use default unless using a custom Entra app name
setupGitHubApp: false    # Phase 0 already done
configureSecrets: true   # 🔑 Phase 1 — Secrets for all three environments
enableValidation: false  # Skip for initial setup
bootstrapInfra: true     # 🔄 Phase 2 — Provisions dev + staging + prod in parallel
deployApi: false
deployUi: false
```
**Time**: ~15 min | **Use case**: Full environment fleet setup in one go

---

## 📋 What Gets Created

### Microsoft Entra ID (OIDC)
- **App Registration**: `GitHub-Actions-OIDC`
- **Federated Credentials**:
  - Branch-based: `dev`, `staging`, `main`
  - Environment-based: `dev`, `staging`, `prod`
- **Service Principal**: Auto-created with `Contributor` role at subscription scope

### GitHub
- **Repository Secrets**: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`
- **GitHub Environments**: `dev`, `staging`, `prod` (auto-created)
- **Environment Secrets**: Same three secrets in each environment

### Azure Resources (Per Environment)

| Resource | Dev (F1 Free) | Staging (B1) | Prod (P1v3) |
|----------|--------------|--------------|-------------|
| Resource Group | `rg-orderprocessing-dev` | `rg-orderprocessing-stg` | `rg-orderprocessing-prod` |
| App Service Plan | `asp-orderprocessing-dev` | `asp-orderprocessing-stg` | `asp-orderprocessing-prod` |
| API Web App | `pavanthakur-orderprocessing-api-xyapp-dev` | `…-stg` | `…-prod` |
| UI Web App | `pavanthakur-orderprocessing-ui-xyapp-dev` | `…-stg` | `…-prod` |
| Application Insights | `ai-orderprocessing-dev` | `…-stg` | `…-prod` |
| SQL Server | `orderprocessing-sql-dev` | `…-stg` | `…-prod` |
| SQL Database | `OrderProcessingSystem_Dev` | `…_Stg` | `…_Prod` |

---

## 🗑️ What Can Be Deleted and Re-Created

| Resource | Safe to Delete? | How to Re-Create |
|----------|----------------|------------------|
| GitHub Environments (`settings/environments`) | ✅ Yes | Re-run Phase 1 with `configureSecrets = true` |
| `AZUREAPPSERVICE_*` secrets | ✅ Yes | Re-run Phase 1 with `setupOidc = true` + `configureSecrets = true` |
| `APP_ID` + `APP_PRIVATE_KEY` secrets | ⚠️ Caution | Must redo [Phase 0 Setup](#-phase-0--manual-prerequisite-github-app-setup) |
| GitHub App Installation (`settings/installations`) | ⚠️ Caution | Must re-install app + update `APP_ID` + `APP_PRIVATE_KEY` |
| Azure Resource Groups / App Services | ✅ Yes | Re-run Phase 2 with `bootstrapInfra = true` |
| Entra ID App Registration | ✅ Yes | Re-run Phase 1 with `setupOidc = true` |

---

## ✅ Verification Checklist

After the full bootstrap, verify each area:

### GitHub Settings
- [ ] https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions  
  → Secrets `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`, `APP_ID`, `APP_PRIVATE_KEY` all present
- [ ] https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/environments  
  → Environment `dev` (and `staging`, `prod` if bootstrapped) with their own secrets
- [ ] https://github.com/settings/installations  
  → GitHub App installed on `XYDataLabs.OrderProcessingSystem`

### Azure Portal
- [ ] [Microsoft Entra ID → App registrations](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps) → `GitHub-Actions-OIDC` exists with federated credentials
- [ ] [Resource Groups](https://portal.azure.com/#blade/HubsExtension/BrowseResourceGroups) → `rg-orderprocessing-dev` exists with App Service Plan, 2 Web Apps, App Insights

### End-to-End Test
```bash
# Trigger a deployment to verify everything works end-to-end
git checkout dev
echo "# bootstrap test" >> README.md
git add README.md && git commit -m "test: verify bootstrap end-to-end"
git push origin dev
```
Watch Actions → the `deploy-api-to-azure.yml` workflow should trigger and succeed.

---

## 🔧 Troubleshooting

### Issue: "Device code timeout" during Setup OIDC
**Cause**: The 3-minute authentication window expired.  
**Fix**: Re-run the workflow — you'll get a fresh device code.

### Issue: "APP_ID / APP_PRIVATE_KEY secrets MISSING" warning in validate-inputs
**Cause**: GitHub App has not been configured yet.  
**Fix**: Complete [Phase 0 — GitHub App Setup](#-phase-0--manual-prerequisite-github-app-setup) and add the two secrets before re-running.

### Issue: `configureSecrets` step fails with "GitHub App token generation failed"
**Cause**: The app is not installed on the repository, or `APP_ID`/`APP_PRIVATE_KEY` are wrong.  
**Fix**:
1. Verify secrets at `settings/secrets/actions`
2. Verify the app is installed at `settings/installations`
3. Re-generate a private key and update `APP_PRIVATE_KEY` if in doubt

### Issue: "App already exists" during Setup OIDC
**Cause**: Expected — the OIDC app already exists and is being updated.  
**Fix**: No action needed; the workflow reuses the existing app and adds any missing federated credentials.

### Issue: Bootstrap Infrastructure fails with RBAC error
**Cause**: Azure role assignment propagation can take a few minutes.  
**Fix**: Wait 5 minutes and re-run with only `bootstrapInfra = true`.

### Issue: Branch/environment mismatch error
**Cause**: "Use workflow from" branch does not match the target environment.  
**Fix**: Match the branch to the environment: `dev` branch → `dev` env, `main` branch → `prod` env. Use any branch only for `environment: all`.

---

## 🚀 Next Steps After Bootstrap

1. **Verify live endpoints**
   - Dev API: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
   - Dev UI: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

2. **Enable continuous deployment**  
   Push to `dev` → auto-deploys to dev environment.  
   Push to `main` → auto-deploys to prod environment.

3. **Add Application Insights telemetry**  
   Follow: `Documentation/02-Azure-Learning-Guides/APP_INSIGHTS_AUTOMATED_SETUP.md`

---

## 📚 Related Documentation

| Document | Purpose |
|----------|---------|
| `Documentation/03-Configuration-Guides/AUTOMATED-BOOTSTRAP-GUIDE.md` | Detailed end-to-end automation guide |
| `Documentation/03-Configuration-Guides/GITHUB-APP-AUTOMATION.md` | GitHub App automation reference |
| `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md` | GitHub App quick setup |
| `Documentation/Bootstrap-Workflow-Summary.md` | Bootstrap script parameter reference |
| `Resources/Azure-Deployment/setup-github-oidc.ps1` | OIDC setup script |
| `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1` | Infrastructure bootstrap script |

---

## 💡 Pro Tips

1. **Phase 0 is a true one-time step**: Once the GitHub App is created, installed, and its secrets are in place, you never touch Phase 0 again.
2. **Phase 1 is also one-time per environment**: Run `setupOidc + configureSecrets` once, then only use Phase 2 for all ongoing work.
3. **Phase 2 is idempotent**: Every `bootstrapInfra` run is safe to re-run — existing resources are skipped, missing ones are created. Run it whenever needed.
4. **Start with `dev`**: Validate the full flow on dev (F1 Free tier, no cost) before extending to staging/prod.
5. **Use `all`**: Select `environment: all` to provision dev/staging/prod simultaneously once you're confident.
6. **Save the `.pem` file**: Store the GitHub App private key securely offline — if lost, generate a new one in app settings and update `APP_PRIVATE_KEY`.

---

## 🔑 Why GitHub App (Not PAT)?

| Feature | PAT Token | GitHub App |
|---------|-----------|------------|
| Expiry | Max 1 year (manual renewal) | Never — generated fresh each run |
| Maintenance | Manual renewal required | Zero maintenance |
| Scope | User-level | App-level (more secure) |
| Automation | Can expire mid-pipeline | Fully automated forever |

**Bottom line**: The one-time 5-minute GitHub App setup eliminates all token expiration issues permanently.

---

**Ready to start?**

👉 **Run Workflow**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

Then click **"Run workflow"** (top-right green button)
