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
> `GITHUB_TOKEN` does NOT have permission to write repository secrets — only a GitHub App installation token can write `AZUREAPPSERVICE_*` secrets.

1. Create a GitHub App at `https://github.com/settings/apps/new` with these permissions:
   - **Secrets**: Read and write ✅
   - **Environments**: Read and write ✅
   - **Actions**, **Workflows**, **Contents**, **Metadata**: as needed
2. Generate and download the private key (`.pem` file)
3. Install the app on this repository
4. Add two repository secrets: `APP_ID` (numeric app ID) and `APP_PRIVATE_KEY` (full `.pem` contents)

See [QUICK-SETUP-GITHUB-APP.md](../../Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md) for the complete walkthrough.

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
   - Open https://microsoft.com/devicelogin in your browser
   - Enter the code and sign in with your Azure account
   - The step continues automatically once authenticated

After completion, proceed to the **Azure Bootstrap & Deploy** workflow for infrastructure.

---

## 📋 Workflow Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | `all` | Target: `dev` / `staging` / `prod` / `all`. Recommended: `all` to configure all environments in one run. |
| `setupGitHubApp` | boolean | `true` | **Phase 0** — Shows GitHub App setup instructions if `APP_ID`/`APP_PRIVATE_KEY` are missing. Does not create the app. |
| `setupOidc` | boolean | `true` | **Phase 1a** — Creates Microsoft Entra ID App Registration + OIDC federated credentials. First run requires device-code login. |
| `oidcAppName` | string | `GitHub-Actions-OIDC` | Name of the Azure AD App Registration to create/update. |
| `configureSecrets` | boolean | `true` | **Phase 1b** — Writes `AZUREAPPSERVICE_*` secrets to GitHub repo + environment secrets. Requires Phase 0 complete. |
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
| `AZUREAPPSERVICE_*` secrets already exist (re-run) | `azure/login@v2` — non-interactive |
| No existing credentials (first-time) | `az login --use-device-code` — user input required once |

**Actions**:
1. Logs in to Azure (OIDC or device code)
2. Runs `setup-github-oidc.ps1` to create/update the Entra ID App Registration
3. Configures federated credentials for branches (`dev`, `staging`, `main`) and environments (`dev`, `staging`, `prod`)
4. Outputs `clientId`, `tenantId`, `subscriptionId` for Phase 1b

### 3. `configure-github-secrets` (Phase 1b — calls `configure-github-secrets.yml`)
**Runs when**: `configureSecrets=true` AND `setup-oidc` succeeded or was skipped
**Needs**: `validate-inputs`, `setup-oidc`

> **Sequential after Phase 1a:** Consumes Phase 1a's outputs (`clientId`, `tenantId`, `subscriptionId`).

**Actions**:
1. Generates a GitHub App installation token from `APP_ID` + `APP_PRIVATE_KEY`
2. Writes `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID` as repository + environment secrets
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
| [Azure Bootstrap & Deploy](README-AZURE-BOOTSTRAP.md) | Infrastructure provisioning + deployment (Phase 2/X) — run **after** this workflow |
| [Configure GitHub Secrets](README-CONFIGURE-GITHUB-SECRETS.md) | Reusable workflow called by Phase 1b |

---

## 🔍 Troubleshooting

| Symptom | Resolution |
|---------|------------|
| Phase 1a device-code prompt doesn't appear | Check the "Setup Azure OIDC" job logs for the device code URL and code |
| `AADSTS700016` during Phase 1a | App Registration doesn't exist — let Phase 1a create it |
| Phase 1b fails with "APP_ID missing" | Complete Phase 0 first — add `APP_ID` + `APP_PRIVATE_KEY` secrets |
| `APP_INSTALLATION_ID` errors | Not needed — auto-discovered at runtime; remove any manual config |
| Need to re-run for a specific environment | Set `environment` to that env instead of `all` |

See [`TROUBLESHOOTING-INDEX.md`](../../TROUBLESHOOTING-INDEX.md) for comprehensive troubleshooting.
