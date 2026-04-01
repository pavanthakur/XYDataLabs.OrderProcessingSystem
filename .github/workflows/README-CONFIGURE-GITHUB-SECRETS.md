# Configure GitHub Secrets Workflow

## Overview

This workflow handles GitHub App setup and secret configuration. It was separated from the main bootstrap workflow to improve modularity, readability, and independent execution tracking.

## 🔑 Key Concept: Two Authentication Systems

This workflow is the intersection of two completely independent authentication systems. Understanding the difference is essential for troubleshooting.

### GitHub App Token — writes GitHub secrets

The GitHub App (`APP_ID` + `APP_PRIVATE_KEY`) is used **only to write `AZUREAPPSERVICE_*` secrets into GitHub**. 

- `GITHUB_TOKEN` (the built-in workflow token) does **not** have permission to write repository secrets — this is a GitHub security constraint.
- A GitHub App installation token (generated from `APP_ID` + `APP_PRIVATE_KEY`) **does** have `Secrets: write` permission.
- The token is short-lived (1 hour), auto-rotates, and never expires like a PAT would.
- **The GitHub App token never touches Azure.** It is purely a GitHub API credential.

### Azure OIDC — authenticates to Azure

The `AZUREAPPSERVICE_*` secrets (`CLIENTID`, `TENANTID`, `SUBSCRIPTIONID`) are the output of Phase 1a. They represent an Azure identity (Entra ID App Registration with federated credentials).

- **This workflow (Phase 1b) does NOT use these to authenticate to Azure.** It only stores their values as GitHub secrets.
- Phase A (bootstrap infra) and Deploy workflows use `azure/login@v3` with these secrets to authenticate to Azure.

### Why Phase 1b "depends on" OIDC credentials

Phase 1b needs the OIDC credential **values** to store them — not to authenticate with them. Those values come from:
- **First run**: Phase 1a outputs `clientId`/`tenantId`/`subscriptionId` and passes them to this workflow.
- **Re-runs**: The `AZUREAPPSERVICE_*` secrets already exist in GitHub from a previous Phase 1b run. This workflow writes them again if new values are passed.

### How `azure/login@v3` is shared across phases

`azure/login@v3` is the **single, consistent Azure authentication action** used by every workflow job that needs to interact with Azure:

| Job | Uses `azure/login@v3`? | Notes |
|-----|------------------------|-------|
| **Phase 1b (this workflow)** | ❌ No | GitHub App token only |
| Phase 1a (re-run) | ✅ Yes | Same credentials as Phase A |
| Phase A (bootstrap-dev/staging/prod) | ✅ Yes | 3-step pattern: Validate → Login → Verify |
| Deploy (deploy-api/ui) | ✅ Yes | 2-step pattern: Check → Login (conditional) |

Each job calls `azure/login@v3` independently because GitHub Actions jobs run on isolated runners and cannot share login state.

The **only** place where a human enters credentials to generate an Azure token is Phase 1a's first-time device-code step. All other Azure logins (Phase 1a re-run, Phase A, Deploy workflows) are fully automated using the stored OIDC credentials.

## Purpose

Automates:
- GitHub App setup guidance and validation
- Repository secret configuration (Azure OIDC credentials: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`)
- Environment secret configuration (dev, staging, prod)
- Configuration validation

> **Scope**: This workflow configures OIDC credentials and the `OIDC_SP_OBJECT_ID` secret only. It does **not** set OpenPay secrets. OpenPay secrets (`OPENPAY_MERCHANT_ID`, `OPENPAY_PRIVATE_KEY`, `OPENPAY_DEVICE_SESSION_ID`) must be added manually in GitHub Settings → Secrets → Actions — workflow inputs are not a secure channel for credentials (they appear in plain text in workflow logs).

## Triggers

### Manual Execution (workflow_dispatch)

```yaml
Actions → Configure GitHub Secrets → Run workflow

Inputs:
  - environment: dev/staging/prod/all
  - setupGitHubApp: true/false
  - configureSecrets: true/false
  - clientId: Azure OIDC Client ID (optional)
  - tenantId: Azure OIDC Tenant ID (optional)
  - subscriptionId: Azure OIDC Subscription ID (optional)
```

**When to use manually:**
- Troubleshoot secret configuration issues
- Reconfigure secrets for specific environments
- Validate GitHub App setup independently
- Update secrets after OIDC changes

### Automated Execution (workflow_call)

Called by `azure-initial-setup.yml` after OIDC setup (Phase 1a → Phase 1b):

The caller passes base64-encoded values to avoid GitHub dropping cross-job outputs that resemble secrets.

```yaml
configure-github-secrets:
  uses: ./.github/workflows/configure-github-secrets.yml
  with:
    environment: ${{ inputs.environment }}
    setupGitHubApp: ${{ inputs.setupGitHubApp }}
    configureSecrets: ${{ inputs.configureSecrets }}
    clientIdB64: ${{ needs.setup-oidc.outputs.clientIdB64 }}
    tenantIdB64: ${{ needs.setup-oidc.outputs.tenantIdB64 }}
    subscriptionIdB64: ${{ needs.setup-oidc.outputs.subscriptionIdB64 }}
```

## Workflow Jobs

### 1. validate-inputs
Logs workflow start and validates input parameters.

**Outputs:**
- Workflow context (timestamp, branch, repository, actor)
- Selected parameters

### 2. setup-github-app
Provides GitHub App setup guidance and validates existing configuration.

**Conditions:**
- Runs if `setupGitHubApp` input is true
- Checks for existing APP_ID and APP_PRIVATE_KEY secrets

**Actions:**
- Checks current GitHub App configuration
- Provides setup instructions if not configured
- Links to automation scripts and documentation

**When to enable:**
- First-time GitHub App setup
- After deleting/recreating GitHub App
- When APP_ID or APP_PRIVATE_KEY secrets are missing

### 3. configure-secrets
Configures repository and environment secrets using GitHub App authentication.

**Prerequisites:**
- GitHub App must be configured (APP_ID and APP_PRIVATE_KEY secrets)
- Azure OIDC credentials must be provided (via inputs)

**Configures:**
- **Repository secrets:**
  - AZUREAPPSERVICE_CLIENTID
  - AZUREAPPSERVICE_TENANTID
  - AZUREAPPSERVICE_SUBSCRIPTIONID

- **Environment secrets** (per environment):
  - AZUREAPPSERVICE_CLIENTID
  - AZUREAPPSERVICE_TENANTID
  - AZUREAPPSERVICE_SUBSCRIPTIONID

**Conditions:**
- Runs if `configureSecrets` input is true
- Requires successful GitHub App token generation

**Actions:**
- Validates OIDC credentials are provided
- Generates GitHub App installation token
- Sets repository-level secrets
- Creates environments if they don't exist
- Sets environment-specific secrets
- Reports success/failure for each secret

### 4. validate-configuration
Validates the completed configuration.

**Actions:**
- Checks GitHub App setup status
- Checks secret configuration status
- Displays configured environments
- Provides validation tool references
- Creates comprehensive summary

**Outputs:**
- Configuration status summary
- Links to validation tools
- Documentation references

## Workflow Outputs

Available to calling workflows:

```yaml
outputs:
  setup-result: # Result of GitHub App setup (success/skipped/failure)
  secrets-result: # Result of secrets configuration (success/failure)
  validation-result: # Result of validation (success/failure)
```

## Required Secrets

### Repository Secrets
- `APP_ID`: GitHub App ID
- `APP_PRIVATE_KEY`: GitHub App private key (PEM format)

### Automatically Configured
- `AZUREAPPSERVICE_CLIENTID`: Azure OIDC Client ID
- `AZUREAPPSERVICE_TENANTID`: Azure Tenant ID
- `AZUREAPPSERVICE_SUBSCRIPTIONID`: Azure Subscription ID

## Environment Configuration

Supports three environments, each with isolated secrets:
- **dev**: Development environment
- **staging**: Staging/pre-production environment
- **prod**: Production environment

When `environment: all` is selected:
- All three environments are configured
- Environments are created if they don't exist
- Each environment gets its own set of secrets

## Integration with Azure Initial Setup Workflow

### Flow in azure-initial-setup.yml

```
1. validate-inputs
2. setup-oidc (Phase 1a)
   ├── Creates Azure OIDC app
   └── Outputs: clientId, tenantId, subscriptionId
3. configure-github-secrets (Phase 1b) ← THIS WORKFLOW
   ├── Receives OIDC outputs
   ├── Configures GitHub App (if needed)
   ├── Configures secrets
   └── Validates configuration
4. summary
```

> **Note:** Infrastructure bootstrap (Phase A) and deployments are handled by the separate
> `azure-bootstrap.yml` workflow, which runs _after_ initial setup is complete.

### Context Passing

**From azure-initial-setup.yml to this workflow:**
- Environment selection
- Branch information
- OIDC credentials (clientId, tenantId, subscriptionId)
- Setup flags (setupGitHubApp, configureSecrets)

**From this workflow to azure-initial-setup.yml:**
- Job results (setup-result, secrets-result, validation-result)
- Success/failure status for downstream job dependencies

## 🔬 Phase 1 Dry Run — Step-by-Step Data Flow

This section traces the complete data path from OIDC login through secret creation for a first-time `setupOidc=true` + `configureSecrets=true` run.

### Inputs (set by user in GitHub UI)

```
# Run via: Actions → Azure Initial Setup → Run workflow
environment:      dev
setupOidc:        true   ← Phase 1a
configureSecrets: true   ← Phase 1b
setupGitHubApp:   false  ← already done in Phase 0
```

> **Note:** These inputs are on `azure-initial-setup.yml`. Infrastructure bootstrap (`bootstrapInfra`)
> and deployments (`deployApi`/`deployUi`) are separate inputs on `azure-bootstrap.yml`.

### Step 1 — `validate-inputs` (azure-initial-setup.yml)

- Validates `environment=dev` and branch = `dev` ✅
- Checks: `AZUREAPPSERVICE_*` secrets missing → OK because `setupOidc=true` will create them ✅
- Checks: `APP_ID` + `APP_PRIVATE_KEY` present (required for Phase 1b) ✅
- Prints Pre-Flight Summary showing both phases "WILL RUN"
- **No credentials written yet**

### Step 2 — `setup-oidc` — Check Azure Authentication Method

```
Input from environment context:
  EXISTING_CLIENT_ID      = "" (not yet set)
  EXISTING_TENANT_ID      = "" (not yet set)
  EXISTING_SUBSCRIPTION_ID = "" (not yet set)

Result:
  useOidc = false  → device-code login required
```

### Step 3 — `setup-oidc` — Azure Login (Device Code — First-Time Setup Only)

```
az login --use-device-code
  ↓
Workflow logs print:
  "To sign in, use a web browser to open https://login.microsoft.com/device
   and enter the code ABCD-EFGH to authenticate."
  ↓
User opens https://login.microsoft.com/device, enters ABCD-EFGH, signs in
  ↓
Azure returns an access token bound to the user's account
  ↓
Azure CLI session is now authenticated
```

> ⏱️ Timeout: 3 minutes. If the code is not entered in time, re-run the workflow.
> ℹ️ Azure may still print the older alias `https://microsoft.com/devicelogin` in some environments. Either URL is valid for the device-code flow.

### Step 4 — `setup-oidc` — Setup OIDC App Registration

```
Parameters computed from environment=dev:
  branches     = "dev"
  environments = "dev"

Runs: setup-github-oidc.ps1
  -Branches "dev"
  -Environments "dev"
  -GitHubOwner "pavanthakur"
  -Repository "XYDataLabs.OrderProcessingSystem"
  -AppDisplayName "GitHub-Actions-OIDC"

Script actions:
  1. Creates (or finds existing) Entra ID App Registration "GitHub-Actions-OIDC"
  2. Creates Service Principal for the App Registration
  3. Creates federated credential for branch:
       name:    "github-dev-oidc"
       subject: "repo:pavanthakur/XYDataLabs.OrderProcessingSystem:ref:refs/heads/dev"
  4. Creates federated credential for environment:
       name:    "github-dev-env-oidc"
       subject: "repo:pavanthakur/XYDataLabs.OrderProcessingSystem:environment:dev"
  5. Assigns Contributor RBAC on the subscription/resource group to the Service Principal
```

### Step 5 — `setup-oidc` — Extract and Output Credentials

```
az account show  →  { id: "sub-123", tenantId: "tnt-456" }
az ad app list --display-name "GitHub-Actions-OIDC"  →  { appId: "clt-789", id: "obj-abc" }

Job outputs written to GITHUB_OUTPUT:
  clientId       = "clt-789"
  tenantId       = "tnt-456"
  subscriptionId = "sub-123"
  appObjectId    = "obj-abc"
```

### Step 6 — `configure-github-secrets` — Receives Phase 1a Outputs

```yaml
# In azure-initial-setup.yml:
configure-github-secrets:
  uses: ./.github/workflows/configure-github-secrets.yml
  with:
    environment:    dev
    configureSecrets: true
    clientIdB64:       ${{ needs.setup-oidc.outputs.clientIdB64 }}       # base64("clt-789")
    tenantIdB64:       ${{ needs.setup-oidc.outputs.tenantIdB64 }}       # base64("tnt-456")
    subscriptionIdB64: ${{ needs.setup-oidc.outputs.subscriptionIdB64 }} # base64("sub-123")
```

GitHub may emit annotations such as `Skip output 'clientIdB64' since it may contain secret.` when these encoded values are written. In a successful run, those warnings are expected masking heuristics, not a failure. Phase 1b still receives the values, which is confirmed when `Configure Secrets` succeeds and writes the `AZUREAPPSERVICE_*` secrets.

### Step 7 — `configure-secrets` — Validate Prerequisites

```
inputs.clientId     = "clt-789" ✅
inputs.tenantId     = "tnt-456" ✅
inputs.subscriptionId = "sub-123" ✅

credentialsProvided = true  → will write new secrets
useExistingSecrets  = false → fresh credentials
```

### Step 8 — `configure-secrets` — Generate GitHub App Token

```
APP_ID + APP_PRIVATE_KEY → actions/create-github-app-token@v3
  → short-lived GitHub App installation token (valid 1 hour, auto-rotated)
  → used as GH_TOKEN for all subsequent gh CLI calls
```

### Step 9 — `configure-secrets` — Set Repository Secrets

```
gh secret set AZUREAPPSERVICE_CLIENTID       --repo pavanthakur/XYDataLabs.OrderProcessingSystem --body "clt-789"
gh secret set AZUREAPPSERVICE_TENANTID       --repo pavanthakur/XYDataLabs.OrderProcessingSystem --body "tnt-456"
gh secret set AZUREAPPSERVICE_SUBSCRIPTIONID --repo pavanthakur/XYDataLabs.OrderProcessingSystem --body "sub-123"

Result:
  ✅ AZUREAPPSERVICE_CLIENTID       — set at repo level
  ✅ AZUREAPPSERVICE_TENANTID       — set at repo level
  ✅ AZUREAPPSERVICE_SUBSCRIPTIONID — set at repo level
```

### Step 10 — `configure-secrets` — Create GitHub Environment + Set Environment Secrets

```
environments to configure: ["dev"]  (from environment=dev)

For environment "dev":
  gh api --method PUT "repos/pavanthakur/XYDataLabs.OrderProcessingSystem/environments/dev"
    → ✅ environment created (or already exists)

  gh secret set AZUREAPPSERVICE_CLIENTID       --env dev --repo ... --body "clt-789"
  gh secret set AZUREAPPSERVICE_TENANTID       --env dev --repo ... --body "tnt-456"
  gh secret set AZUREAPPSERVICE_SUBSCRIPTIONID --env dev --repo ... --body "sub-123"
    → ✅ all three secrets set at environment level
```

### Final State (what was created)

| Location | Secret | Value |
|----------|--------|-------|
| Repository secrets | `AZUREAPPSERVICE_CLIENTID` | `clt-789` |
| Repository secrets | `AZUREAPPSERVICE_TENANTID` | `tnt-456` |
| Repository secrets | `AZUREAPPSERVICE_SUBSCRIPTIONID` | `sub-123` |
| `dev` environment secrets | `AZUREAPPSERVICE_CLIENTID` | `clt-789` |
| `dev` environment secrets | `AZUREAPPSERVICE_TENANTID` | `tnt-456` |
| `dev` environment secrets | `AZUREAPPSERVICE_SUBSCRIPTIONID` | `sub-123` |

| Azure Resource | What Was Created |
|----------------|-----------------|
| Entra ID App Registration | `GitHub-Actions-OIDC` with Client ID `clt-789` |
| Federated credential (branch) | `repo:.../XYDataLabs.OrderProcessingSystem:ref:refs/heads/dev` |
| Federated credential (environment) | `repo:.../XYDataLabs.OrderProcessingSystem:environment:dev` |

### Re-run Behaviour (after first successful run)

On the next run (e.g., credential rotation or adding `staging`):

```
Step 2 — Auth Check:
  EXISTING_CLIENT_ID = "clt-789" ✅
  useOidc = true  → azure/login@v3 (no device code, fully automated)

Step 7 — Prerequisites:
  If new clientId/tenantId/subscriptionId passed:
    credentialsProvided = true  → overwrite existing secrets
  If no new credentials passed AND existing secrets present:
    useExistingSecrets = true   → no writes needed, Phase 1b is a no-op
```
## Usage Examples

### Example 1: First-Time Setup (Recommended — Run Phase 1a + 1b Together)

```yaml
# Run azure-initial-setup.yml with both Phase 1 checkboxes selected.
# OIDC outputs (clientId/tenantId/subscriptionId) are automatically
# passed from setup-oidc to configure-github-secrets by the workflow.

azure-initial-setup.yml:
  environment: all        # Configure all environments at once
  setupOidc: true         # Phase 1a — device-code login, create Entra ID App
  configureSecrets: true  # Phase 1b — receives 1a outputs, writes AZUREAPPSERVICE_* secrets
  setupGitHubApp: false   # Already done in Phase 0
```

Phase 1a and Phase 1b always run sequentially (1a first, then 1b). The workflow dependency chain enforces this order automatically — no manual coordination is needed.

### Example 2: Complete Initial Setup (All Phases)

```yaml
# Run azure-initial-setup.yml with all options
azure-initial-setup.yml:
  environment: all
  setupGitHubApp: true    # Phase 0 — shows setup instructions
  setupOidc: true         # Phase 1a — create Entra ID App + federated credentials
  configureSecrets: true  # Phase 1b — write AZUREAPPSERVICE_* secrets to GitHub

# This workflow is automatically called and:
# 1. Provides GitHub App setup guidance
# 2. Configures all secrets
# 3. Validates configuration

# After initial setup completes, run infrastructure bootstrap separately:
# azure-bootstrap.yml → bootstrapInfra: true, deployApi: true, deployUi: true
```

### Example 3: Reconfigure Secrets for Specific Environment

```yaml
# Run this workflow directly
configure-github-secrets.yml:
  environment: staging
  setupGitHubApp: false
  configureSecrets: true
  clientId: <current or updated>
  tenantId: <current or updated>
  subscriptionId: <current or updated>
```

### Example 4: Troubleshooting

```yaml
# Validate GitHub App setup
configure-github-secrets.yml:
  environment: dev
  setupGitHubApp: true  # Check current setup
  configureSecrets: false

# Or use validation script locally:
./scripts/validate-github-app-config.ps1 -Detailed
```

## Troubleshooting

### GitHub App Token Generation Failed

**Symptom:**
```
❌ Failed to generate GitHub App installation token
```

**Common Causes:**
1. GitHub App not installed on repository
2. Incorrect APP_ID secret
3. Invalid APP_PRIVATE_KEY format
4. Missing "Secrets: Read and write" permission

**Solutions:**
1. Install app: https://github.com/settings/installations
2. Verify APP_ID matches your app
3. Ensure APP_PRIVATE_KEY includes BEGIN/END lines
4. Add "Secrets: Read and write" permission to app

### Environment Secret Configuration Failed

**Symptom:**
```
❌ Failed to set environment secret
```

**Common Causes:**
1. Environment doesn't exist
2. Missing "Environments: write" permission
3. Repository access restrictions

**Solutions:**
1. Create environment manually or let workflow create it
2. Add "Environments: write" permission to GitHub App
3. Verify app has access to repository

### Missing OIDC Credentials

**Symptom:**
```
❌ OIDC secrets are missing and no new credentials were provided!
```

**Root Cause:**  
Phase 1b (`configureSecrets`) was run without Phase 1a (`setupOidc`), and no `AZUREAPPSERVICE_*` secrets exist in the repository yet (first-time setup).

**Solution:**  
Re-run the **Azure Initial Setup** workflow with **both** Phase 1 checkboxes selected:

| Parameter | Value |
|-----------|-------|
| 🔑 Setup Azure OIDC (Phase 1a) | `true` ✅ |
| 🔑 Configure GitHub Secrets (Phase 1b) | `true` ✅ |

**After the first successful run**, Phase 1a does not need to be repeated. The `AZUREAPPSERVICE_*` secrets are stored persistently and used automatically by Phase 1b on subsequent runs.

---

### ℹ️ Is Azure OIDC Required for Phase 1b, A, and Deploy?

**Short answer: Yes for Phase 1b, A, and Deploy — but Phase 1a only needs to run ONCE.**

| Phase | Requires Azure OIDC? | Notes |
|-------|---------------------|-------|
| Phase 0 — GitHub App | ❌ No | Only manages GitHub secrets; no Azure access |
| **Phase 1a — Setup Azure OIDC** | N/A — this IS the setup | Run once to create the Azure identity (`GitHub-Actions-OIDC` app registration) |
| **Phase 1b — Configure Secrets** | ✅ Yes (first run only) | Needs `clientId`/`tenantId`/`subscriptionId` from Phase 1a to store as `AZUREAPPSERVICE_*` secrets. On re-runs: uses existing secrets if present — no Phase 1a needed. |
| Phase A — Bootstrap Infrastructure | ✅ Yes | Uses `AZUREAPPSERVICE_*` secrets set by Phase 1b |
| Deploy — Deploy API/UI | ✅ Yes | Uses `AZUREAPPSERVICE_*` secrets set by Phase 1b |

> **Phase 0 (GitHub App) is NOT a substitute for OIDC.** The GitHub App is only for managing GitHub repository secrets (writing `AZUREAPPSERVICE_*` to GitHub). It does NOT grant any Azure permissions. Phase A and Deploy workflows always authenticate to Azure via OIDC — the stored `AZUREAPPSERVICE_*` secrets are the mechanism.

## Validation

### Local Validation

```powershell
# Validate complete configuration
.\scripts\validate-github-app-config.ps1 -Detailed

# Checks:
# ✓ GitHub CLI authentication
# ✓ Repository secrets
# ✓ Environment secrets
# ✓ GitHub App installation
# ✓ Permissions
```

### Workflow Validation

The workflow automatically validates configuration at the end:
- GitHub App setup status
- Secret configuration status
- Environment setup status

## Documentation

- **Automation Guide**: `Documentation/03-Configuration-Guides/GITHUB-APP-AUTOMATION.md`
- **Quick Setup**: `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md`
- **Setup Script**: `scripts/setup-github-app-from-manifest.ps1`
- **Validation Script**: `scripts/validate-github-app-config.ps1`
- **App Manifest**: `.github/app-manifest.json`

## Benefits of Separation

### Modularity
- GitHub configuration is self-contained
- Can be updated independently
- Easier to test in isolation

### Tracking
- Separate execution tracking in Actions UI
- Clear visibility of GitHub configuration status
- Easier to debug issues

### Reusability
- Can be called from multiple workflows
- Supports both manual and automated triggers
- Flexible input parameters

### Maintainability
- Cleaner bootstrap workflow (29% smaller)
- Focused responsibility
- Easier to understand and modify

## Related Workflows

- **azure-initial-setup.yml**: Calls this workflow (Phase 0 → 1a → 1b)
- **azure-bootstrap.yml**: Infrastructure bootstrap & deploy (Phase A + deployments) — runs after initial setup
- **deploy-api-to-azure.yml**: API deployment (uses configured secrets)
- **deploy-ui-to-azure.yml**: UI deployment (uses configured secrets)

## Version History

- **v1.0**: Initial separation from azure-bootstrap.yml
- Extracted jobs: setup-github-app, configure-secrets, validate-configuration
- Added workflow_call support for integration
- Added comprehensive validation and error handling
- **v1.1**: Workflow split — now called exclusively by `azure-initial-setup.yml` (no longer by `azure-bootstrap.yml`). Phase 0/1a/1b live in Initial Setup; Phase A + deployments live in Bootstrap & Deploy.
- **v1.2**: Phase 2/3 naming retired — renamed to Phase A (bootstrap) and Deploy. Backtick rendering fix in step summaries. LASTEXITCODE false exit-1 fix, fail-hard behavior, and comprehensive diagnostics added.

---

## 🔧 Recent Functional Changes (March 2026)

### Backtick Rendering Fix in Step Summaries
**Symptom**: GitHub step summary showed `\APP_ID\` instead of `` `APP_ID` ``.
**Root cause**: In PowerShell double-quoted strings, the sequence `` \` `` is a literal backslash followed by the escape character — producing `\X` not `` `X` ``. All GITHUB_STEP_SUMMARY lines used `` \` `` wrapping.
**Fix**: Replaced all occurrences of `` \` `` with ` `` ` (double backtick = literal backtick in PowerShell double-quoted strings) across every `$env:GITHUB_STEP_SUMMARY` heredoc in this workflow.

### LASTEXITCODE False Exit-1 Fix
**Commit**: `dffb1eb`
**Symptom**: `Validate Prerequisites` step failed even when validation passed — logged "✅ Prerequisite validation complete" then immediately exited with code 1.
**Root cause**: `gh secret list --env prod` returns a non-zero exit code when the environment does not yet exist. GitHub Actions checks `$LASTEXITCODE` implicitly at the end of every `run:` step with `pwsh`. The `else` branch handled the missing environment gracefully, but the non-zero `$LASTEXITCODE` was still visible at step exit.
**Fix**: Added `exit 0` at the very end of the `Validate Prerequisites` step, after all validation logic, to ensure the step always exits cleanly when the script itself determined success.

### Fail-Hard for Environment Secret Creation
**Commit**: `12266d6`
**What changed**: The `Set Environment Secrets` step now tracks failures per-environment and per-secret into a `$totalFail` counter. If `$totalFail -gt 0` at the end, the step exits with code 1.
**Why**: All three environments (`dev`, `staging`, `prod`) must have correct secrets for any deployment to work. A partial write leaves the repository in an inconsistent state, so a warning-only path was insufficient.

### Comprehensive Failure Diagnostics
**Commit**: `12266d6`
**What changed**: Every failure path now emits structured diagnostic output:
- Exact API response or `gh` exit code
- Authentication method in use at the time of failure
- The exact command that failed (for copy-paste reproduction)
- Numbered list of possible causes, each with a direct URL for remediation

**Failure paths covered**:
| Step | Condition | Diagnostic info logged |
|------|-----------|----------------------|
| `Validate Prerequisites` | `AZUREAPPSERVICE_*` secrets missing | Which env is missing + how to re-run Initial Setup |
| `Check GitHub App Authentication` | `else` branch (not token nor app) | All 3 boolean values + per-condition guidance |
| `Set Repository Secrets` | Required value missing | Per-value source explanation + solution |
| `Set Repository Secrets` | `gh secret set` failure | Target / auth method / exact command / 3 causes |
| `Set Environment Secrets` | Environment creation fails | API endpoint + 3 causes with doc links |
| `Set Environment Secrets` | Per-secret write fails | API response + exact command + causes |

### Three-Way `useExistingSecrets` Decision Logic
**Commit**: `d7c785d`
**What changed**: The prerequisite check now always queries environment-level secrets (not just repo-level) before deciding whether to skip secret writes. Three outcomes:
1. Fresh credentials passed as inputs → `useExistingSecrets = false` (always write)
2. No fresh creds, but all three `AZUREAPPSERVICE_*` exist at repo or environment level → `useExistingSecrets = true` (skip writes; credential rotation not needed)
3. No fresh creds, secrets missing → fail with diagnostic error pointing to Initial Setup
**Also**: Added `|| secrets.*` fallback to `env:` blocks in downstream jobs so existing repository secrets work as credential sources without requiring explicit inputs.

---

**Last Updated**: 2026-03-19
**Maintainer**: GitHub Copilot
