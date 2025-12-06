# Deployment Scripts

## Overview

This directory contains automation scripts for configuring and deploying the Order Processing System with secure configuration management.

## Scripts

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

- [Bicep Templates](../bicep/README.md) - Infrastructure as Code
- [Runbook](../docs/runbooks/keyvault-managed-identity-deploy.md) - Deployment runbook
- [GitHub Workflow](../.github/workflows/deploy-and-verify.yml) - CI/CD pipeline
