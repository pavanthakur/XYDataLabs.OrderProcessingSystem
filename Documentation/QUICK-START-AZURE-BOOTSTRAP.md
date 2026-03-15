# 🚀 Azure Bootstrap - Quick Start Guide

## 🗺️ High-Level Summary

The **Azure Bootstrap workflow** (`azure-bootstrap.yml`) is a one-stop GitHub Actions workflow that takes a brand-new repository from zero to a fully deployed Azure environment.  
It handles everything — Azure authentication, GitHub secrets, cloud infrastructure, and optionally application deployment — in a single, menu-driven run.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     BOOTSTRAP OVERVIEW (first-time setup)                   │
│                                                                             │
│  PRE-REQUISITE (manual, ~5 min)                                             │
│  └── Create GitHub App → Install on repo → Add APP_ID + APP_PRIVATE_KEY    │
│                                ↓                                            │
│  PHASE 1 — Azure Identity (automated, ~3 min)                               │
│  └── Setup OIDC → Creates Microsoft Entra ID App Registration               │
│                   + Federated credentials for passwordless auth             │
│                                ↓                                            │
│  PHASE 2 — GitHub Secrets (automated, ~1 min)                               │
│  └── Configure Secrets → Writes AZUREAPPSERVICE_* to repo + environments   │
│                                ↓                                            │
│  PHASE 3 — Azure Infrastructure (automated, ~10 min)                        │
│  └── Bootstrap Infra → Resource Groups, App Services, SQL, Key Vault        │
│                                ↓                                            │
│  PHASE 4 — Deploy Application (optional, ~5 min each)                       │
│  └── Deploy API + Deploy UI → Live endpoints on Azure App Service           │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Key rule**: The GitHub App (`APP_ID` + `APP_PRIVATE_KEY`) must be configured **before** you run the workflow for the first time. Everything else is automated.

### What gets created automatically vs. what needs manual work

| Resource | Automated? | When |
|----------|-----------|------|
| Microsoft Entra ID App Registration | ✅ Fully automated | `setupOidc = true` |
| Azure Federated OIDC Credentials | ✅ Fully automated | `setupOidc = true` |
| GitHub Environments (dev / staging / prod) | ✅ Fully automated | `configureSecrets = true` |
| GitHub OIDC Secrets (`AZUREAPPSERVICE_*`) | ✅ Fully automated | `configureSecrets = true` |
| Azure Resource Groups, App Services, SQL | ✅ Fully automated | `bootstrapInfra = true` |
| Deploy API code to Azure App Service | ✅ Fully automated | `deployApi = true` |
| Deploy UI code to Azure App Service | ✅ Fully automated | `deployUi = true` |
| **GitHub App** (`APP_ID` + `APP_PRIVATE_KEY`) | ⚠️ **Manual one-time** | Before first workflow run |

---

## 📋 Workflow Parameter Reference

Navigate to: **GitHub → Actions → Azure Bootstrap Setup → Run workflow**

Each parameter is numbered in the order it should first be enabled.

### 🎯 `environment` — Target Environment
| | |
|---|---|
| **Type** | Choice: `dev` / `staging` / `prod` / `all` |
| **Required** | Yes |
| **Description** | Which Azure environment to provision. `all` provisions dev, staging, and prod in parallel. |
| **Branch rule** | The **"Use workflow from"** branch must match the environment: `dev`→`dev`, `staging`→`staging`, `main`→`prod`. Use any branch for `all`. |
| **Example** | Start with `dev` to validate the setup cheaply before committing to staging/prod. |

---

### 1️⃣ `setupOidc` — Setup Azure OIDC
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **When to enable** | **First time only.** Also re-run if federated credentials are corrupted or deleted. |
| **What it does** | Logs in to Azure via interactive device code, then creates (or updates) the **`GitHub-Actions-OIDC`** App Registration in Microsoft Entra ID. Creates a Service Principal and configures federated credentials so GitHub Actions can authenticate to Azure without passwords. |
| **Output** | `clientId`, `tenantId`, `subscriptionId` — passed automatically to the next steps. |
| **Requires** | Azure account with permission to create App Registrations (Application Administrator or Owner). |
| **Skip when** | Secrets `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` already exist and are valid. |
| **Idempotent** | ✅ Yes — re-running adds missing federated credentials without removing existing ones. |

---

### 2️⃣ `setupGitHubApp` — Setup GitHub App (instructions only)
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | Enable when `APP_ID` or `APP_PRIVATE_KEY` repository secrets are missing and you need a reminder of the setup steps. |
| **What it does** | Checks whether `APP_ID` and `APP_PRIVATE_KEY` secrets already exist and prints step-by-step instructions if they are missing. **It does not create the app.** |
| **Why not automated?** | GitHub's security model requires interactive user approval to create an OAuth/GitHub App. This is by design and cannot be bypassed. |
| **⚠️ Action required** | See [GitHub App Manual Setup](#-github-app-manual-setup-required-before-first-run) below — this one-time manual step must be completed **before** `configureSecrets` can succeed. |

---

### `oidcAppName` — OIDC App Name (advanced)
| | |
|---|---|
| **Type** | String (default: `GitHub-Actions-OIDC`) |
| **When to change** | Only if you use a custom name for the Entra ID App Registration. Leave blank for default. |

---

### 3️⃣ `configureSecrets` — Configure GitHub Secrets
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **When to enable** | After `setupOidc` has run (or OIDC credentials already exist) **and** the GitHub App is installed with `APP_ID` + `APP_PRIVATE_KEY` secrets present. |
| **What it does** | Uses the GitHub App token to write `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, and `AZUREAPPSERVICE_SUBSCRIPTIONID` as both repository secrets and per-environment secrets (auto-creates the GitHub environments if missing). |
| **Prerequisite** | `APP_ID` and `APP_PRIVATE_KEY` repository secrets **must already exist**. See the manual setup section below. |
| **Idempotent** | ✅ Yes — overwrites existing secrets with current values. |

---

### 🔍 `enableValidation` — Pre-Flight Validation (optional)
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | Optional. Enable once the environment is stable to run pre-deployment checks before infrastructure runs. |
| **What it does** | Validates that branch/environment alignment is correct and that OIDC credentials and GitHub App secrets are all present before proceeding. |
| **Tip** | Disable during the very first run to reduce friction; enable for all subsequent runs. |

---

### 4️⃣ `bootstrapInfra` — Bootstrap Infrastructure
| | |
|---|---|
| **Type** | Boolean (default: `true`) |
| **When to enable** | After secrets are configured (or already exist). Can also be used standalone to re-provision infrastructure. |
| **What it creates** | Azure Resource Group, App Service Plan, API Web App, UI Web App, Application Insights, Azure SQL Server + Database, Key Vault, and connection string configuration. |
| **Requires** | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` secrets (or `setupOidc` must run in the same workflow execution). |
| **Idempotent** | ✅ Yes — skips resources that already exist. Safe to re-run to add missing pieces. |

---

### 5️⃣ `deployApi` — Deploy API (optional)
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | After infrastructure is bootstrapped and you want to immediately deploy the API application code. |
| **What it does** | Triggers the `deploy-api-to-azure.yml` workflow for the selected environment after bootstrap completes. |

---

### 6️⃣ `deployUi` — Deploy UI (optional)
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | After infrastructure is bootstrapped and you want to immediately deploy the UI application code. |
| **What it does** | Triggers the `deploy-ui-to-azure.yml` workflow for the selected environment after bootstrap completes. |

---

## 🔐 GitHub App Manual Setup (required before first run)

> **This is the only step that cannot be automated.** GitHub requires interactive user authorization to create an app. It takes approximately 5 minutes and only needs to be done once.

### Step 1: Create the GitHub App

1. Go to: https://github.com/settings/apps/new  
   *(or https://github.com/organizations/YOUR-ORG/settings/apps/new for org repos)*
2. Fill in the form:
   - **App name**: `XYDataLabs-OrderProcessing-Automation` (or any name you choose)
   - **Homepage URL**: `https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem`
   - **Webhook**: Uncheck "Active" (not needed)
3. Under **Repository permissions**, set:
   - **Secrets**: `Read and write` ✅ *(critical — without this, secret configuration fails)*
   - **Environments**: `Read and write` ✅ *(required for environment creation)*
   - **Administration**: `Read and write` ✅
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

### Phase 0 — Manual Prerequisite (~5 min, done once)

Complete the [GitHub App Manual Setup](#-github-app-manual-setup-required-before-first-run) above.  
Add `APP_ID` and `APP_PRIVATE_KEY` to repository secrets before proceeding.

---

### Phase 1 — Azure Identity Setup (~3 min)

**Goal**: Create the Microsoft Entra ID App Registration and OIDC federated credentials.

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure parameters:

| Parameter | Value | Reason |
|-----------|-------|--------|
| `environment` | `dev` | Start with dev to validate cheaply |
| `setupOidc` | ✅ `true` | Creates Entra ID app + OIDC credentials |
| `setupGitHubApp` | ❌ `false` | Already done manually in Phase 0 |
| `configureSecrets` | ❌ `false` | Do this in Phase 2 after OIDC succeeds |
| `enableValidation` | ❌ `false` | Skip for first run |
| `bootstrapInfra` | ❌ `false` | Do this in Phase 3 |
| `deployApi` | ❌ `false` | |
| `deployUi` | ❌ `false` | |

4. Click **Run workflow**
5. When the workflow pauses for **device code authentication**:
   - Open https://microsoft.com/devicelogin
   - Enter the code shown in the workflow logs
   - Sign in with your Azure account (must have App Registration permissions)
6. Wait for the job to complete — note the `clientId`, `tenantId`, `subscriptionId` in the summary

**What gets created**: `GitHub-Actions-OIDC` App Registration in Azure, federated credentials for dev branch and dev environment.

---

### Phase 2 — GitHub Secrets Configuration (~1 min)

**Goal**: Write Azure credentials into GitHub repository and environment secrets.

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure parameters:

| Parameter | Value | Reason |
|-----------|-------|--------|
| `environment` | `dev` | |
| `setupOidc` | ❌ `false` | Already done in Phase 1 |
| `setupGitHubApp` | ❌ `false` | Already done manually |
| `configureSecrets` | ✅ `true` | Writes `AZUREAPPSERVICE_*` secrets |
| `enableValidation` | ❌ `false` | |
| `bootstrapInfra` | ❌ `false` | Do this in Phase 3 |
| `deployApi` | ❌ `false` | |
| `deployUi` | ❌ `false` | |

4. Click **Run workflow**

**What gets created**: Repository secrets `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID`, GitHub environment `dev` with matching environment secrets.

> **Tip**: You can combine Phases 1 + 2 in one run by enabling both `setupOidc` and `configureSecrets` together, as long as the GitHub App is already configured (Phase 0 complete).

---

### Phase 3 — Azure Infrastructure Bootstrap (~10 min)

**Goal**: Provision all Azure resources for the dev environment.

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure parameters:

| Parameter | Value | Reason |
|-----------|-------|--------|
| `environment` | `dev` | |
| `setupOidc` | ❌ `false` | Already done |
| `setupGitHubApp` | ❌ `false` | Already done |
| `configureSecrets` | ❌ `false` | Already done |
| `enableValidation` | ✅ `true` | Run validation now that setup is complete |
| `bootstrapInfra` | ✅ `true` | Creates Azure resources |
| `deployApi` | ❌ `false` | Optional: enable if you want to deploy immediately |
| `deployUi` | ❌ `false` | Optional: enable if you want to deploy immediately |

4. Click **Run workflow**

**What gets created**: `rg-orderprocessing-dev` resource group with App Service Plan, API + UI Web Apps, Application Insights, Azure SQL Server & Database, Key Vault.

---

### Phase 4 — Deploy Application (optional, ~5 min each)

After infrastructure is ready, deploy the application code either:
- **Via bootstrap**: Re-run bootstrap with `deployApi = true` and/or `deployUi = true`
- **Via push**: Push to the `dev` branch — deployment workflows trigger automatically
- **Via manual dispatch**: Run `deploy-api-to-azure.yml` or `deploy-ui-to-azure.yml` directly

---

### Combined Single-Run (After Phase 0)

Once the GitHub App is set up (Phase 0), you can complete Phases 1–3 in a single workflow run:

| Parameter | Value |
|-----------|-------|
| `environment` | `dev` |
| `setupOidc` | ✅ `true` |
| `setupGitHubApp` | ❌ `false` |
| `configureSecrets` | ✅ `true` |
| `enableValidation` | ✅ `true` |
| `bootstrapInfra` | ✅ `true` |
| `deployApi` | ❌ `false` (or `true` if ready) |
| `deployUi` | ❌ `false` (or `true` if ready) |

---

## 🔄 Common Scenarios

### Scenario A: Full Dev Setup (first time, all-in-one after GitHub App is configured)
```yaml
environment: dev
setupOidc: true          # 1️⃣ Create Entra ID app + OIDC
setupGitHubApp: false    # 2️⃣ Already done manually
configureSecrets: true   # 3️⃣ Write Azure creds to GitHub secrets
enableValidation: true   # 🔍 Validate everything
bootstrapInfra: true     # 4️⃣ Provision Azure resources
deployApi: false         # 5️⃣ Enable once infra is confirmed healthy
deployUi: false          # 6️⃣ Enable once infra is confirmed healthy
```
**Time**: ~15 min | **Use case**: Complete first-time dev environment

---

### Scenario B: Add Staging (OIDC + secrets already exist)
```yaml
environment: staging      # Switch to staging branch first!
setupOidc: false         # Skip — already done
setupGitHubApp: false    # Skip — already done
configureSecrets: false  # Skip — already done (or re-run with true if you want staging secrets)
enableValidation: true
bootstrapInfra: true     # 4️⃣ Provision staging resources
deployApi: false
deployUi: false
```
**Time**: ~10 min | **Use case**: Add staging after dev is already running

---

### Scenario C: Re-bootstrap Failed/Deleted Infrastructure
```yaml
environment: dev
setupOidc: false         # Skip — credentials still valid
setupGitHubApp: false    # Skip
configureSecrets: false  # Skip — secrets still valid
enableValidation: false  # Skip for speed
bootstrapInfra: true     # 4️⃣ Re-provision
deployApi: false
deployUi: false
```
**Time**: ~10 min | **Use case**: Infrastructure was accidentally deleted; OIDC and secrets are fine

---

### Scenario D: Refresh Secrets Only (after rotating Azure credentials)
```yaml
environment: dev
setupOidc: true          # 1️⃣ Re-create OIDC credentials
setupGitHubApp: false
configureSecrets: true   # 3️⃣ Update GitHub secrets with new values
enableValidation: false
bootstrapInfra: false    # Skip — infra untouched
deployApi: false
deployUi: false
```
**Time**: ~4 min | **Use case**: Azure credentials rotated, GitHub secrets need updating

---

### Scenario E: Bootstrap All Environments at Once
```yaml
environment: all          # Use any branch
setupOidc: true          # Creates credentials for dev + staging + prod
setupGitHubApp: false    # Already done
configureSecrets: true   # Secrets for all three environments
enableValidation: false  # Skip for initial setup
bootstrapInfra: true     # Provisions dev + staging + prod in parallel
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
| GitHub Environments (`settings/environments`) | ✅ Yes | Re-run with `configureSecrets = true` |
| `AZUREAPPSERVICE_*` secrets | ✅ Yes | Re-run with `setupOidc = true` + `configureSecrets = true` |
| `APP_ID` + `APP_PRIVATE_KEY` secrets | ⚠️ Caution | Must redo [GitHub App Manual Setup](#-github-app-manual-setup-required-before-first-run) |
| GitHub App Installation (`settings/installations`) | ⚠️ Caution | Must re-install app + update `APP_ID` + `APP_PRIVATE_KEY` |
| Azure Resource Groups / App Services | ✅ Yes | Re-run with `bootstrapInfra = true` |
| Entra ID App Registration | ✅ Yes | Re-run with `setupOidc = true` |

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
**Fix**: Complete [Phase 0 — GitHub App Manual Setup](#-github-app-manual-setup-required-before-first-run) and add the two secrets before re-running.

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

1. **Do Phase 0 first**: The GitHub App manual setup is the only blocker — complete it before anything else.
2. **Start with `dev`**: Validate the full flow on dev (F1 Free tier, no cost) before extending to staging/prod.
3. **Combine phases**: Once GitHub App is configured, you can run `setupOidc + configureSecrets + bootstrapInfra` all in one workflow execution.
4. **Idempotent**: Every phase is safe to re-run — existing resources are skipped, missing ones are created.
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
