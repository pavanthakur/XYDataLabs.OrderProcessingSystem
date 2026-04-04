# Deployment and Configuration Scripts

## Overview

This directory contains automation scripts for configuring and deploying the Order Processing System with secure configuration management, including GitHub App automation tools.

---

## 🖥️ Local Development Bootstrap

### setup-local.ps1

**Run once after a fresh `git clone`** — bootstraps everything needed to develop locally without any manual prompts.

**Purpose**:
- Creates `Resources/Docker/.env.local` from `.env.local.example` (Docker secrets)
- Sets `dotnet user-secrets` for VS F5 and `dotnet run` (API + UI projects)
- Exports and trusts the HTTPS dev certificate

**Usage**:
```powershell
# First run — prompts you to choose SQL + cert passwords, saves to .env.local
.\scripts\setup-local.ps1

# Re-run and overwrite everything (after password change, or clean reset)
.\scripts\setup-local.ps1 -Force
```

**Parameters**:
- `Force` (switch): Re-prompt for passwords, overwrite `.env.local`, user-secrets, and dev cert

**What It Does**:
1. ✅ Creates `Resources/Docker/.env.local` with Docker secrets (skips if already exists)
2. ✅ Sets `dotnet user-secrets` for API: `CertPassword`, `OpenPay:MerchantId/PrivateKey/DeviceSessionId`
3. ✅ Sets `dotnet user-secrets` for UI: `CertPassword`
4. ✅ Exports `aspnetapp.pfx` and trusts HTTPS dev certificate

**After Running**:
- Visual Studio F5 on `http`/`https` profile → ready, no prompts
- Docker: `.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http`
- To use real OpenPay sandbox credentials: `setup-local.ps1` tries Azure Key Vault first, then prompts interactively. RedirectUrl is auto-resolved from `ApiSettings:UI`.

**Idempotent**: Safe to re-run at any time — skips steps already completed.

**Prerequisites**:
- .NET 8 SDK installed
- PowerShell 7+

---

## 🆕 GitHub App Automation Scripts

### verify-payment-run-azure.ps1

Deterministic Azure payment verification for the `verify-db-logs` workflow.

**Purpose**:
- Queries Azure App Insights API traces and UI callback traces in one pass
- Resolves the logical run prefix automatically when only one prefix exists for the day
- Queries both Azure SQL databases directly without ad hoc `sqlcmd` parsing in the terminal
- Produces a consolidated API -> UI -> DB pass/fail report for a selected run prefix

**Usage**:
```powershell
# Auto-resolve the only run prefix found today
.\scripts\verify-payment-run-azure.ps1 -Environment dev

# Verify a specific logical run prefix
.\scripts\verify-payment-run-azure.ps1 -Environment dev -RunPrefix OR-1-2ndApr

# Emit structured JSON for later processing
.\scripts\verify-payment-run-azure.ps1 -Environment dev -RunPrefix OR-1-2ndApr -OutputFormat Json
```

**Parameters**:
- `Environment` (optional): `dev`, `stg`, or `prod` (default: `dev`)
- `RunPrefix` (optional): logical run prefix such as `OR-1-2ndApr`
- `OutputFormat` (optional): `Table` or `Json` (default: `Table`)
- `SkipFirewallOpen` (switch): skip the Azure SQL firewall helper call

**Prerequisites**:
- `az login` completed
- Key Vault access to `sql-admin-password`
- Local machine allowed through Azure SQL firewall, or allow the script to open it automatically

**Notes**:
- This script is Azure-only. Docker/local verification still uses the physical log flow documented in `docs/runbooks/payment-db-verification.md` and the `/XYDataLabs-verify-db-logs` prompt.
- If multiple run prefixes exist for the day, the script stops and asks you to rerun with `-RunPrefix`.
- If App Insights returns no scoped payment rows but you already know the logical prefix, rerun with `-RunPrefix` and the script will continue with DB verification while marking log-side checks as inconclusive.
- The pass/fail summary still scopes UI checks to callback evidence. Richer browser-originated `ui_payment_*` telemetry is available in App Insights for deeper triage and is documented in `docs/runbooks/payment-db-verification.md`.

### test-verify-payment-run-azure.ps1

Regression runner for `verify-payment-run-azure.ps1`.

**Purpose**:
- Replays the Azure verifier as a child script and asserts expected behavior from structured JSON output
- Guards the staging SQL pass path and, when App Insights evidence is still available, the full log correlation path end-to-end
- Guards the sparse/no-App-Insights fallback path so missing evidence degrades to `INCONCLUSIVE` instead of crashing

**Usage**:
```powershell
# Run the staging happy-path regression
.\scripts\test-verify-payment-run-azure.ps1

# Run staging and the optional dev sparse-evidence regression
.\scripts\test-verify-payment-run-azure.ps1 -Scenario stg-pass,dev-fallback -DevRunPrefix OR-1-2ndApr
```

**Parameters**:
- `Scenario` (optional): one or more of `stg-pass`, `dev-fallback` (default: `stg-pass`)
- `StagingRunPrefix` (optional): explicit staging run prefix if auto-resolution would be ambiguous
- `DevRunPrefix` (optional): dev run prefix used to exercise the fallback scenario
- `SkipFirewallOpen` (switch): skip the Azure SQL firewall helper call

**Notes**:
- This is a repo-style script validation runner, not a Pester suite.
- The default `stg-pass` scenario depends on an unambiguous live staging run for the current day. If none exists, the runner skips the scenario and tells you to supply `-StagingRunPrefix`.
- The `dev-fallback` scenario is opt-in because it depends on a known logical prefix from an existing dev Azure run.

### setup-github-app-from-manifest.ps1

**NEW** - Streamlines GitHub App creation using a declarative manifest configuration.

**Purpose**: 
- Simplifies GitHub App creation process
- Ensures consistent configuration across recreations
- Provides step-by-step guided setup
- Validates configuration

**Usage**:
```powershell
# Standard setup with manifest
./scripts/setup-github-app-from-manifest.ps1

# Validate only (no creation)
./scripts/setup-github-app-from-manifest.ps1 -ValidateOnly

# Custom repository and app name
./scripts/setup-github-app-from-manifest.ps1 `
  -Repository myorg/myrepo `
  -AppName MyCustomApp
```

**Parameters**:
- `Repository` (optional): GitHub repository in format owner/repo (default: pavanthakur/XYDataLabs.OrderProcessingSystem)
- `AppName` (optional): Custom name for the GitHub App (overrides manifest default)
- `ValidateOnly` (switch): Only validate existing app configuration

**What It Does**:
1. ✅ Reads and validates the app manifest (`.github/app-manifest.json`)
2. ✅ Displays required configuration
3. ✅ Provides guided instructions for app creation
4. ✅ Shows exact permissions needed
5. ✅ Guides through private key generation
6. ✅ Guides through app installation

**Prerequisites**:
- PowerShell 7+ (for proper JSON handling)
- GitHub account with admin access to repository

**Related Files**:
- `.github/app-manifest.json` - Declarative app configuration

---

### validate-github-app-config.ps1

**NEW** - Comprehensive validation tool for GitHub App configuration.

**Purpose**:
- Validates GitHub App setup
- Checks repository and environment secrets
- Verifies app installation
- Diagnoses configuration issues
- Provides actionable troubleshooting guidance

**Usage**:
```powershell
# Basic validation
./scripts/validate-github-app-config.ps1

# Detailed validation with verbose output
./scripts/validate-github-app-config.ps1 -Detailed

# Validate specific repository
./scripts/validate-github-app-config.ps1 `
  -Repository pavanthakur/XYDataLabs.OrderProcessingSystem `
  -Detailed

# Validate with specific App ID
./scripts/validate-github-app-config.ps1 -AppId 12345 -Detailed
```

**Parameters**:
- `Repository` (optional): GitHub repository in format owner/repo (default: pavanthakur/XYDataLabs.OrderProcessingSystem)
- `AppId` (optional): GitHub App ID (uses APP_ID environment variable if not provided)
- `Detailed` (switch): Show detailed validation output

**What It Validates**:
1. ✅ GitHub CLI installation and authentication
2. ✅ Repository secrets (APP_ID, APP_PRIVATE_KEY)
3. ✅ Environment secrets (dev, staging, prod)
   - AZUREAPPSERVICE_CLIENTID
   - AZUREAPPSERVICE_TENANTID
   - AZUREAPPSERVICE_SUBSCRIPTIONID
4. ✅ GitHub App installation status
5. ✅ App accessibility via API
6. ⚠️ Manual verification checklist for permissions

**Exit Codes**:
- `0`: All automated checks passed
- `1`: One or more checks failed

**When to Use**:
- 🔍 Before running bootstrap workflow
- 🔍 After creating/recreating GitHub App
- 🔍 When troubleshooting authentication issues
- 🔍 After modifying app permissions
- 🔍 As part of regular maintenance

**Prerequisites**:
- GitHub CLI installed and authenticated (`gh auth login`)
- Admin access to repository

---

## Deployment Scripts

### configure-secrets-and-run.ps1

Main wrapper script that orchestrates the complete configuration flow.

**Purpose**: Implements the Option 3 → Option 1 flow:
1. Populates GitHub environment secrets
2. Configures App Service environment settings
3. Validates each step
4. Runs health checks

**Usage**:
```powershell
# Basic usage for dev environment
./scripts/configure-secrets-and-run.ps1 -Environment dev

# Full parameters
./scripts/configure-secrets-and-run.ps1 `
  -Environment dev `
  -Repository pavanthakur/XYDataLabs.OrderProcessingSystem `
  -BaseName orderprocessing `
  -GitHubOwner pavanthakur `
  -Force

# Skip health check
./scripts/configure-secrets-and-run.ps1 -Environment dev -SkipHealthCheck
```

**Parameters**:
- `Environment` (required): Target environment (dev, staging, prod)
- `Repository` (optional): GitHub repository in format owner/repo (default: pavanthakur/XYDataLabs.OrderProcessingSystem)
- `BaseName` (optional): Base name for resources (default: orderprocessing)
- `GitHubOwner` (optional): GitHub repository owner name (default: pavanthakur)
- `Force` (switch): Overwrite existing secrets without prompting
- `SkipHealthCheck` (switch): Skip health check after configuration

**Exit Codes**:
- `0`: Success
- `1`: Failure (check error messages in output)

**Prerequisites**:
- Azure CLI installed and logged in (`az login`)
- GitHub CLI installed and authenticated (`gh auth login`)
- PowerShell 7+ installed
- Appropriate permissions in Azure and GitHub

**What It Does**:

1. **Step 1: Configure GitHub Secrets**
   - Calls `Resources/Azure-Deployment/configure-github-secrets.ps1`
   - Retrieves Azure OIDC credentials
   - Sets GitHub repository secrets:
     - `AZUREAPPSERVICE_CLIENTID`
     - `AZUREAPPSERVICE_TENANTID`
     - `AZUREAPPSERVICE_SUBSCRIPTIONID`
   - Validates exit code

2. **Step 2: Configure App Environment**
   - Calls `Resources/Azure-Deployment/configure-app-environment.ps1`
   - Sets `ASPNETCORE_ENVIRONMENT` on App Service
   - Validates exit code

3. **Step 3: Health Check**
   - Waits for app to stabilize (30 seconds)
   - Calls `/api/info/environment` endpoint
   - Validates HTTP 200 response
   - Displays environment information

**Example Output**:
```
╔════════════════════════════════════════════════════════════════╗
║     CONFIGURE SECRETS AND RUN - DEV                            ║
╚════════════════════════════════════════════════════════════════╝

Configuration:
  Environment:    dev
  Repository:     pavanthakur/XYDataLabs.OrderProcessingSystem
  Base Name:      orderprocessing
  GitHub Owner:   pavanthakur

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[STEP 1/3] Configuring GitHub Secrets...
  [SUCCESS] GitHub secrets configured successfully

[STEP 2/3] Configuring App Service Environment...
  [SUCCESS] App environment configured successfully

[STEP 3/3] Running Health Check...
  [SUCCESS] Health check passed (HTTP 200)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ CONFIGURATION AND DEPLOYMENT COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Related Scripts

The wrapper script depends on these existing scripts in `Resources/Azure-Deployment/`:

### configure-github-secrets.ps1
Configures GitHub repository secrets for Azure OIDC authentication.

**Located at**: `Resources/Azure-Deployment/configure-github-secrets.ps1`

**What it does**:
- Retrieves Azure subscription ID, tenant ID, and client ID
- Creates/updates GitHub repository secrets
- Validates GitHub CLI authentication

### configure-app-environment.ps1
Configures App Service environment variables.

**Located at**: `Resources/Azure-Deployment/configure-app-environment.ps1`

**What it does**:
- Sets `ASPNETCORE_ENVIRONMENT` on both API and UI App Services
- Verifies resource group and app existence
- Validates configuration after setting

## Workflow Integration

These scripts can be used:

1. **Locally by Developers/DevOps**:
   ```powershell
   ./scripts/configure-secrets-and-run.ps1 -Environment dev
   ```

2. **In CI/CD Pipelines**:
   - Called from GitHub Actions workflows
   - Used for environment setup before deployment

3. **For Troubleshooting**:
   - Run individual steps to diagnose issues
   - Use `-SkipHealthCheck` to test configuration without health validation

## Error Handling

The wrapper script:
- Validates each step's exit code
- Stops on first failure
- Provides clear error messages
- Suggests remediation actions

**Common Errors**:

| Error | Cause | Solution |
|-------|-------|----------|
| Script not found | Missing dependency script | Verify `Resources/Azure-Deployment/` scripts exist |
| GitHub secrets failed | Not authenticated to GitHub | Run `gh auth login` |
| App config failed | Resource doesn't exist | Run infrastructure deployment first |
| Health check failed | App not started or misconfigured | Check Azure Portal logs, wait longer, or use `-SkipHealthCheck` |

## Best Practices

1. **Run in Dev First**: Always test configuration changes in dev before promoting
2. **Use -Force Sparingly**: Only use `-Force` when you know secrets need to be updated
3. **Check Prerequisites**: Ensure Azure CLI and GitHub CLI are authenticated
4. **Review Output**: Read the detailed output for any warnings or issues
5. **Idempotency**: Scripts are designed to be run multiple times safely
6. **Health Checks**: Don't skip health checks unless troubleshooting

## Troubleshooting

### Script Not Found Error

```powershell
[ERROR] Script not found: /path/to/script.ps1
```

**Solution**: Ensure you're running from the repository root and all dependency scripts exist.

### Authentication Errors

```
[ERROR] Not logged into Azure CLI
```

**Solution**: Run `az login` before executing the script.

```
[ERROR] GitHub authentication failed
```

**Solution**: Run `gh auth login` and authenticate to GitHub.

### Health Check Timeout

```
[ERROR] Health check failed: The operation has timed out
```

**Solution**:
- Verify app is running in Azure Portal
- Check application logs for startup errors
- Increase wait time in the script (modify line with `Start-Sleep`)
- Use `-SkipHealthCheck` to bypass health validation

### Permission Denied

```
[ERROR] Insufficient permissions to configure secrets
```

**Solution**: Verify you have:
- Repository admin access (for GitHub secrets)
- Contributor role in Azure (for app configuration)

## See Also

- [Bicep Templates](../../../bicep/README.md) - Infrastructure as Code
- [Runbook](../../runbooks/keyvault-managed-identity-deploy.md) - Deployment runbook
- [Workflow Overview](../../../.github/workflows/README.md) - Current CI/CD and deployment workflows

---

## 📚 GitHub App Automation Documentation

For comprehensive information about GitHub App automation, including:
- ✅ How to delete and recreate apps
- ✅ Understanding automation limitations
- ✅ Step-by-step recreation guide
- ✅ Secret management best practices
- ✅ Troubleshooting guide

See: [github-app-authentication.md](../configuration/github-app-authentication.md) and [workflow-automation-visual-guide.md](../configuration/workflow-automation-visual-guide.md)

### Quick Reference

#### App Manifest Location
`.github/app-manifest.json` - Declarative configuration for GitHub App

#### To Create New App
```powershell
./scripts/setup-github-app-from-manifest.ps1
```

#### To Validate Configuration
```powershell
./scripts/validate-github-app-config.ps1 -Detailed
```

#### To Delete and Recreate App
1. Document current config: `./scripts/validate-github-app-config.ps1 -Detailed > backup.txt`
2. Delete app at: https://github.com/settings/apps
3. Recreate with manifest: `./scripts/setup-github-app-from-manifest.ps1`
4. Update secrets (APP_ID, APP_PRIVATE_KEY)
5. Reinstall app on repository
6. Run bootstrap workflow with "Configure Secrets" enabled

---

## Workflow Integration

These scripts integrate with two workflows:

### Azure Initial Setup Workflow Flow
```
azure-initial-setup.yml (Phase 0/1a/1b)
  ├── setup-github-app (guides GitHub App creation)
  ├── setup-oidc (creates Azure OIDC app)
  └── configure-secrets (automated secret management)
      ├── Repository secrets via GitHub App
      └── Environment secrets (dev, staging, prod)
```

### Azure Bootstrap & Deploy Workflow Flow
```
azure-bootstrap.yml (Phase 2/Deploy/X)
  ├── bootstrap-infra (creates Azure resources)
  ├── deploy-api / deploy-ui (application deployment)
  └── cleanup (optional, destructive)
```

### Running Full Setup & Bootstrap
1. Navigate to Actions → **Azure Initial Setup** → Run workflow
   - ✅ Setup Azure OIDC
   - ✅ Setup GitHub App (first time only)
   - ✅ Configure Secrets
2. Navigate to Actions → **Azure Bootstrap & Deploy** → Run workflow
   - ✅ Bootstrap Infrastructure
   - ✅ Deploy API / Deploy UI
3. Follow on-screen instructions for any manual steps
4. Review validation output

---

## Script Dependencies

### External Tools Required
- PowerShell 7+
- Azure CLI (`az`)
- GitHub CLI (`gh`)

### Internal Script Dependencies
- `configure-secrets-and-run.ps1` → `configure-github-secrets.ps1`
- `configure-secrets-and-run.ps1` → `configure-app-environment.ps1`
- `setup-github-app-from-manifest.ps1` → `.github/app-manifest.json`

---

## Best Practices

### Before Running Scripts
1. ✅ Authenticate to Azure: `az login`
2. ✅ Authenticate to GitHub: `gh auth login`
3. ✅ Set correct subscription: `az account set --subscription <id>`
4. ✅ Verify repository access
5. ✅ Review script parameters

### After Running Scripts
1. ✅ Validate configuration: `./scripts/validate-github-app-config.ps1 -Detailed`
2. ✅ Check Azure Portal for resources
3. ✅ Verify secrets in GitHub
4. ✅ Test deployments
5. ✅ Review workflow logs

### Regular Maintenance
1. 🔄 Monthly: Run validation script
2. 🔄 Quarterly: Review app permissions
3. 🔄 As needed: Rotate private keys
4. 🔄 Always: Keep documentation updated
