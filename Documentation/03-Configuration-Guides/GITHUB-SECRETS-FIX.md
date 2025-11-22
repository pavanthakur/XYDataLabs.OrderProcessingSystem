# GitHub Secrets Configuration Fix

## Problem Statement

The Azure Bootstrap workflow was failing with HTTP 403 error when attempting to set repository secrets:

```
failed to fetch public key: HTTP 403: Resource not accessible by integration 
(https://api.github.com/repos/.../actions/secrets/public-key)
Error: Failed to set AZUREAPPSERVICE_CLIENTID
```

## Root Cause

**GitHub Actions `GITHUB_TOKEN` does not have permission to create or update repository secrets.** This is a security limitation by design - the automatically provided `GITHUB_TOKEN` can only *read* secrets, not write them.

The workflow was incorrectly using `GITHUB_TOKEN` to set repository secrets via the `gh secret set` command.

## Why AZUREAPPSERVICE_CLIENTID is Required

These Azure credentials ARE necessary for the deployment workflows:
- **AZUREAPPSERVICE_CLIENTID** - Azure AD application client ID for OIDC authentication
- **AZUREAPPSERVICE_TENANTID** - Azure AD tenant ID
- **AZUREAPPSERVICE_SUBSCRIPTIONID** - Azure subscription ID

They are used by:
1. `deploy-api-to-azure.yml` (line 84) - for Azure login during API deployment
2. `deploy-ui-to-azure.yml` - for Azure login during UI deployment  
3. `infra-deploy.yml` (line 93) - for infrastructure deployment
4. Bootstrap jobs - for initial infrastructure setup

Without these secrets, the workflows cannot authenticate with Azure to deploy resources.

## Solution

Changed the workflow to use a **Personal Access Token (PAT)** with `repo` scope instead of `GITHUB_TOKEN`:

### Changes Made

1. **Set Repository Secrets step** (lines 392-424):
   - Changed from `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to `GH_PAT: ${{ secrets.GH_PAT }}`
   - Added check for GH_PAT availability before attempting to set secrets
   - If GH_PAT not available, provides clear instructions for manual secret configuration
   - Sets `$env:GH_TOKEN = $env:GH_PAT` to use PAT for gh CLI authentication

2. **Check Required Secrets step** (lines 359-383):
   - Changed to check for GH_PAT instead of GITHUB_TOKEN
   - Shows authentication method and capabilities (read-only vs can set secrets)

3. **Log Token Availability step** (lines 385-391):
   - Renamed from "Log GitHub Token Availability"
   - Now checks for GH_PAT and provides guidance if missing

4. **Verify Repository Secrets step** (lines 507-566):
   - Falls back to GITHUB_TOKEN for read-only verification if GH_PAT unavailable
   - Removed misleading message about GITHUB_TOKEN being sufficient

5. **Create Setup Summary step** (lines 318-330):
   - Updated to provide clear instructions for both automated (with PAT) and manual approaches
   - Explains PAT setup process step-by-step

## How to Use

### Option 1: Automated Secret Configuration (Recommended)

1. **Create a GitHub Personal Access Token (PAT)**:
   - Go to: https://github.com/settings/tokens/new
   - Select scopes: `repo` (Full control of private repositories)
   - Generate and copy the token

2. **Add PAT as Repository Secret**:
   - Go to: https://github.com/[your-org]/[your-repo]/settings/secrets/actions/new
   - Name: `GH_PAT`
   - Value: [paste your PAT token]
   - Click "Add secret"

3. **Run Azure Bootstrap Workflow**:
   - Go to Actions > Azure Bootstrap Setup
   - Select "Configure GitHub secrets" = true
   - The workflow will automatically set AZUREAPPSERVICE_* secrets

### Option 2: Manual Secret Configuration

If you don't want to use a PAT, manually add these secrets:

1. Go to: https://github.com/[your-org]/[your-repo]/settings/secrets/actions
2. Add these three secrets (values from OIDC setup output):
   - `AZUREAPPSERVICE_CLIENTID`
   - `AZUREAPPSERVICE_TENANTID`
   - `AZUREAPPSERVICE_SUBSCRIPTIONID`

## Security Considerations

### Why PAT is Safe

- PAT is stored as an encrypted GitHub secret
- PAT is only accessible to workflows with proper permissions
- PAT can be scoped to specific repositories and permissions
- PAT can be revoked at any time from GitHub settings

### PAT Scope Requirements

The PAT only needs the `repo` scope, which grants:
- Read/write access to repository code
- Read/write access to repository secrets
- Read/write access to repository settings

This is necessary because the workflow needs to write secrets to the repository.

### Alternative: GitHub App

For enterprise scenarios, consider using a GitHub App instead of PAT:
- More granular permissions
- Better audit trail
- Can be installed organization-wide
- Automatic token rotation

## Testing

To verify the fix works:

1. Remove existing AZUREAPPSERVICE_* secrets
2. Ensure GH_PAT secret is configured
3. Run Azure Bootstrap workflow with:
   - Setup OIDC = false (use existing OIDC app)
   - Configure GitHub secrets = true
   - Bootstrap infrastructure = false
4. Verify secrets are created successfully
5. Check job summary shows green checkmarks

## Related Files

- `.github/workflows/azure-bootstrap.yml` - Main bootstrap workflow
- `.github/workflows/deploy-api-to-azure.yml` - Uses AZUREAPPSERVICE_* secrets
- `.github/workflows/deploy-ui-to-azure.yml` - Uses AZUREAPPSERVICE_* secrets
- `.github/workflows/infra-deploy.yml` - Uses AZUREAPPSERVICE_* secrets
- `Resources/Azure-Deployment/configure-github-secrets.ps1` - PowerShell script for local secret configuration

## Troubleshooting

### Error: "GH_PAT secret not configured"

**Solution**: Follow Option 1 steps above to create and add a PAT.

### Error: "Failed to set AZUREAPPSERVICE_CLIENTID" with GH_PAT

**Possible causes**:
1. PAT doesn't have `repo` scope - regenerate with correct scope
2. PAT has expired - create a new PAT
3. PAT is for wrong account - ensure PAT is from account with write access to repository

### Secrets show as set but workflows can't read them

**Solution**: 
- Secrets are encrypted and can't be read directly
- Check workflow logs to see if secrets are being passed correctly
- Verify secret names match exactly (case-sensitive)

## Migration Guide

If you were relying on the old (broken) behavior:

1. **Immediate action**: Add GH_PAT secret or manually configure AZUREAPPSERVICE_* secrets
2. **Update documentation**: Inform team members about PAT requirement
3. **Update CI/CD docs**: Add PAT setup to onboarding documentation
4. **Consider automation**: Use `configure-github-secrets.ps1` for local setup

## References

- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [GitHub Secrets API](https://docs.github.com/en/rest/actions/secrets)
- [Azure OIDC with GitHub Actions](https://docs.microsoft.com/en-us/azure/developer/github/connect-from-azure)
