# 🚀 Azure Bootstrap - Quick Start Guide

## 🗺️ High-Level Summary

The bootstrap process uses **two GitHub Actions workflows** that together take a brand-new repository from zero to a fully deployed Azure environment:

| Workflow | File | Purpose |
|----------|------|---------|
| **Azure Initial Setup** | `azure-initial-setup.yml` | One-time setup: GitHub App guidance, OIDC identity, GitHub secrets (Phase 0/1a/1b) |
| **Azure Bootstrap & Deploy** | `azure-bootstrap.yml` | Day-to-day: infrastructure provisioning, app deployment, cleanup (Phase 2/X) |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     BOOTSTRAP OVERVIEW                                      │
│                                                                             │
│  ┌── Azure Initial Setup workflow (azure-initial-setup.yml) ────────────┐  │
│  │                                                                      │  │
│  │  PHASE 0 — Manual Prerequisite (~5 min, done ONCE)                   │  │
│  │  └── Create GitHub App → Install on repo → Add APP_ID + KEY         │  │
│  │                                ↓                                     │  │
│  │  PHASE 1 — One-Time Azure Setup (~4 min, done ONCE after Phase 0)   │  │
│  │  ├── setupOidc       → Creates Microsoft Entra ID App Registration   │  │
│  │  │                     + Federated credentials for passwordless auth │  │
│  │  └── configureSecrets → Writes AZUREAPPSERVICE_* to GitHub repo+envs│  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                ↓                                            │
│  ┌── Azure Bootstrap & Deploy workflow (azure-bootstrap.yml) ───────────┐  │
│  │                                                                      │  │
│  │  PHASE 2 — Day-to-Day Operations (run as needed)                     │  │
│  │  ├── bootstrapInfra  → Resource Groups, App Services, SQL, Key Vault │  │
│  │  ├── deployApi       → API code deployed to Azure App Service        │  │
│  │  └── deployUi        → UI code deployed to Azure App Service         │  │
│  │                                                                      │  │
│  │  PHASE X — Cleanup (⚠️ DESTRUCTIVE — deletes everything)             │  │
│  │  └── cleanupInfra    → Deletes App Services, SQL, Key Vault, RG     │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Key rule**: Complete the phases in order. Phase 0 and Phase 1 are each done **once** via **Azure Initial Setup** — after they are complete, day-to-day operations only use Phase 2 via **Azure Bootstrap & Deploy**.

### When do I run each phase?

| Phase | Workflow | When to Run | Parameters |
|-------|----------|-------------|------------|
| **Phase 0** | Azure Initial Setup | Once — before anything else | `setupGitHubApp` (guidance only) |
| **Phase 1** | Azure Initial Setup | Once — after Phase 0 is complete | `setupOidc` + `configureSecrets` |
| **Phase 2** | Azure Bootstrap & Deploy | Any time — infrastructure and deployments | `bootstrapInfra` + `deployApi` / `deployUi` |
| **Phase X** | Azure Bootstrap & Deploy | When tearing down — ⚠️ destructive | `cleanupInfra` |

### What gets created automatically vs. what needs manual work

| Resource | Automated? | Phase | Workflow |
|----------|-----------|-------|----------|
| Microsoft Entra ID App Registration | ✅ Fully automated | Phase 1 (`setupOidc`) | Azure Initial Setup |
| Azure Federated OIDC Credentials | ✅ Fully automated | Phase 1 (`setupOidc`) | Azure Initial Setup |
| GitHub Environments (dev / staging / prod) | ✅ Fully automated | Phase 1 (`configureSecrets`) | Azure Initial Setup |
| GitHub OIDC Secrets (`AZUREAPPSERVICE_*`) | ✅ Fully automated | Phase 1 (`configureSecrets`) | Azure Initial Setup |
| Azure Resource Groups, App Services, SQL | ✅ Fully automated | Phase 2 (`bootstrapInfra`) | Azure Bootstrap & Deploy |
| Deploy API code to Azure App Service | ✅ Fully automated | Phase 2 (`deployApi`) | Azure Bootstrap & Deploy |
| Deploy UI code to Azure App Service | ✅ Fully automated | Phase 2 (`deployUi`) | Azure Bootstrap & Deploy |
| **GitHub App** (`APP_ID` + `APP_PRIVATE_KEY`) | ⚠️ **Manual one-time** | Phase 0 | Azure Initial Setup (guidance) |

---

## 🏗️ Architecture Explained: Two Authentication Systems

> **Read this section if you're confused about why there are two sets of credentials (GitHub App vs. Azure OIDC) and what each one does.**

The bootstrap setup uses **two completely separate authentication systems** that serve entirely different purposes. Mixing them up is the most common source of confusion.

---

### System 1 — GitHub App (`APP_ID` + `APP_PRIVATE_KEY`)

| | |
|---|---|
| **Phase** | Phase 0 prerequisite |
| **What it is** | A GitHub App you create once and install on your repository |
| **Credentials stored** | `APP_ID` + `APP_PRIVATE_KEY` — stored manually as GitHub repository secrets |
| **How it works at runtime** | `actions/create-github-app-token@v3` uses these to generate a **short-lived installation token** (auto-rotated, valid 1 hour) |
| **What it can do** | Write GitHub repository and environment secrets via the GitHub API |
| **What it CANNOT do** | Authenticate to Azure or interact with Azure resources in any way |
| **Used in** | **Phase 1b only** — to call `gh secret set AZUREAPPSERVICE_*` and write Azure credentials into GitHub |
| **NOT used in** | Phase 2 or deploy workflows — those authenticate directly to Azure, not to GitHub |

#### ❓ Why can't `GITHUB_TOKEN` do this?

`GITHUB_TOKEN` is the built-in token every GitHub Actions run gets automatically. It **does not have permission to write repository secrets** — this is a GitHub security design decision. Only a GitHub App installation token (or a PAT with `repo` scope) can call `gh secret set`. A PAT is tied to a user account and expires; a GitHub App is tied to the repository, auto-rotates, and never expires.

---

### System 2 — Azure OIDC (`AZUREAPPSERVICE_CLIENTID` + `TENANTID` + `SUBSCRIPTIONID`)

| | |
|---|---|
| **Phase** | Phase 1a creates, Phase 1b stores, Phase 1a re-run + Phase 2 + Phase X use |
| **What it is** | A Microsoft Entra ID App Registration with federated credentials configured for GitHub Actions |
| **Credentials stored** | `AZUREAPPSERVICE_CLIENTID` + `AZUREAPPSERVICE_TENANTID` + `AZUREAPPSERVICE_SUBSCRIPTIONID` (written automatically by Phase 1b) |
| **How it works at runtime** | `azure/login@v3` exchanges a GitHub-issued JWT for an Azure access token (passwordless, no stored passwords) |
| **What it can do** | Authenticate to Azure and interact with Azure resources (create App Services, deploy code, etc.) |
| **What it CANNOT do** | Write GitHub secrets or interact with the GitHub API |
| **Used in** | Phase 1a (re-runs) + Phase 2 (bootstrap) + Phase X (cleanup) + deploy — **consistent `azure/login@v3` across all Azure-touching jobs** |
| **NOT used in** | Phase 0 or Phase 1b (first time) — those don't interact with Azure resources |

---

### ❓ Why does Phase 1b appear to "depend on" OIDC?

Phase 1b does **NOT authenticate to Azure**. It only needs the OIDC credential **values** (clientId, tenantId, subscriptionId) so it can store them as `AZUREAPPSERVICE_*` GitHub secrets. Those values come from:

- **First run**: Phase 1a outputs them (after logging into Azure and creating the Entra ID App Registration)
- **Re-runs**: Already stored as `AZUREAPPSERVICE_*` secrets from the previous run — Phase 1a can be skipped

So Phase 1b's "OIDC dependency" is simply needing the **values to write** — not actual Azure authentication.

---

### ✅ Azure OIDC Login IS Commonized

The `azure/login@v3` action with the same three credentials (`AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`) is the **consistent, shared Azure authentication mechanism** across all workflow jobs that need to interact with Azure:

| Job | `azure/login@v3` called? | Credentials source |
|-----|------------------------|--------------------|
| `setup-oidc` — re-run | ✅ Yes | Existing `AZUREAPPSERVICE_*` secrets |
| `bootstrap-dev` | ✅ Yes | Phase 1a outputs or existing secrets |
| `bootstrap-staging` | ✅ Yes | Phase 1a outputs or existing secrets |
| `bootstrap-prod` | ✅ Yes | Phase 1a outputs or existing secrets |
| `deploy-api-to-azure` | ✅ Yes | Existing `AZUREAPPSERVICE_*` secrets |
| `deploy-ui-to-azure` | ✅ Yes | Existing `AZUREAPPSERVICE_*` secrets |
| `cleanup-dev/staging/prod` | ✅ Yes | Phase 1a outputs or existing secrets |
| `configure-github-secrets` (Phase 1b) | ❌ No | GitHub App token only |

**Why does `azure/login@v3` appear in multiple jobs instead of once?**  
GitHub Actions jobs run on completely isolated, fresh runners. An Azure login token is not shared between jobs — each job must authenticate independently. This is not duplication by choice; it is required by GitHub Actions' security model.

#### Phase 1a Special Case: First-Time "User Input" Login Path

Phase 1a is the only job with **two different login paths** selected at runtime:

```
IF AZUREAPPSERVICE_* secrets already exist (re-run):
  → azure/login@v3   (same as Phase 2 and Phase X — fully automated, no user input)

IF no existing credentials (first-time setup):
  → az login --use-device-code   ← USER ACTION REQUIRED
    • Workflow prints a device code in the logs
    • User navigates to https://microsoft.com/devicelogin and enters the code
    • Azure returns an access token
    • Token is used to create the Entra ID App Registration
    • clientId / tenantId / subscriptionId are extracted and output to Phase 1b
```

This device-code step is the **only place in the entire workflow where user input generates an Azure token**. It runs exactly once. Every subsequent Azure login (Phase 1a re-runs, Phase 2, Phase X, deploy) is fully automated via OIDC.

#### Standard OIDC Login Pattern in Phase 2 (Bootstrap Jobs)

Each bootstrap job (dev / staging / prod) uses a consistent **3-step Azure login sequence**:

```
Step 1: Validate Azure Credentials
        → Checks that CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID are present
        → Fails fast with a clear error if any are missing
        → Source: Phase 1a outputs || AZUREAPPSERVICE_* secrets

Step 2: Azure Login (OIDC or Secrets)
        → uses: azure/login@v3
        → Exchanges GitHub OIDC JWT for an Azure access token
        → Passwordless — no stored passwords, no manual input

Step 3: Verify Azure Login
        → Runs: az account show
        → Confirms the login succeeded and prints subscription details
        → Fails the job before any infrastructure changes if login is bad
```

The three steps are repeated per-environment job (dev, staging, prod) because each job runs on an independent runner.

#### Login Pattern in Phase X (Cleanup Jobs)

Each cleanup job (dev, staging, prod) uses the same **3-step Azure login sequence** as bootstrap, then proceeds to delete resources.

#### Login Pattern in Deploy Workflows

The deploy workflows (`deploy-api-to-azure.yml`, `deploy-ui-to-azure.yml`) use a **2-step pattern** with conditional gating:

```
Step 1: Check Azure Credentials
        → Validates that AZUREAPPSERVICE_* secrets are present
        → Sets credentialsConfigured=true/false output
        → If credentials are missing: prints fix instructions, exits gracefully (no failure)

Step 2: Login to Azure
        → uses: azure/login@v3 (only if credentialsConfigured == 'true')
        → All subsequent steps are also gated on credentialsConfigured == 'true'
        → Missing credentials = graceful skip, not failure (deploy is optional until infra exists)
```

---

### Complete Token Flow (All Phases)

```
Phase 0:  ──── (Manual, one-time) ───────────────────────────────────────────
           User creates GitHub App + stores APP_ID + APP_PRIVATE_KEY
           in GitHub repository secrets.

Phase 1a: ──── Azure login (conditional) ────────────────────────────────────
           ┌─ FIRST RUN (no stored OIDC credentials):
           │    az login --use-device-code  ← USER INPUT REQUIRED (once only)
           │    → Azure returns access token from user's credentials
           └─ RE-RUN (AZUREAPPSERVICE_* already exist):
                azure/login@v3              ← AUTOMATED, same as Phase 2/3
           → setup-github-oidc.ps1 creates/updates Entra ID App Registration
           OUTPUT: clientId, tenantId, subscriptionId

Phase 1b: ──── GitHub App token ─────────────────────────────────────────────
           APP_ID + APP_PRIVATE_KEY
             → actions/create-github-app-token@v3 → short-lived GitHub token
             → gh secret set AZUREAPPSERVICE_CLIENTID  ← stores Phase 1a output
             → gh secret set AZUREAPPSERVICE_TENANTID  ← stores Phase 1a output
             → gh secret set AZUREAPPSERVICE_SUBSCRIPTIONID ← stores Phase 1a output
           ❌ Does NOT talk to Azure at all.

Phase 2:  ──── Azure OIDC (3-step pattern, per-environment job) ─────────────
           AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID
             Step 1: Validate credentials present (fast-fail pre-check)
             Step 2: azure/login@v3 → Authenticate to Azure (passwordless)
             Step 3: az account show → Verify login succeeded
             → Provision: Resource Groups, App Services, SQL, Key Vault
           ❌ Does NOT use GitHub App token at all.

Phase X:  ──── Azure OIDC (3-step pattern, per-environment job) ─────────────
(cleanup) AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID
             Step 1: Validate credentials present (fast-fail pre-check)
             Step 2: azure/login@v3 → Authenticate to Azure (passwordless)
             Step 3: az account show → Verify login succeeded
             → Delete: App Services (stop+delete UI, stop+delete API) → Resource Group
           ❌ Does NOT use GitHub App token at all.

Deploy:   ──── Azure OIDC (2-step pattern + conditional gating) ─────────────
          AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID
             Step 1: Check credentials → set credentialsConfigured=true/false
             Step 2: azure/login@v3 (only if credentialsConfigured == 'true')
             → Deploy API and UI to Azure App Service
           ❌ Does NOT use GitHub App token at all.
```

### Summary Table

| Phase / Job | Uses GitHub App Token? | Azure OIDC login? | Login path | Purpose |
|-------------|----------------------|-------------------|------------|---------|
| Phase 0 | N/A — creates the app | ❌ No | — | Create GitHub App + store APP_ID/APP_PRIVATE_KEY |
| **Phase 1a** (first time) | ❌ No | ❌ No — device code instead | `az login --use-device-code` ← **user input** | Create Entra ID App Registration |
| **Phase 1a** (re-run) | ❌ No | ✅ `azure/login@v3` | Automated OIDC (same as Phase 2) | Re-run/update Entra ID App Registration |
| **Phase 1b** | ✅ Yes — writes GitHub secrets | ❌ **No Azure login at all** | GitHub App token only | Store `AZUREAPPSERVICE_*` secrets in GitHub |
| Phase 2 (bootstrap) | ❌ No | ✅ `azure/login@v3` | 3-step: Validate → Login → Verify | Provision Azure infrastructure |
| **Phase X (cleanup)** | ❌ No | ✅ `azure/login@v3` | 3-step: Validate → Login → Verify | ⚠️ Delete all Azure resources |
| Deploy (API/UI) | ❌ No | ✅ `azure/login@v3` | 2-step + conditional gate | Deploy applications to Azure |

---

## 📋 Workflow Parameter Reference

Parameters are split across **two workflows**. Use the workflow that matches the phase you are running.

---

## 📋 Parameters — Azure Initial Setup (`azure-initial-setup.yml`)

Navigate to: **GitHub → Actions → Azure Initial Setup → Run workflow**

> Phase 0/1a/1b parameters. The Initial Setup workflow does **not** enforce branch–environment matching — you can run it from any branch.

---

### 🎯 `environment` — Target Environment *(always required)*
| | |
|---|---|
| **Type** | Choice: `dev` / `staging` / `prod` / `all` |
| **Required** | Yes — every run |
| **Description** | Which Azure environment to configure. `all` configures dev, staging, and prod. |
| **Branch rule** | **No branch restriction.** The Initial Setup workflow does not enforce branch–environment matching because Phase 0/1a/1b only configure credentials, not deploy code. Recommended: `branch=dev`, `environment=all`. |
| **Example** | Start with `dev` to validate the setup cheaply before committing to staging/prod. |

---

## 🔑 Phase 1 Parameters — One-Time Setup
> Enable these **once** when setting up a new environment. After Phase 1 is complete, you will not need to run these again unless credentials are lost or rotated.

> ⚠️ **Phase 1a and 1b always run in `dev` environment context** (hardcoded) because all environments share the same Azure AD App Registration. The Initial Setup workflow does not enforce branch–environment matching, so you can run Phase 1 from any branch. Recommended: `branch=dev`, `environment=all`.

> ⚠️ **Phase 1a → Phase 1b must run sequentially (not in parallel).** `configureSecrets` (Phase 1b) uses the OIDC outputs (`clientId`, `tenantId`, `subscriptionId`) produced by `setupOidc` (Phase 1a), so the two steps cannot run concurrently. The workflow dependency chain enforces this order automatically.

### `setupOidc` — Setup Azure OIDC *(Phase 1a)*
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **Phase** | 🔑 Phase 1a — one-time setup |
| **When to enable** | **First time only.** Also re-run if federated credentials are corrupted or deleted. |
| **What it does** | Logs in to Azure via interactive device code, then creates (or updates) the **`GitHub-Actions-OIDC`** App Registration in Microsoft Entra ID. Creates a Service Principal and configures federated credentials so GitHub Actions can authenticate to Azure without passwords. |
| **Output** | `clientId`, `tenantId`, `subscriptionId` — passed automatically to `configureSecrets` (Phase 1b). |
| **Requires** | Azure account with permission to create App Registrations (Application Administrator or Owner). |
| **Skip when** | Secrets `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` already exist and are valid. |
| **Idempotent** | ✅ Yes — re-running adds missing federated credentials without removing existing ones. |

### `oidcAppName` — OIDC App Name *(advanced, optional)*
| | |
|---|---|
| **Type** | String (default: `GitHub-Actions-OIDC`) |
| **Phase** | 🔑 Phase 1a — used only when `setupOidc = true` |
| **When to change** | Only if you need a custom name for the Entra ID App Registration. Leave blank for the default. |

### `configureSecrets` — Configure GitHub Secrets *(Phase 1b)*
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **Phase** | 🔑 Phase 1b — one-time setup (sequential after Phase 1a) |
| **When to enable** | After `setupOidc` (Phase 1a) has run (or OIDC credentials already exist) **and** the GitHub App is installed with `APP_ID` + `APP_PRIVATE_KEY` secrets present. |
| **What it does** | Uses the GitHub App token to write `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, and `AZUREAPPSERVICE_SUBSCRIPTIONID` as both repository secrets and per-environment secrets (auto-creates the GitHub environments if missing). |
| **Prerequisite** | `APP_ID` and `APP_PRIVATE_KEY` repository secrets **must already exist**. See [Phase 0 Setup](#phase-0-manual-prerequisite-5-min-done-once) below. |
| **Idempotent** | ✅ Yes — overwrites existing secrets with current values. |

> 💡 **Tip**: Run `setupOidc` and `configureSecrets` **together in a single Azure Initial Setup workflow run** — they are designed to chain: OIDC outputs from Phase 1a feed directly into Phase 1b secret configuration. They always run sequentially (1a first, then 1b).

---

## 📋 Parameters — Azure Bootstrap & Deploy (`azure-bootstrap.yml`)

Navigate to: **GitHub → Actions → Azure Bootstrap & Deploy → Run workflow**

> Phase 2/X parameters. This workflow **enforces branch–environment matching**: the **“Use workflow from”** branch must match the environment (`dev`→`dev`, `staging`→`staging`, `main`→`prod`). Use any branch for `environment: all`.

> Azure deployment scripts use the same default mapping from `Resources/Azure-Deployment/branch-policy.json`. Keep the workflow rules and that shared policy file aligned if branch governance changes.

### 🎯 `environment` — Target Environment *(always required)*
| | |
|---|---|
| **Type** | Choice: `dev` / `staging` / `prod` / `all` |
| **Required** | Yes — every run |
| **Description** | Which Azure environment to provision. `all` provisions dev, staging, and prod in parallel. |
| **Branch rule** | The **“Use workflow from”** branch must match the environment: `dev`→`dev`, `staging`→`staging`, `main`→`prod`. Use any branch for `all`. |

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

## 🗑️ Phase X Parameter — Cleanup (⚠️ Destructive)

### `cleanupInfra` — Cleanup Azure Infrastructure *(Phase X)*
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **Phase** | 🗑️ Phase X — ⚠️ **DESTRUCTIVE** |
| **When to enable** | Only when you want to **permanently delete** all Azure resources for the selected environment(s). |
| **What it does** | Stops and deletes UI and API App Services (blocking), then deletes the entire Resource Group with `--no-wait` (fire-and-forget). |
| **Requires** | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` secrets (from Phase 1). |
| **⚠️ WARNING** | This action is **irreversible**. All resources in the environment's Resource Group will be destroyed. Re-run Phase 2 (`bootstrapInfra`) to recreate them. |
| **Idempotent** | ✅ Yes — safe to re-run if cleanup failed partway through. |

---

## ℹ️ Phase 0 Helper Parameter

> These parameters are part of the **Azure Initial Setup** workflow (`azure-initial-setup.yml`).

### `setupGitHubApp` — GitHub App Instructions
| | |
|---|---|
| **Type** | Boolean (default: `false`) |
| **When to enable** | Enable if `APP_ID` or `APP_PRIVATE_KEY` secrets are missing and you need step-by-step guidance. |
| **What it does** | Checks whether `APP_ID` and `APP_PRIVATE_KEY` secrets already exist and prints setup instructions if they are missing. **It does not create the app.** |
| **Why not automated?** | GitHub's security model requires interactive user approval to create an OAuth/GitHub App. This is by design and cannot be bypassed. |
| **⚠️ Action required** | See [Phase 0 Setup](#phase-0-manual-prerequisite-5-min-done-once) below — this one-time manual step must be completed **before** Phase 1 can succeed. |

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

Complete the [GitHub App setup](#phase-0-manual-prerequisite-github-app-setup) above.  
Add `APP_ID` and `APP_PRIVATE_KEY` to repository secrets before proceeding.

✅ **Done when**: Both `APP_ID` and `APP_PRIVATE_KEY` secrets exist at `settings/secrets/actions`.  
🚫 **Do not proceed to Phase 1 until Phase 0 is complete.**

---

### Phase 1 — One-Time Azure Setup (~4 min, done once after Phase 0)

**Goal**: Create the Azure OIDC identity and push credentials into GitHub. This runs **once per environment** — after this, you never need to run `setupOidc` or `configureSecrets` again unless credentials are rotated or lost.

1. Go to **Actions → Azure Initial Setup → Run workflow**
2. Set **"Use workflow from"** to `dev` (any branch works — Initial Setup does not enforce branch matching)
3. Configure parameters — check **only** the Phase 1 boxes:

| Parameter | Value | Notes |
|-----------|-------|-------|
| `environment` | `dev` | Start with dev to validate cheaply |
| `setupOidc` ✅ | `true` | 🔑 Phase 1 — creates Entra ID app + OIDC credentials |
| `oidcAppName` | *(default)* | Leave blank (uses `GitHub-Actions-OIDC`) |
| `setupGitHubApp` | `false` | Already done in Phase 0 |
| `configureSecrets` ✅ | `true` | 🔑 Phase 1 — writes `AZUREAPPSERVICE_*` secrets to GitHub |

4. Click **Run workflow**
5. When the `setupOidc` step prompts for **device code authentication**:
   - The step prints a code and URL in the workflow logs (visible in real time)
   - Open https://microsoft.com/devicelogin in your browser
   - Enter the code shown in the workflow logs
   - Sign in with your Azure account (must have App Registration permissions)
   - The step continues automatically once authentication completes
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

1. Go to **Actions → Azure Bootstrap & Deploy → Run workflow**
2. Set **“Use workflow from”** to `dev` (must match environment)
3. Configure parameters — check **only** the Phase 2 boxes:

| Parameter | Value | Notes |
|-----------|-------|-------|
| `environment` | `dev` | |
| `bootstrapInfra` ✅ | `true` | 🔄 Phase 2 — creates/updates Azure resources |
| `deployApi` | `false` (or `true`) | 🔄 Phase 2 — enable to deploy API code immediately |
| `deployUi` | `false` (or `true`) | 🔄 Phase 2 — enable to deploy UI code immediately |
| `cleanupInfra` | `false` | 🗑️ Phase X — not tearing down |

4. Click **Run workflow**

**What gets created**: `rg-orderprocessing-dev` resource group with App Service Plan, API + UI Web Apps, Application Insights, Azure SQL Server & Database, Key Vault.

> 💡 **Re-running Phase 2 is safe**: Every resource is idempotent — existing resources are skipped, missing ones are created. Run it any time infrastructure needs to be refreshed.

---

### Phase 2 — Deploying Application Code

After infrastructure is ready, deploy application code:
- **Via Azure Bootstrap & Deploy**: Run workflow with `deployApi = true` and/or `deployUi = true`
- **Via push**: Push to the `dev` branch — deployment workflows trigger automatically
- **Via manual dispatch**: Run `deploy-api-to-azure.yml` or `deploy-ui-to-azure.yml` directly

---

### Quick Reference: What to check for each run

| Goal | Workflow | Key Parameters |
|------|----------|---------|
| First-time full setup (Phase 1 + 2) | **Azure Initial Setup** then **Azure Bootstrap & Deploy** | `setupOidc` + `configureSecrets` → then `bootstrapInfra` |
| Phase 1 only (OIDC + secrets) | **Azure Initial Setup** | `setupOidc` + `configureSecrets` |
| Phase 2 only (infra + deploy) | **Azure Bootstrap & Deploy** | `bootstrapInfra` + optional `deployApi` / `deployUi` |
| Redeploy code only | **Azure Bootstrap & Deploy** | `deployApi` + `deployUi` |
| Rotate credentials | **Azure Initial Setup** | `setupOidc` + `configureSecrets` |
| Tear down environment | **Azure Bootstrap & Deploy** | `cleanupInfra` |

---

## 🔄 Common Scenarios

### Scenario A: Brand-New Dev Environment (Phase 0 already done)

**Run 1 — Azure Initial Setup** (`azure-initial-setup.yml`):
```yaml
# Phase 1 (one-time) — create OIDC identity and push credentials
environment: dev
setupOidc: true          # 🔑 Phase 1 — Create Entra ID app + OIDC
oidcAppName: ""          # Use default (GitHub-Actions-OIDC)
setupGitHubApp: false    # Phase 0 done — skip
configureSecrets: true   # 🔑 Phase 1 — Write Azure creds to GitHub secrets
```

**Run 2 — Azure Bootstrap & Deploy** (`azure-bootstrap.yml`):
```yaml
# Phase 2 — provision infrastructure (after Initial Setup completes)
environment: dev
bootstrapInfra: true     # 🔄 Phase 2 — Provision Azure resources
deployApi: false         # 🔄 Phase 2 — Enable once infra is confirmed healthy
deployUi: false          # 🔄 Phase 2 — Enable once infra is confirmed healthy
cleanupInfra: false      # 🗑️ Phase X — Not tearing down
```
**Time**: ~15 min total (two runs) | **Use case**: Complete first-time dev environment setup

---

### Scenario B: Add Staging (Phase 1 already done for dev)

**Azure Bootstrap & Deploy** (`azure-bootstrap.yml`):
```yaml
# Phase 2 only — OIDC and secrets already exist from dev setup
environment: staging      # Use workflow from staging branch!
bootstrapInfra: true     # 🔄 Phase 2 — Provision staging resources
deployApi: false
deployUi: false
cleanupInfra: false
```
**Time**: ~10 min | **Use case**: Add staging after dev is already running

---

### Scenario C: Re-provision Infrastructure (Phase 1 already done)

**Azure Bootstrap & Deploy** (`azure-bootstrap.yml`):
```yaml
# Phase 2 only — credentials are fine, just re-create Azure resources
environment: dev
bootstrapInfra: true     # 🔄 Phase 2 — Re-provision Azure resources
deployApi: false
deployUi: false
cleanupInfra: false
```
**Time**: ~10 min | **Use case**: Infrastructure was accidentally deleted; OIDC and secrets are intact

---

### Scenario D: Rotate Azure Credentials

**Azure Initial Setup** (`azure-initial-setup.yml`):
```yaml
# Re-run Phase 1 to refresh credentials and secrets
environment: dev
setupOidc: true          # 🔑 Phase 1 — Re-create OIDC credentials
oidcAppName: ""          # Use default unless your app uses a custom name
setupGitHubApp: false
configureSecrets: true   # 🔑 Phase 1 — Update GitHub secrets with new values
```
**Time**: ~4 min | **Use case**: Azure credentials rotated; GitHub secrets need updating

---

### Scenario E: Bootstrap All Environments at Once

**Run 1 — Azure Initial Setup** (`azure-initial-setup.yml`):
```yaml
# Phase 1 for all environments
environment: all          # Use any branch
setupOidc: true          # 🔑 Phase 1 — Creates credentials for dev + staging + prod
oidcAppName: ""          # Use default unless using a custom Entra app name
setupGitHubApp: false    # Phase 0 already done
configureSecrets: true   # 🔑 Phase 1 — Secrets for all three environments
```

**Run 2 — Azure Bootstrap & Deploy** (`azure-bootstrap.yml`):
```yaml
# Phase 2 for all environments (after Initial Setup completes)
environment: all          # Use any branch
bootstrapInfra: true     # 🔄 Phase 2 — Provisions dev + staging + prod in parallel
deployApi: false
deployUi: false
cleanupInfra: false
```
**Time**: ~15 min total (two runs) | **Use case**: Full environment fleet setup

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
| `APP_ID` + `APP_PRIVATE_KEY` secrets | ⚠️ Caution | Must redo [Phase 0 Setup](#phase-0-manual-prerequisite-github-app-setup) |
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
**Fix**: Complete [Phase 0 — GitHub App Setup](#phase-0-manual-prerequisite-github-app-setup) and add the two secrets before re-running.

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
**Cause**: "Use workflow from" branch does not match the target environment in **Azure Bootstrap & Deploy**.  
**Fix**: Match the branch to the environment: `dev` branch → `dev` env, `main` branch → `prod` env. Use any branch only for `environment: all`. Note: **Azure Initial Setup** does not enforce branch matching.

---

## 🚀 Next Steps After Bootstrap

1. **Verify live endpoints**
   - Dev API: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
   - Dev UI: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

2. **Enable continuous deployment**  
   Push to `dev` → auto-deploys to dev environment.  
   Push to `main` → auto-deploys to prod environment.

3. **Add Application Insights telemetry**  
  Follow: `docs/guides/configuration/app-insights-automated-setup.md`

---

## 📚 Related Documentation

| Document | Purpose |
|----------|---------|
| `docs/guides/deployment/azure-deployment-guide.md` | Detailed end-to-end automation guide |
| `docs/guides/configuration/workflow-automation-visual-guide.md` | GitHub workflow automation reference |
| `docs/guides/configuration/quick-setup-github-app.md` | GitHub App quick setup |
| `.github/workflows/README.md` | Bootstrap script and workflow parameter reference |
| `Resources/Azure-Deployment/setup-github-oidc.ps1` | OIDC setup script |
| `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1` | Infrastructure bootstrap script |

---

## 💡 Pro Tips

1. **Phase 0 is a true one-time step**: Once the GitHub App is created, installed, and its secrets are in place, you never touch Phase 0 again.
2. **Phase 1 is also one-time per environment**: Run `setupOidc + configureSecrets` via **Azure Initial Setup** once, then only use **Azure Bootstrap & Deploy** for all ongoing work.
3. **Phase 2 is idempotent**: Every `bootstrapInfra` run is safe to re-run — existing resources are skipped, missing ones are created. Run it whenever needed.
4. **Start with `dev`**: Validate the full flow on dev (F1 Free tier, no cost) before extending to staging/prod.
5. **Use `all`**: Select `environment: all` to provision dev/staging/prod simultaneously once you're confident.
6. **Save the `.pem` file**: Store the GitHub App private key securely offline — if lost, generate a new one in app settings and update `APP_PRIVATE_KEY`.
7. **Two workflows, clear separation**: Phase 0/1 (credentials) → **Azure Initial Setup**. Phase 2/X (infrastructure) → **Azure Bootstrap & Deploy**. Never mix them up.

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

👉 **Azure Initial Setup** (Phase 0/1): https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-initial-setup.yml

👉 **Azure Bootstrap & Deploy** (Phase 2/X): https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

Then click **"Run workflow"** (top-right green button)
