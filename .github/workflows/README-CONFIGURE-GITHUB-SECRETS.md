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
- Phase 2 (bootstrap infra) and Phase 3 (deploy) use `azure/login@v2` with these secrets to authenticate to Azure.

### Why Phase 1b "depends on" OIDC credentials

Phase 1b needs the OIDC credential **values** to store them — not to authenticate with them. Those values come from:
- **First run**: Phase 1a outputs `clientId`/`tenantId`/`subscriptionId` and passes them to this workflow.
- **Re-runs**: The `AZUREAPPSERVICE_*` secrets already exist in GitHub from a previous Phase 1b run. This workflow writes them again if new values are passed.

### How `azure/login@v2` is shared across phases

`azure/login@v2` is the **single, consistent Azure authentication action** used by every workflow job that needs to interact with Azure:

| Job | Uses `azure/login@v2`? | Notes |
|-----|------------------------|-------|
| **Phase 1b (this workflow)** | ❌ No | GitHub App token only |
| Phase 1a (re-run) | ✅ Yes | Same credentials as Phase 2 |
| Phase 2 (bootstrap-dev/staging/prod) | ✅ Yes | 3-step pattern: Validate → Login → Verify |
| Phase 3 (deploy-api/ui) | ✅ Yes | 2-step pattern: Check → Login (conditional) |

Each job calls `azure/login@v2` independently because GitHub Actions jobs run on isolated runners and cannot share login state.

The **only** place where a human enters credentials to generate an Azure token is Phase 1a's first-time device-code step. All other Azure logins (Phase 1a re-run, Phase 2, Phase 3) are fully automated using the stored OIDC credentials.

## Purpose

Automates:
- GitHub App setup guidance and validation
- Repository secret configuration (Azure OIDC credentials)
- Environment secret configuration (dev, staging, prod)
- Configuration validation

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

Called by `azure-bootstrap.yml` after OIDC setup:

```yaml
configure-github-secrets:
  uses: ./.github/workflows/configure-github-secrets.yml
  with:
    environment: ${{ inputs.environment }}
    setupGitHubApp: ${{ inputs.setupGitHubApp }}
    configureSecrets: ${{ inputs.configureSecrets }}
    clientId: ${{ needs.setup-oidc.outputs.clientId }}
    tenantId: ${{ needs.setup-oidc.outputs.tenantId }}
    subscriptionId: ${{ needs.setup-oidc.outputs.subscriptionId }}
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

## Integration with Bootstrap Workflow

### Flow in azure-bootstrap.yml

```
1. validate-inputs
2. setup-oidc
   ├── Creates Azure OIDC app
   └── Outputs: clientId, tenantId, subscriptionId
3. configure-github-secrets ← THIS WORKFLOW
   ├── Receives OIDC outputs
   ├── Configures GitHub App (if needed)
   ├── Configures secrets
   └── Validates configuration
4. pre-validate-prerequisites
5. bootstrap-dev/staging/prod
6. summary
```

### Context Passing

**From bootstrap to this workflow:**
- Environment selection
- Branch information
- OIDC credentials (clientId, tenantId, subscriptionId)
- Setup flags (setupGitHubApp, configureSecrets)

**From this workflow to bootstrap:**
- Job results (setup-result, secrets-result, validation-result)
- Success/failure status for downstream job dependencies

## Usage Examples

### Example 1: First-Time Setup

```yaml
# Step 1: Run bootstrap with OIDC setup
azure-bootstrap.yml:
  setupOidc: true
  setupGitHubApp: false
  configureSecrets: false

# Step 2: Manually setup GitHub App (one-time)
# Follow instructions in workflow output or use:
# ./scripts/setup-github-app-from-manifest.ps1

# Step 3: Run configure-github-secrets workflow manually
configure-github-secrets.yml:
  environment: all
  setupGitHubApp: false
  configureSecrets: true
  clientId: <from Azure>
  tenantId: <from Azure>
  subscriptionId: <from Azure>
```

### Example 2: Complete Automated Setup

```yaml
# Run bootstrap with all options
azure-bootstrap.yml:
  environment: all
  setupOidc: true
  setupGitHubApp: true  # Shows setup instructions
  configureSecrets: true  # Automatically configures after OIDC
  bootstrapInfra: true

# This workflow is automatically called and:
# 1. Provides GitHub App setup guidance
# 2. Configures all secrets
# 3. Validates configuration
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
2. Missing "Administration: Read and write" permission
3. Repository access restrictions

**Solutions:**
1. Create environment manually or let workflow create it
2. Add "Administration: Read and write" permission to GitHub App
3. Verify app has access to repository

### Missing OIDC Credentials

**Symptom:**
```
❌ OIDC secrets are missing and no new credentials were provided!
```

**Root Cause:**  
Phase 1b (`configureSecrets`) was run without Phase 1a (`setupOidc`), and no `AZUREAPPSERVICE_*` secrets exist in the repository yet (first-time setup).

**Solution:**  
Re-run the bootstrap workflow with **both** Phase 1 checkboxes selected:

| Parameter | Value |
|-----------|-------|
| 🔑 Setup Azure OIDC (Phase 1a) | `true` ✅ |
| 🔑 Configure GitHub Secrets (Phase 1b) | `true` ✅ |

**After the first successful run**, Phase 1a does not need to be repeated. The `AZUREAPPSERVICE_*` secrets are stored persistently and used automatically by Phase 1b on subsequent runs.

---

### ℹ️ Is Azure OIDC Required for Phase 1b, 2, and 3?

**Short answer: Yes for all three phases — but Phase 1a only needs to run ONCE.**

| Phase | Requires Azure OIDC? | Notes |
|-------|---------------------|-------|
| Phase 0 — GitHub App | ❌ No | Only manages GitHub secrets; no Azure access |
| **Phase 1a — Setup Azure OIDC** | N/A — this IS the setup | Run once to create the Azure identity (`GitHub-Actions-OIDC` app registration) |
| **Phase 1b — Configure Secrets** | ✅ Yes (first run only) | Needs `clientId`/`tenantId`/`subscriptionId` from Phase 1a to store as `AZUREAPPSERVICE_*` secrets. On re-runs: uses existing secrets if present — no Phase 1a needed. |
| Phase 2 — Bootstrap Infrastructure | ✅ Yes | Uses `AZUREAPPSERVICE_*` secrets set by Phase 1b |
| Phase 3 — Deploy API/UI | ✅ Yes | Uses `AZUREAPPSERVICE_*` secrets set by Phase 1b |

> **Phase 0 (GitHub App) is NOT a substitute for OIDC.** The GitHub App is only for managing GitHub repository secrets (writing `AZUREAPPSERVICE_*` to GitHub). It does NOT grant any Azure permissions. Phase 2 and Phase 3 always authenticate to Azure via OIDC — the stored `AZUREAPPSERVICE_*` secrets are the mechanism.

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

- **azure-bootstrap.yml**: Main orchestration workflow
- **deploy-api-to-azure.yml**: API deployment (uses configured secrets)
- **deploy-ui-to-azure.yml**: UI deployment (uses configured secrets)

## Version History

- **v1.0**: Initial separation from azure-bootstrap.yml
- Extracted jobs: setup-github-app, configure-secrets, validate-configuration
- Added workflow_call support for integration
- Added comprehensive validation and error handling

---

**Last Updated**: 2026-01-27
**Maintainer**: GitHub Copilot
