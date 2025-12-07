# Key Vault OIDC Token Expiration - Issue Resolution

## Issue Summary

**Problem**: The Azure Bootstrap workflow for the `dev` environment was failing when attempting to populate Key Vault secrets with the following error:

```
ERROR: AADSTS700024: Client assertion is not within its valid time range. 
Current time: 2025-12-07T21:07:56.8910557Z, 
assertion valid from 2025-12-07T20:56:03.0000000Z, 
expiry time of assertion 2025-12-07T21:01:03.0000000Z.
```

**Root Cause**: OIDC tokens issued by GitHub Actions have a 5-minute validity period. The workflow sequence for the dev environment was:

1. Initial Azure Login using OIDC (20:56:03 UTC)
2. Bootstrap Infrastructure (~3 minutes)
3. Provision SQL Database with 5-minute firewall propagation wait (~6 minutes)
4. Run Database Migrations (~2 minutes)
5. **Populate Key Vault Secrets** (21:07:56 UTC - **Token Expired!**)

Total time: ~11 minutes from initial login, but token only valid for 5 minutes.

## Failed Workflow Reference

- **Run ID**: 20009395486
- **Job ID**: 57378511655
- **Link**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/20009395486/job/57378511655
- **Commit**: `6c57f114214ee3665b51065c5e0e7e31f12d56bf` (before fix was applied)
- **Date**: 2025-12-07 21:08:05 UTC

## Resolution

The fix was already implemented in **Pull Request #63** and is present in the current `dev` branch.

### Changes Made

Added two steps before the "Populate Key Vault Secrets" step in the dev environment bootstrap job:

#### 1. Clear Azure CLI Token Cache (Lines 1970-1988)

```yaml
- name: Clear Azure CLI Token Cache
  run: |
    Write-Host "🔄 Clearing Azure CLI token cache to force fresh authentication..." -ForegroundColor Cyan
    try {
      # Clear Azure account to force re-authentication
      az account clear 2>&1 | Out-Null
      Write-Host "  ✓ Azure account cleared" -ForegroundColor Gray
      
      # Purge Azure CLI cache
      az cache purge 2>&1 | Out-Null
      Write-Host "  ✓ Azure CLI cache purged" -ForegroundColor Gray
      
      Write-Host "✅ Token cache cleared successfully" -ForegroundColor Green
    }
    catch {
      # Cache clearing failure is not critical - log and continue
      Write-Host "  ⚠️  Cache clearing encountered an issue (non-critical): $($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host "  Proceeding with Azure login refresh..." -ForegroundColor Gray
    }
```

#### 2. Refresh Azure Login for Key Vault Operations (Lines 1990-1996)

```yaml
- name: Refresh Azure Login for Key Vault Operations
  timeout-minutes: 3
  uses: azure/login@v2
  with:
    client-id: ${{ env.CLIENT_ID }}
    tenant-id: ${{ env.TENANT_ID }}
    subscription-id: ${{ env.SUBSCRIPTION_ID }}
```

### Why This Works

1. **Token Refresh**: Generates a fresh OIDC token just before Key Vault operations
2. **Cache Clearing** (Dev Only): Ensures Azure CLI doesn't use stale cached tokens in the dev environment
3. **Consistent Pattern**: All three environments now have token refresh before Key Vault operations
4. **Safety Net**: Dev environment includes error handling for non-critical cache clearing failures

**Note**: The dev environment has an additional "Clear Azure CLI Token Cache" step that staging and prod do not have. This extra step provides additional robustness but is not strictly required - the token refresh alone is sufficient to resolve the issue.

## Verification

The token refresh fix has been verified to be present in all environments:

- **Dev Environment**: 
  - Cache Clear: Line 1970 of `.github/workflows/azure-bootstrap.yml`
  - Token Refresh: Line 1990 of `.github/workflows/azure-bootstrap.yml`
- **Staging Environment**: 
  - Token Refresh: Line 2426 of `.github/workflows/azure-bootstrap.yml`
- **Production Environment**: 
  - Token Refresh: Line 2926 of `.github/workflows/azure-bootstrap.yml`

**Note**: Only the dev environment includes the cache clearing step. Staging and prod environments only have the token refresh step, which is sufficient to resolve the token expiration issue.

## Timeline

- **Issue Occurred**: 2025-12-07 21:08:05 UTC (Workflow Run 20009395486)
- **Fix Applied**: Pull Request #63
- **Current Status**: ✅ **RESOLVED** - Fix is in the `dev` branch (commit `9fd0f67`)

## Related Documentation

- GitHub Actions OIDC Token Lifespan: 5 minutes
- Azure AD Token Expiration: [Microsoft Documentation](https://learn.microsoft.com/entra/identity-platform/certificate-credentials)
- Workflow File: `.github/workflows/azure-bootstrap.yml`

## Impact

This fix prevents token expiration errors during long-running bootstrap workflows and ensures reliable Key Vault secret population across all environments.

Future workflow runs will automatically refresh the OIDC token before Key Vault operations, eliminating the AADSTS700024 error.
