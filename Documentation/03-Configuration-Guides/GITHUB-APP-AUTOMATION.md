# GitHub App Automation Guide

## Overview

This guide explains how to automate GitHub App setup and configuration for the XYDataLabs Order Processing System. While GitHub security requirements prevent full automation, this guide provides tools and workflows to streamline the process as much as possible.

## Table of Contents

1. [Understanding GitHub App Automation](#understanding-github-app-automation)
2. [Quick Start: Automated Setup](#quick-start-automated-setup)
3. [Detailed Configuration](#detailed-configuration)
4. [Secret Management Automation](#secret-management-automation)
5. [Deleting and Recreating Apps](#deleting-and-recreating-apps)
6. [Troubleshooting](#troubleshooting)

---

## Understanding GitHub App Automation

### What Can Be Automated

✅ **Fully Automated:**
- Secret configuration (via bootstrap workflow)
- Environment secret setup
- Repository secret setup
- Token generation (via GitHub App)
- Installation validation

⚠️ **Semi-Automated (Requires User Interaction):**
- Initial app creation (requires OAuth-like approval)
- Private key generation (manual download)
- Initial app installation (requires user approval)

❌ **Cannot Be Automated:**
- First-time app authorization (GitHub security requirement)
- Private key storage (security best practice)

### Why Full Automation Isn't Possible

GitHub's security model requires interactive user approval for:
1. **App Creation**: Ensures apps are created intentionally by authorized users
2. **Permission Grants**: Requires explicit user consent for access levels
3. **Installation**: Ensures repository owners control which apps have access

This is **by design** and cannot be circumvented.

---

## Quick Start: Automated Setup

### Prerequisites

- GitHub account with admin access to the repository
- GitHub CLI (`gh`) installed and authenticated
- PowerShell 7+ (for automation scripts)

### Option 1: Using App Manifest (Recommended)

The app manifest provides a declarative configuration that can be reused to create identical app configurations.

#### Step 1: Review the Manifest

The manifest file is located at `.github/app-manifest.json`:

```json
{
  "name": "XYDataLabs-OrderProcessing-Automation",
  "url": "https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem",
  "hook_attributes": {
    "active": false
  },
  "description": "Automated secret management and workflow automation",
  "public": false,
  "default_permissions": {
    "actions": "write",
    "secrets": "write",
    "workflows": "write",
    "pull_requests": "write",
    "administration": "write",
    "environments": "write",
    "contents": "read",
    "metadata": "read"
  },
  "default_events": []
}
```

#### Step 2: Run the Setup Script

```powershell
# From repository root
.\scripts\setup-github-app-from-manifest.ps1
```

This script will:
1. Read and validate the manifest
2. Display the configuration
3. Provide step-by-step instructions for app creation
4. Guide you through the semi-automated setup process

#### Step 3: Follow the On-Screen Instructions

The script provides detailed instructions for:
- Creating the app with manifest configuration
- Generating the private key
- Installing the app on the repository
- Adding secrets

#### Step 4: Validate Configuration

```powershell
# Validate the app configuration
.\scripts\validate-github-app-config.ps1 -Detailed
```

### Option 2: Manual Setup with Bootstrap Workflow

If you prefer to follow the existing manual process:

1. Run the bootstrap workflow: `.github/workflows/azure-bootstrap.yml`
2. Enable the "Setup GitHub App" option
3. Follow the instructions in the workflow output
4. Re-run with "Configure Secrets" enabled after app creation

---

## Detailed Configuration

### Required Permissions

The GitHub App **must** have these permissions:

| Permission | Access Level | Purpose |
|------------|--------------|---------|
| **Actions** | Read and write | Trigger workflows, manage workflow runs |
| **Secrets** | Read and write | ⚠️ **CRITICAL** - Configure repository & environment secrets |
| **Workflows** | Read and write | Modify workflow files, dispatch workflow runs |
| **Pull requests** | Read and write | Create/update PRs in workflows |
| **Administration** | Read and write | Repository settings, teams, and collaborators |
| **Environments** | Read and write | **CRITICAL** - Create/manage environments, configure protection rules |
| **Contents** | Read | Access repository files |
| **Metadata** | Read | Basic repository information (automatic) |

### Important Notes on Permissions

1. **Secrets Permission is Critical**: Without this, secret automation will fail
2. **Environments Permission is Critical**: Required for creating and managing environments
3. **Administration Permission**: Provides additional repository management capabilities
3. **No Webhook Required**: The app doesn't need to receive events

### Repository vs Environment Secrets

The automation configures two types of secrets:

#### Repository Secrets (Configured Once)
- `APP_ID`: Your GitHub App ID
- `APP_PRIVATE_KEY`: Private key for the app
- `AZUREAPPSERVICE_CLIENTID`: Azure OIDC Client ID
- `AZUREAPPSERVICE_TENANTID`: Azure Tenant ID
- `AZUREAPPSERVICE_SUBSCRIPTIONID`: Azure Subscription ID

#### Environment Secrets (Per Environment)
For each environment (dev, staging, prod):
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

---

## Secret Management Automation

### Automated Secret Configuration

Once the GitHub App is set up, secrets are **fully automated** via the bootstrap workflow:

```yaml
# In azure-bootstrap.yml
inputs:
  configureSecrets: true  # Enable this option
  environment: dev        # Or staging, prod, all
```

The workflow will:
1. ✅ Generate GitHub App installation token
2. ✅ Configure repository secrets
3. ✅ Create environments if they don't exist
4. ✅ Configure environment-specific secrets
5. ✅ Validate all configurations

### Environment-Specific Configuration

When `environment: all` is selected:
- Secrets are configured for **all** environments (dev, staging, prod)
- Environments are created if they don't exist
- Each environment gets its own secret configuration

When a specific environment is selected:
- Only that environment's secrets are configured
- Branch validation ensures correct branch is used

### Branch-Environment Alignment

The workflow validates branch-environment alignment:

| Branch | Recommended Environment |
|--------|------------------------|
| `dev` | `dev` |
| `staging` | `staging` |
| `main` | `prod` |

**Warning**: The workflow will warn you if branch and environment don't align.

---

## Deleting and Recreating Apps

### Can I Delete and Recreate the App?

**Yes**, you can delete and recreate the GitHub App. Here's the process:

### Step 1: Document Current Configuration

Before deleting, validate and document your current setup:

```powershell
# Save current configuration
.\scripts\validate-github-app-config.ps1 -Detailed > app-config-backup.txt
```

### Step 2: Delete the App

1. Go to: https://github.com/settings/apps
2. Find your app
3. Click "Advanced" tab
4. Scroll to "Danger Zone"
5. Click "Delete GitHub App"
6. Confirm deletion

### Step 3: Recreate Using Manifest

```powershell
# Use the manifest to recreate with identical configuration
.\scripts\setup-github-app-from-manifest.ps1
```

This ensures the new app has **exactly the same configuration** as before.

### Step 4: Update Secrets

After recreating the app:

1. Update `APP_ID` in repository secrets (new app will have different ID)
2. Update `APP_PRIVATE_KEY` with the new private key
3. Reinstall the app on the repository

### Step 5: Re-run Bootstrap

```powershell
# Run bootstrap workflow to reconfigure all secrets
# Enable: "Configure Secrets" = true
```

### What Happens to Existing Secrets?

- **Repository secrets**: Remain intact, only need to update APP_ID and APP_PRIVATE_KEY
- **Environment secrets**: Remain intact, no action needed
- **Azure credentials**: Unaffected by app deletion/recreation

### When to Delete and Recreate

Delete and recreate when:
- ✅ You need to change app permissions
- ✅ App was misconfigured during initial setup
- ✅ Private key was compromised
- ✅ Starting fresh after testing
- ✅ Moving to production from development setup

**Don't** delete if:
- ❌ Secrets have expired (they don't - app tokens are generated on-demand)
- ❌ You just need to update repository secrets
- ❌ You're troubleshooting - validate first instead

---

## Troubleshooting

### Validation Script

Always start with validation:

```powershell
.\scripts\validate-github-app-config.ps1 -Detailed
```

This checks:
- ✅ GitHub CLI installation
- ✅ Authentication status
- ✅ Repository secrets
- ✅ Environment secrets
- ✅ App installation
- ✅ API accessibility

### Common Issues

#### Issue: "GitHub App token generation failed"

**Cause**: App not installed on repository

**Solution**:
1. Go to: https://github.com/settings/installations
2. Find your app installation
3. Click "Configure"
4. Ensure the repository is selected
5. Save changes

#### Issue: "Failed to set secrets"

**Cause**: Missing "Secrets: Read and write" permission

**Solution**:
1. Go to: https://github.com/settings/apps/[your-app]
2. Click "Permissions & events"
3. Repository permissions → Secrets → Read and write
4. Save changes
5. Approve updated permissions on installation page

#### Issue: "Environment secrets configuration failed"

**Cause**: Missing "Environments: Read and write" permission

**Solution**:
1. Add "Environments: Read and write" permission to app
2. Re-approve permissions
3. Re-run bootstrap workflow

#### Issue: "APP_INSTALLATION_ID not found"

**Solution**: Installation ID is **auto-discovered** - this error shouldn't occur in newer versions. If it does:
1. Ensure app is installed on repository
2. Verify APP_ID and APP_PRIVATE_KEY are correct
3. Check app permissions

### Getting Help

If you encounter issues:

1. **Run validation**: `.\scripts\validate-github-app-config.ps1 -Detailed`
2. **Check workflow logs**: Review the bootstrap workflow run for detailed error messages
3. **Review documentation**: 
   - `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md`
   - `Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md`
4. **Check GitHub App settings**: Verify all permissions are correct

---

## Advanced: Programmatic App Management

### Using GitHub API

While full automation isn't possible, you can use the API for certain operations:

```powershell
# Get app information (requires APP_ID and APP_PRIVATE_KEY)
gh api /app

# List installations
gh api /app/installations

# Get installation access token (what the workflow does)
# This is automated via actions/create-github-app-token action
```

### Manifest-Based Creation

The manifest can be used programmatically:

```powershell
# Read manifest
$manifest = Get-Content .github/app-manifest.json | ConvertFrom-Json

# Display for manual entry or automation
$manifest | ConvertTo-Json -Depth 10
```

---

## Best Practices

### Security

1. ✅ **Never commit private keys**: Store only in GitHub secrets
2. ✅ **Use minimum required permissions**: Only enable what's needed
3. ✅ **Rotate keys periodically**: Delete old keys, generate new ones
4. ✅ **Validate configuration regularly**: Use validation script

### Automation

1. ✅ **Use manifest for consistency**: Ensures identical configuration
2. ✅ **Document configuration**: Keep backup of app settings
3. ✅ **Test in development first**: Validate setup before production
4. ✅ **Use validation script**: Before and after changes

### Maintenance

1. ✅ **Regular validation**: Run validation script monthly
2. ✅ **Monitor workflow failures**: Check for authentication issues
3. ✅ **Keep documentation updated**: Note any configuration changes
4. ✅ **Review app permissions**: Ensure they match requirements

---

## Conclusion

While GitHub App creation requires some manual steps, this automation framework:
- ✅ **Streamlines setup**: Manifest-based configuration
- ✅ **Automates secrets**: Full automation after initial setup
- ✅ **Provides validation**: Automated configuration checking
- ✅ **Enables recreation**: Easy delete and recreate process
- ✅ **Documents configuration**: Declarative manifest

The result is a **reproducible, validated, and well-documented** GitHub App setup that can be easily recreated if needed.

---

## Quick Reference

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-github-app-from-manifest.ps1` | Guide app creation using manifest |
| `scripts/validate-github-app-config.ps1` | Validate app configuration |

### Files

| File | Purpose |
|------|---------|
| `.github/app-manifest.json` | Declarative app configuration |
| `.github/workflows/azure-bootstrap.yml` | Automated secret management |

### URLs

| Resource | URL |
|----------|-----|
| Create App | https://github.com/settings/apps/new |
| Manage Apps | https://github.com/settings/apps |
| Installations | https://github.com/settings/installations |
| Repository Secrets | https://github.com/[owner]/[repo]/settings/secrets/actions |

---

**Last Updated**: 2026-01-27
**Version**: 1.0
