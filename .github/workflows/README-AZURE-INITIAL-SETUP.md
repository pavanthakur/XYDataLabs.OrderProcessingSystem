# Azure Initial Setup Workflow

One-time setup workflow that configures the GitHub App, Azure OIDC trust, and GitHub environment secrets required before infrastructure can be deployed.

## 🎯 Purpose

This workflow (`azure-initial-setup.yml`) handles all **one-time prerequisite setup** that must complete before the [Azure Bootstrap & Deploy](README-AZURE-BOOTSTRAP.md) workflow can run. It sequences:

- **Phase 0** — GitHub App instructions (manual prerequisite)
- **Phase 1a** — Azure AD App Registration + OIDC federated credentials
- **Phase 1b** — GitHub environment secrets (`AZUREAPPSERVICE_CLIENTID/TENANTID/SUBSCRIPTIONID`)

> **Run this workflow once per repository.** After it completes, use the **Azure Bootstrap & Deploy** workflow for all infrastructure provisioning and deployments.

---

## ⚠️ Prerequisites (Phase 0 — Manual, One-Time)

> **A GitHub App is required before Phase 1b can succeed.**
> `GITHUB_TOKEN` does NOT have permission to write environment secrets — only a GitHub App installation token can write `AZUREAPPSERVICE_*` secrets into the GitHub environments.

1. Create a GitHub App at `https://github.com/settings/apps/new` with these permissions:
   - **Actions**: write ✅
   - **Secrets**: write ✅
   - **Workflows**: write ✅
   - **Environments**: write ✅
   - **Contents**: read ✅
   - **Metadata**: read ✅
2. Generate and download the private key (`.pem` file)
3. Install the app on this repository
4. Add two repository secrets: `APP_ID` (numeric app ID) and `APP_PRIVATE_KEY` (full `.pem` contents)

See [quick-setup-github-app.md](../../docs/guides/configuration/quick-setup-github-app.md) for the complete walkthrough.

> **`APP_INSTALLATION_ID` is not required** — it is auto-discovered at runtime.

---

## 🚀 Quick Start

1. Complete Phase 0 above (one-time manual step)
2. Go to **Actions → Azure Initial Setup → Run workflow**
3. All defaults are correct:
   - **Environment** = `all` (configures dev + staging + prod)
   - **Phase 0**, **Phase 1a**, **Phase 1b** = all enabled
4. Click **Run workflow**
5. When Phase 1a prompts for device-code authentication (first time only):
   - The step prints a code and URL in the workflow logs
   - Open https://login.microsoft.com/device in your browser
   - Enter the code and sign in with your Azure account
   - The step continues automatically once authenticated

> ℹ️ Some Azure CLI versions still show the older alias `https://microsoft.com/devicelogin`. Either URL is valid.

After completion, proceed to the **Azure Bootstrap & Deploy** workflow for infrastructure.

> ⚠️ **Before running Bootstrap**: You must also add the three OpenPay secrets manually to each target **GitHub environment** (`OPENPAY_MERCHANT_ID`, `OPENPAY_PRIVATE_KEY`, `OPENPAY_DEVICE_SESSION_ID`). These are payment credentials that must never pass through workflow inputs. The target bootstrap job will fail immediately with guidance if any are missing.

### Additional Entra Permission For SQL Managed Identity Automation

In some tenants, the existing `GitHub-Actions-OIDC` app registration can authenticate to Azure Resource Manager but still lacks permission to read Microsoft Entra service principal metadata.

That does not break OIDC login itself, but it can break the later SQL managed identity automation during bootstrap or API deployment. The failure usually includes one of these messages:

- `Could not resolve managed identity appId`
- `ERROR: Insufficient privileges to complete the operation.`

If you hit that error later, update the existing `GitHub-Actions-OIDC` app registration in Azure Portal:

1. Go to `Azure Portal -> Microsoft Entra ID -> App registrations`
2. Open `GitHub-Actions-OIDC`
3. Open `API permissions`
4. Click `Add a permission`
5. Choose `Microsoft Graph`
6. Choose `Application permissions`
7. Add `Application.Read.All`
8. Click `Grant admin consent`
9. Wait 1 to 3 minutes for permission propagation
10. Re-run `Azure Bootstrap & Deploy` or `Deploy API to Azure`

If the same error still appears after propagation, add `Directory.Read.All`, grant admin consent, wait briefly, and re-run the workflow.

---

## 📋 Workflow Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | `all` | Target: `dev` / `staging` / `prod` / `all`. Recommended: `all` to configure all environments in one run. |
| `setupGitHubApp` | boolean | `true` | **Phase 0** — Shows GitHub App setup instructions if `APP_ID`/`APP_PRIVATE_KEY` are missing. Does not create the app. |
| `setupOidc` | boolean | `true` | **Phase 1a** — Creates Microsoft Entra ID App Registration + OIDC federated credentials. First run requires device-code login. |
| `oidcAppName` | string | `GitHub-Actions-OIDC` | Name of the Azure AD App Registration to create/update. |
| `configureSecrets` | boolean | `true` | **Phase 1b** — Writes `AZUREAPPSERVICE_*` secrets to GitHub environments. Requires Phase 0 complete. |
| `githubAppName` | string | `XYDataLabsGitHubApp` | Your GitHub App name (used in instructions and validation). |

---

## 🔄 Workflow Jobs

### 1. `validate-inputs`
- Validates selected inputs
- Checks `APP_ID`/`APP_PRIVATE_KEY` when Phase 1b is selected
- Prints Phase Readiness Pre-Flight Summary

### 2. `setup-oidc` (Phase 1a)
**Runs when**: `setupOidc=true`
**Environment**: Always `dev` (hardcoded) — all environments share the same Azure AD App Registration

**Authentication**:

| Condition | Login method |
|-----------|-------------|
| `AZUREAPPSERVICE_*` secrets already exist (re-run) | `azure/login@v3` — non-interactive |
| No existing credentials (first-time) | `az login --use-device-code` — user input required once |

**Actions**:
1. Logs in to Azure (OIDC or device code)
2. Runs `setup-github-oidc.ps1` to create/update the Entra ID App Registration
3. Configures federated credentials from the shared script policy in `Resources/Azure-Deployment/branch-policy.json` (default branches: `dev`, `staging`, `main`; default environments: `dev`, `staging`, `prod`)
4. Outputs `clientId`, `tenantId`, `subscriptionId` for Phase 1b

### 3. `configure-github-secrets` (Phase 1b — calls `configure-github-secrets.yml`)
**Runs when**: `configureSecrets=true` AND `setup-oidc` succeeded or was skipped
**Needs**: `validate-inputs`, `setup-oidc`

> **Sequential after Phase 1a:** Consumes Phase 1a's outputs (`clientId`, `tenantId`, `subscriptionId`).

**Actions**:
1. Generates a GitHub App installation token from `APP_ID` + `APP_PRIVATE_KEY`
2. Writes `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID` as environment secrets for `dev`, `staging`, and `prod`
3. Creates GitHub environments (`dev`, `staging`, `prod`) if they don't exist

### 4. `summary`
**Runs**: always (after all jobs complete)

- Shows Phase 0 status and next steps if `APP_ID`/`APP_PRIVATE_KEY` are missing
- Aggregates results from all jobs
- Points to the **Azure Bootstrap & Deploy** workflow as next step

---

## 🔗 Related Workflows

| Workflow | Purpose |
|----------|---------|
| [Azure Bootstrap & Deploy](README-AZURE-BOOTSTRAP.md) | Infrastructure provisioning + deployment (Phase A/X) — run **after** this workflow |
| [Configure GitHub Secrets](README-CONFIGURE-GITHUB-SECRETS.md) | Reusable workflow called by Phase 1b |

---

## ⚙️ Optional Repository Variables

While here, consider also setting these in **GitHub → Settings → Secrets and variables → Actions → Variables tab → Repository variables**. They are not required for OIDC or deployment to work.

| Variable | Value to set | Effect |
|----------|-------------|--------|
| `ADR_VALIDATION_ENABLED` | `true` | Enables the `Validate ADR Markdown` CI check on push/PR. **Off by default** — job is skipped unless this variable is explicitly `true`. |

> **How to add**: Click **New repository variable**, enter the Name and Value from the table, then click **Add variable**.

---

## 🔍 Troubleshooting

| Symptom | Resolution |
|---------|------------|
| Phase 1a device-code prompt doesn't appear | Check the "Setup Azure OIDC" job logs for the device code URL and code |
| `AADSTS700016` during Phase 1a | App Registration doesn't exist — let Phase 1a create it |
| `Skip output 'clientIdB64' since it may contain secret` warnings | Expected GitHub masking heuristic for encoded cross-job outputs. If Phase 1b succeeds, ignore the warning. |
| Phase 1b fails with "APP_ID missing" | Complete Phase 0 first — add `APP_ID` + `APP_PRIVATE_KEY` secrets |
| `APP_INSTALLATION_ID` errors | Not needed — auto-discovered at runtime; remove any manual config |
| Need to re-run for a specific environment | Set `environment` to that env instead of `all` |

See [`TROUBLESHOOTING-INDEX.md`](../../TROUBLESHOOTING-INDEX.md) for comprehensive troubleshooting.
