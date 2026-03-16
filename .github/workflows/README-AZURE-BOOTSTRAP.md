# Azure Bootstrap Workflow

Automated orchestration workflow for Azure OIDC setup, GitHub secrets configuration, and infrastructure provisioning.

## 🎯 Purpose

This workflow (`azure-bootstrap.yml`) is the single entry point for all first-time Azure setup. It sequences Phase 0 prerequisites, Phase 1 OIDC and secrets setup, and Phase 2 infrastructure provisioning in the correct dependency order.

> 📖 **Full guide**: See [`Documentation/QUICK-START-AZURE-BOOTSTRAP.md`](../../Documentation/QUICK-START-AZURE-BOOTSTRAP.md) for the complete reference including architecture diagrams, parameter reference, and step-by-step sequences.

---

## ⚠️ Prerequisites (Phase 0 — Manual, One-Time)

> **A GitHub App is required before Phase 1 can succeed.**  
> `GITHUB_TOKEN` does NOT have permission to write repository secrets — this is a GitHub security constraint. Only a GitHub App installation token can write `AZUREAPPSERVICE_*` secrets.

You must complete Phase 0 once before running Phase 1:

1. Create a GitHub App at `https://github.com/settings/apps/new` with these permissions:
   - **Secrets**: Read and write ✅
   - **Environments**: Read and write ✅
   - **Actions**, **Workflows**, **Contents**, **Metadata**: as needed
2. Generate and download the private key (`.pem` file)
3. Install the app on this repository
4. Add two repository secrets: `APP_ID` (numeric app ID) and `APP_PRIVATE_KEY` (full `.pem` contents)

See [Phase 0 in the Quick Start Guide](../../Documentation/QUICK-START-AZURE-BOOTSTRAP.md#-phase-0--manual-prerequisite-github-app-setup) for the complete walkthrough.

> **`APP_INSTALLATION_ID` is not required** — it is auto-discovered at runtime.

---

## 🚀 Quick Start: First-Time Setup

**Step 1 — Complete Phase 0** (see above). Both `APP_ID` and `APP_PRIVATE_KEY` must exist before proceeding.

**Step 2 — Run Phase 1** (one-time, ~4 minutes):

1. Go to **Actions → Azure Bootstrap Setup → Run workflow**
2. Set **"Use workflow from"** to `dev`
3. Configure inputs:

| Input | Value | Notes |
|-------|-------|-------|
| `environment` | `dev` | Start with dev to validate cheaply |
| `setupOidc` | ✅ `true` | Phase 1a — creates Entra ID App Registration |
| `configureSecrets` | ✅ `true` | Phase 1b — writes `AZUREAPPSERVICE_*` to GitHub |
| `bootstrapInfra` | `false` | Do this separately (Phase 2) |
| `enableValidation` | `false` | Skip for first run |
| `setupGitHubApp` | `false` | Already done in Phase 0 |

4. Click **Run workflow**
5. When the `setupOidc` step prompts for device-code authentication:
   - The step will print a code and a URL in the workflow logs (visible in real time)
   - Open https://microsoft.com/devicelogin in your browser
   - Enter the code shown in the logs
   - Sign in with your Azure account (needs App Registration permissions)
   - The step will continue automatically once authentication succeeds

**Step 3 — Run Phase 2** (day-to-day, after Phase 1 succeeds):

| Input | Value |
|-------|-------|
| `setupOidc` | `false` |
| `configureSecrets` | `false` |
| `bootstrapInfra` | ✅ `true` |
| `enableValidation` | ✅ `true` (recommended) |

---

## 📋 Workflow Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | *(required)* | Target: `dev` / `staging` / `prod` / `all`. Branch must match: `dev`→dev, `staging`→staging, `main`→prod. |
| `setupOidc` | boolean | `true` | **Phase 1a** — Creates Microsoft Entra ID App Registration + OIDC federated credentials. First run: device-code login. Re-runs: uses existing `AZUREAPPSERVICE_*` credentials (no interactive prompt). |
| `oidcAppName` | string | `GitHub-Actions-OIDC` | Name of the Azure AD App Registration to create/update. |
| `setupGitHubApp` | boolean | `false` | **Phase 0 helper** — Shows GitHub App setup instructions if `APP_ID`/`APP_PRIVATE_KEY` are missing. Does not create the app. |
| `githubAppName` | string | `XYDataLabsGitHubApp` | Your GitHub App name (used in instructions and validation). |
| `configureSecrets` | boolean | `true` | **Phase 1b** — Writes `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` to GitHub repo + environment secrets. Requires Phase 0 (APP_ID + APP_PRIVATE_KEY) and Phase 1a OIDC outputs. |
| `bootstrapInfra` | boolean | `true` | **Phase 2** — Provisions Resource Group, App Service, SQL, Key Vault. |
| `deployApi` | boolean | `false` | **Phase 2 optional** — Deploys API code after bootstrap. |
| `deployUi` | boolean | `false` | **Phase 2 optional** — Deploys UI code after bootstrap. |
| `enableValidation` | boolean | `false` | **Phase 3** — Activates pre-deployment validation checks in `infra-deploy.yml` for future runs. |

---

## 🔄 Workflow Jobs

### 1. `validate-inputs`
**Runs when**: always (workflow_dispatch only)

- Validates `environment` selection and branch/environment match
- Checks OIDC secrets if `setupOidc=false` (Phase 1a skipped)
- Checks GitHub App credentials if `configureSecrets=true` (Phase 1b)
- Prints a **Phase Readiness Pre-Flight Summary** showing what will run and whether prerequisites are met
- **Fails fast** if OIDC secrets are missing and Phase 1b is requested without Phase 1a

### 2. `setup-oidc` (Phase 1a)
**Runs when**: `setupOidc=true`  
**Needs**: `validate-inputs`

**Authentication (smart, automatic)**:

| Condition | Login method |
|-----------|-------------|
| `AZUREAPPSERVICE_*` secrets **already exist** (re-run) | `azure/login@v2` — non-interactive, passwordless |
| No existing credentials (**first-time**) | `az login --use-device-code` — **user input required** (once only) |

**Actions**:
1. Checks for existing OIDC credentials in the `AZUREAPPSERVICE_*` environment secrets
2. Logs in to Azure (OIDC or device code — see above)
3. Runs `setup-github-oidc.ps1` to create/update the `GitHub-Actions-OIDC` Entra ID App Registration
4. Configures federated credentials for branches (`dev`, `staging`, `main`) and environments (`dev`, `staging`, `prod`)
5. Extracts `clientId`, `tenantId`, `subscriptionId` from Azure
6. Verifies that all federated credentials propagated correctly

**Job Outputs** (passed to Phase 1b):
- `clientId` — Azure AD Application (Client) ID
- `tenantId` — Azure Tenant ID
- `subscriptionId` — Azure Subscription ID
- `appObjectId` — Azure AD App Object ID (for verification)

### 3. `configure-github-secrets` (Phase 1b — calls `configure-github-secrets.yml`)
**Runs when**: `configureSecrets=true` OR `setupGitHubApp=true`, AND `setup-oidc` succeeded or was skipped  
**Needs**: `validate-inputs`, `setup-oidc`

> ⚠️ **Sequential after Phase 1a:** Phase 1b always runs after Phase 1a because it consumes Phase 1a's job outputs (`clientId`, `tenantId`, `subscriptionId`). The two cannot run in parallel.

**Inputs received from `setup-oidc` outputs**:
```yaml
clientId:       ${{ needs.setup-oidc.outputs.clientId }}
tenantId:       ${{ needs.setup-oidc.outputs.tenantId }}
subscriptionId: ${{ needs.setup-oidc.outputs.subscriptionId }}
```

**Actions** (inside `configure-github-secrets.yml`):
1. Validates that either fresh OIDC credentials were passed OR `AZUREAPPSERVICE_*` secrets already exist
2. Generates a short-lived GitHub App installation token from `APP_ID` + `APP_PRIVATE_KEY`
3. Writes `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID` as **repository-level** secrets
4. Creates each GitHub environment (`dev`, `staging`, `prod`) if it does not exist
5. Writes the same three secrets as **environment-level** secrets for each selected environment
6. Reports success/failure per secret

See [`README-CONFIGURE-GITHUB-SECRETS.md`](README-CONFIGURE-GITHUB-SECRETS.md) for full details and the Phase 1 dry-run data flow.

### 4. `pre-validate-prerequisites`
**Runs when**: bootstrap or Phase 2 deploy is requested, after Phase 1b completes  
**Needs**: `validate-inputs`, `setup-oidc`, `configure-github-secrets`

- Checks that `AZUREAPPSERVICE_*` and `APP_ID`/`APP_PRIVATE_KEY` secrets are present
- Fails the job (blocks Phase 2) if OIDC credentials are still missing after Phase 1

### 5. `bootstrap-dev` / `bootstrap-staging` / `bootstrap-prod` (Phase 2)
**Runs when**: `bootstrapInfra=true` AND environment matches  
**Needs**: `pre-validate-prerequisites`

**Azure login (3-step pattern per environment)**:
```
Step 1: Validate that CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID are present
Step 2: azure/login@v2  — passwordless OIDC authentication
Step 3: az account show — verify login succeeded before making changes
```

**Actions**:
- Authenticates to Azure using OIDC (`AZUREAPPSERVICE_*` secrets)
- Runs `bootstrap-enterprise-infra.ps1`
- Creates: Resource Group, App Service Plan, API + UI Web Apps, Application Insights, Azure SQL, Key Vault
- Assigns Contributor RBAC to the OIDC service principal
- Dev, Staging, and Prod jobs run in parallel when `environment=all`

### 6. `enable-validation` (Phase 3)
**Runs when**: `enableValidation=true`, after Phase 2  
**Needs**: `pre-validate-prerequisites`

- Modifies `.github/workflows/infra-deploy.yml` to re-enable the `pre-validate` job
- Commits the change (git push)
- No Azure credentials required — git operation only

### 7. `summary`
**Runs**: always (after all jobs complete)

- Aggregates results from all jobs
- Displays overall status table in the workflow run summary
- Shows success / skipped / failure per phase
   - Click "Add secret"

---

## 🎬 Usage Scenarios

### Scenario 1: Complete First-Time Setup (Phase 0 → Phase 1 → Phase 2)

```
Phase 0  (manual, ~5 min):
  Create GitHub App → Install on repo → Add APP_ID + APP_PRIVATE_KEY

Phase 1  (run workflow once, ~4 min):
  setupOidc=true + configureSecrets=true
  (authenticate via device code when prompted)

Phase 2  (run workflow as needed):
  bootstrapInfra=true (+ deployApi/deployUi as required)
```

### Scenario 2: Bootstrap Only Dev (Validate Cheaply First)

```yaml
environment: dev
setupOidc: true
configureSecrets: true
bootstrapInfra: false   # Add after Phase 1 succeeds
```

### Scenario 3: Add Staging After Dev Is Working

Phase 1 credentials are already stored — only Phase 2 is needed:

```yaml
environment: staging
setupOidc: false        # Already done
configureSecrets: false # Already done
bootstrapInfra: true
enableValidation: true
```

### Scenario 4: Re-run Bootstrap (Fix Issues)

Phase 1 credentials are intact — only re-provision infrastructure:

```yaml
environment: dev
setupOidc: false
configureSecrets: false
bootstrapInfra: true
```

### Scenario 5: Rotate OIDC Credentials

Run Phase 1a + 1b together to refresh credentials:

```yaml
environment: dev
setupOidc: true         # Creates new/updated federated credentials
configureSecrets: true  # Overwrites AZUREAPPSERVICE_* with new values
bootstrapInfra: false
```

---

## 🔍 Monitoring & Troubleshooting

### View Workflow Progress

1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
2. Click on "Azure Bootstrap Setup"
3. Expand each job to see real-time logs

### Common Issues

#### Phase 1b fails: "OIDC secrets are missing and no new credentials were provided"

**Cause**: `configureSecrets=true` but `setupOidc=false` and no `AZUREAPPSERVICE_*` secrets exist yet (first-time setup).

**Fix**: Run both Phase 1a and Phase 1b in the same workflow run:
```
setupOidc=true  +  configureSecrets=true
```

After the first successful run, Phase 1a does not need to be repeated. See [`README-CONFIGURE-GITHUB-SECRETS.md`](README-CONFIGURE-GITHUB-SECRETS.md) for the full dry-run flow.

#### Phase 1b fails: "GitHub App token generation failed"

**Cause**: `APP_ID` or `APP_PRIVATE_KEY` secrets are missing, or the GitHub App is not installed on the repository.

**Fix**:
1. Complete Phase 0 — create and install the GitHub App
2. Add `APP_ID` and `APP_PRIVATE_KEY` to repository secrets
3. Re-run with `setupGitHubApp=true` to validate

> ⚠️ **`GITHUB_TOKEN` cannot write secrets** — a GitHub App installation token is required. `GH_PAT` is not used by this workflow.

#### Phase 1a device-code authentication times out

**Cause**: The 3-minute window for entering the device code expired.

**Fix**: Re-run the workflow and enter the device code at https://microsoft.com/devicelogin within 3 minutes of the code appearing in the logs.

#### AADSTS700016: Application not found

**Cause**: The OIDC federated credential does not match the branch/environment the workflow is running from.

**Fix**: Run Phase 1a with `setupOidc=true` to recreate federated credentials. Ensure the `environment` input and "Use workflow from" branch match.

#### "Resource Group creation timeout"

- Check Azure subscription quotas
- Verify region availability (`centralindia`)
- Re-run workflow after verifying Azure status

### Verify Setup Completion

```bash
# List configured GitHub secrets
gh secret list --repo pavanthakur/XYDataLabs.OrderProcessingSystem

# Verify Azure AD App Registration
az ad app list --display-name "GitHub-Actions-OIDC"

# List federated credentials
az ad app federated-credential list --id <app-object-id>

# List provisioned Azure resource groups
az group list --query "[?starts_with(name, 'rg-orderprocessing')].name"
```

---

## 🔐 Security Considerations

### Authentication Methods

| Phase | Method | Interactive? |
|-------|--------|-------------|
| Phase 1a (first run) | `az login --use-device-code` | ✅ Yes — one-time only |
| Phase 1a (re-run) | `azure/login@v2` (OIDC) | ❌ No — fully automated |
| Phase 1b | GitHub App installation token | ❌ No — auto-generated |
| Phase 2 (bootstrap) | `azure/login@v2` (OIDC) | ❌ No — fully automated |
| Phase 3 (deploy) | `azure/login@v2` (OIDC) | ❌ No — fully automated |

No passwords, PATs, or certificates are stored. Azure authentication uses OIDC token exchange.

### Required Permissions

**Azure AD** (for Phase 1a OIDC setup):
- Application Administrator or Owner
- Permission to create App Registrations and assign RBAC

**Azure Subscription** (for Phase 2 bootstrap):
- Owner or Contributor + User Access Administrator
- Required to create resource groups and assign Contributor RBAC to the OIDC service principal

**GitHub** (for Phase 1b secret writing):
- GitHub App with `Secrets: write` and `Environments: write` permissions
- App must be installed on the repository
- `GITHUB_TOKEN` does **not** have `secrets: write` — a GitHub App token is required

### Secret Scope

Both repository-level and environment-level secrets are configured:

| Scope | Secrets Configured | When Set |
|-------|-------------------|----------|
| Repository | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` | Phase 1b |
| `dev` environment | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` | Phase 1b |
| `staging` environment | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` | Phase 1b |
| `prod` environment | `AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID` | Phase 1b |

All three environments receive the same credentials (they all point to the same Entra ID App Registration). Environment isolation is achieved through OIDC federated credential subjects, not by using different Azure identities.

---

## 📊 Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  User triggers workflow via GitHub UI                               │
│  Selects: environment, setupOidc, configureSecrets, bootstrapInfra  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   validate-inputs    │
                    │  (always runs)       │
                    │  ✓ Branch/env check  │
                    │  ✓ Pre-flight check  │
                    └──────────┬───────────┘
                               │
               ┌───────────────┴───────────────┐
               │ if setupOidc=true             │ if setupGitHubApp or
               ▼                               │ configureSecrets=true
    ┌─────────────────────┐                    ▼
    │   setup-oidc        │         ┌───────────────────────────┐
    │   (Phase 1a)        │────────▶│  configure-github-secrets │
    │   ① Check existing  │ outputs │  (Phase 1b)               │
    │     credentials     │ ──────▶ │  ① Validate prerequisites │
    │   ② Azure login     │ clientId│  ② Generate App token     │
    │     (OIDC or device)│ tenantId│  ③ Set repo secrets       │
    │   ③ Run OIDC script │ subId   │  ④ Create environments    │
    │   ④ Output creds    │         │  ⑤ Set env secrets        │
    └─────────────────────┘         └─────────────┬─────────────┘
                                                  │
                                                  ▼
                                   ┌──────────────────────────┐
                                   │  pre-validate-prereqs    │
                                   │  Checks AZUREAPPSERVICE_*│
                                   │  and APP_ID present      │
                                   └──────────────┬───────────┘
                                                  │
                       ┌──────────────────────────┴──────────────────────────┐
                       │                          │                          │
                       ▼                          ▼                          ▼
            ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
            │  bootstrap-dev   │      │ bootstrap-staging │      │  bootstrap-prod  │
            │  (if selected)   │      │  (if selected)   │      │  (if selected)   │
            │  ① Validate creds│      │  ① Validate creds│      │  ① Validate creds│
            │  ② azure/login   │      │  ② azure/login   │      │  ② azure/login   │
            │  ③ Verify login  │      │  ③ Verify login  │      │  ③ Verify login  │
            │  ④ Run script    │      │  ④ Run script    │      │  ④ Run script    │
            └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘
                     │                         │                         │
                     └─────────────────────────┼─────────────────────────┘
                                               │
                               ┌───────────────┴───────────────┐
                               │                               │
                               ▼                               ▼
                   ┌───────────────────────┐      ┌───────────────────────┐
                   │   enable-validation   │      │       summary         │
                   │   (if enabled)        │      │   (always runs)       │
                   │   Modifies            │      │   Aggregates results  │
                   │   infra-deploy.yml    │      │   Displays status     │
                   └───────────────────────┘      └───────────────────────┘
```

---

## ✅ Success Criteria

After Phase 1 succeeds:

- [ ] `APP_ID` + `APP_PRIVATE_KEY` secrets present (Phase 0)
- [ ] `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID` — repo-level secrets visible at `settings/secrets/actions`
- [ ] Same three secrets present in each GitHub environment (`dev`, `staging`, `prod`)
- [ ] Azure AD App Registration `GitHub-Actions-OIDC` exists with federated credentials for all branches/environments

After Phase 2 succeeds:

- [ ] Resource groups `rg-orderprocessing-dev/staging/prod` created in Azure
- [ ] App Service Plans and Web Apps provisioned
- [ ] Azure SQL Server + Database provisioned
- [ ] Key Vault provisioned
- [ ] Application Insights created
- [ ] RBAC (Contributor) assigned to OIDC service principal

---

## 📚 Related Documentation

| Document | Location |
|----------|----------|
| Full Quick Start Guide | [`Documentation/QUICK-START-AZURE-BOOTSTRAP.md`](../../Documentation/QUICK-START-AZURE-BOOTSTRAP.md) |
| Configure GitHub Secrets | [`README-CONFIGURE-GITHUB-SECRETS.md`](README-CONFIGURE-GITHUB-SECRETS.md) |
| GitHub App Setup (QUICK) | [`Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md`](../../Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md) |
| Azure Deployment Guide | [`Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md`](../../Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md) |
| OIDC Setup Script | `Resources/Azure-Deployment/setup-github-oidc.ps1` |
| Bootstrap Script | `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1` |

---

**Last Updated**: 2026-03-16  
**Workflow Version**: Current (`azure-bootstrap.yml`)  
**Maintainer**: GitHub Copilot
