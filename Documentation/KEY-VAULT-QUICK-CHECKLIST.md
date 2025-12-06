# Key Vault Setup - Quick Verification Checklist

This is a quick reference checklist for verifying the Key Vault setup from PR#54 and PR#5. For detailed instructions, see [KEY-VAULT-VERIFICATION-GUIDE.md](KEY-VAULT-VERIFICATION-GUIDE.md).

## Quick Start

Run the automated verification script:

**PowerShell:**
```powershell
.\Scripts\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
```

**Bash:**
```bash
./Scripts/verify-keyvault-setup.sh rg-orderprocessing-dev dev
```

## Manual Verification Checklist

### ☑️ Azure Portal Checks

#### 1. Key Vault Existence
- [ ] Navigate to Azure Portal
- [ ] Search for "Key Vaults"
- [ ] Verify `kv-orderproc-dev` (or `kv-orderproc-{environment}`) exists
- [ ] Check it's in the correct resource group: `rg-orderprocessing-{environment}`

#### 2. Key Vault Configuration
- [ ] **Properties Tab**
  - [ ] Pricing Tier: Standard
  - [ ] Soft Delete: Enabled
  - [ ] Soft Delete Retention: 90 days
  - [ ] Vault URI: `https://kv-orderproc-{environment}.vault.azure.net/`

- [ ] **Access Policies Tab**
  - [ ] At least one policy exists for the App Service managed identity
  - [ ] Identity has "Get" permission for secrets
  - [ ] Identity has "List" permission for secrets

- [ ] **Secrets Tab**
  - [ ] `OpenPayAdapter--ApiKey` exists
  - [ ] `ApplicationInsights--ConnectionString` exists

- [ ] **Tags Tab**
  - [ ] `environment`: {environment-name}
  - [ ] `app`: orderprocessing

#### 3. App Service Integration
- [ ] Navigate to App Service: `{owner}-orderprocessing-api-xyapp-{environment}`
- [ ] **Identity Tab**
  - [ ] System-assigned managed identity: **On**
  - [ ] Object (principal) ID is displayed

- [ ] **Configuration → Application Settings Tab**
  - [ ] Key Vault references present (format: `@Microsoft.KeyVault(SecretUri=...)`)
  - [ ] References show green checkmark (resolved successfully)
  - [ ] Key settings to verify:
    - [ ] `OpenPayAdapter__ApiKey` (or similar)
    - [ ] `APPLICATIONINSIGHTS_CONNECTION_STRING`

#### 4. Application Verification
- [ ] **Test Endpoints**
  - [ ] App Service URL is accessible: `https://{app-name}.azurewebsites.net`
  - [ ] Health check endpoint works (if available): `/api/health`
  - [ ] No configuration errors in logs

- [ ] **Application Insights**
  - [ ] Navigate to Application Insights resource
  - [ ] Open "Live Metrics" 
  - [ ] Verify telemetry is being received
  - [ ] Check for configuration errors in logs

- [ ] **App Service Logs**
  - [ ] Navigate to App Service → Log stream
  - [ ] Look for successful configuration load messages
  - [ ] Verify no Key Vault access errors
  - [ ] Example expected log: `[CONFIG] Application Insights enabled for dev environment`

### ☑️ PR#54 Changes Verification

#### Changes Made in PR#54
- [ ] **Bicep Template** (if exists in your repo: `bicep/appservice-with-kv.bicep`)
  - [ ] Key Vault is created (not referenced as `existing`)
  - [ ] Soft delete enabled with 90-day retention
  - [ ] Access policies configured for managed identity

- [ ] **Documentation Updated**
  - [ ] `bicep/README.md` reflects automatic Key Vault creation
  - [ ] Prerequisites no longer require manual Key Vault creation
  - [ ] Post-deployment secret population instructions included

- [ ] **Workflow Updated**
  - [ ] `.github/workflows/deploy-and-verify.yml` (if exists)
  - [ ] Error messages updated to reflect automatic creation
  - [ ] No longer mentions "create Key Vault before deployment"

- [ ] **Deployment Success**
  - [ ] Check workflow run: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/19994518481
  - [ ] Status: Completed successfully
  - [ ] Key Vault was created during deployment

### ☑️ PR#5 Changes Verification

#### Changes Made in PR#5
- [ ] **Workflow File** (`.github/workflows/azure-bootstrap.yml`)
  - [ ] No references to `secrets.GH_PAT`
  - [ ] Uses `secrets.GITHUB_TOKEN` instead
  - [ ] Has `permissions: secrets: write`
  - [ ] Validation checks for GH_PAT removed

- [ ] **GitHub Environment Secrets**
  - [ ] Navigate to: GitHub Repo → Settings → Environments
  - [ ] Select environment (dev/staging/prod)
  - [ ] Verify auto-generated secrets exist:
    - [ ] `AZURE_CLIENT_ID`
    - [ ] `AZURE_SUBSCRIPTION_ID`
    - [ ] `AZURE_TENANT_ID`

- [ ] **Workflow Execution**
  - [ ] Check recent workflow runs: https://github.com/{owner}/{repo}/actions
  - [ ] Azure Bootstrap workflow runs without manual PAT errors
  - [ ] No "GH_PAT missing" error messages

## Common Issues and Quick Fixes

### Issue: Key Vault References Show Red Icon

**Quick Fix:**
```bash
# Get App Service principal ID
PRINCIPAL_ID=$(az webapp identity show --name {app-name} --resource-group {rg-name} --query principalId -o tsv)

# Grant Key Vault access
az keyvault set-policy --name {kv-name} --object-id $PRINCIPAL_ID --secret-permissions get list

# Restart App Service
az webapp restart --name {app-name} --resource-group {rg-name}
```

### Issue: Secrets Missing in Key Vault

**Quick Fix:**
```bash
# Add OpenPayAdapter ApiKey
az keyvault secret set --vault-name {kv-name} \
  --name "OpenPayAdapter--ApiKey" \
  --value "your-api-key-here"

# Add Application Insights Connection String
az keyvault secret set --vault-name {kv-name} \
  --name "ApplicationInsights--ConnectionString" \
  --value "InstrumentationKey=...;IngestionEndpoint=..."
```

### Issue: Application Not Reading Secrets

**Checklist:**
- [ ] App Settings use correct format: `@Microsoft.KeyVault(SecretUri=https://{vault}.vault.azure.net/secrets/{secret-name}/)`
- [ ] Secret names use double dash in Key Vault: `OpenPayAdapter--ApiKey`
- [ ] App Settings use double underscore: `OpenPayAdapter__ApiKey`
- [ ] App Service has been restarted after configuration changes
- [ ] Managed Identity has Get and List permissions on Key Vault

## Azure CLI Quick Commands

### Check Key Vault
```bash
az keyvault show --name kv-orderproc-dev --resource-group rg-orderprocessing-dev
```

### List Secrets
```bash
az keyvault secret list --vault-name kv-orderproc-dev --query "[].name" -o table
```

### Check App Service Identity
```bash
az webapp identity show --name {app-name} --resource-group {rg-name}
```

### Check Key Vault Access Policies
```bash
az keyvault show --name kv-orderproc-dev --query "properties.accessPolicies"
```

### Check App Service Configuration
```bash
az webapp config appsettings list --name {app-name} --resource-group {rg-name} \
  --query "[?contains(value, '@Microsoft.KeyVault')]" -o table
```

## PowerShell Quick Commands

### Check Key Vault
```powershell
Get-AzKeyVault -ResourceGroupName "rg-orderprocessing-dev" -VaultName "kv-orderproc-dev"
```

### List Secrets
```powershell
Get-AzKeyVaultSecret -VaultName "kv-orderproc-dev" | Select-Object Name
```

### Check App Service Identity
```powershell
$webapp = Get-AzWebApp -ResourceGroupName "{rg-name}" -Name "{app-name}"
$webapp.Identity
```

### Check App Service Configuration
```powershell
$config = Get-AzWebApp -ResourceGroupName "{rg-name}" -Name "{app-name}"
$config.SiteConfig.AppSettings | Where-Object { $_.Value -like "*@Microsoft.KeyVault*" }
```

## Verification Status Summary

After completing all checks, fill in your status:

**Environment:** ___________________

| Category | Status | Notes |
|----------|--------|-------|
| Key Vault Exists | ⬜ Pass ⬜ Fail | |
| Soft Delete Enabled | ⬜ Pass ⬜ Fail | |
| Required Secrets | ⬜ Pass ⬜ Fail | |
| Managed Identity | ⬜ Pass ⬜ Fail | |
| Key Vault Access | ⬜ Pass ⬜ Fail | |
| App Settings References | ⬜ Pass ⬜ Fail | |
| Application Working | ⬜ Pass ⬜ Fail | |

**Overall Status:** ⬜ Success ⬜ Needs Attention ⬜ Failed

**Verified By:** ___________________  
**Date:** ___________________

## Next Steps

- [ ] Complete verification for all environments (dev, staging, prod)
- [ ] Document any environment-specific configurations
- [ ] Set up monitoring and alerts for Key Vault access
- [ ] Create runbook for secret rotation
- [ ] Update team documentation with findings

## Resources

- **Detailed Guide:** [KEY-VAULT-VERIFICATION-GUIDE.md](KEY-VAULT-VERIFICATION-GUIDE.md)
- **Automated Scripts:** 
  - PowerShell: `Scripts/Verify-KeyVaultSetup.ps1`
  - Bash: `Scripts/verify-keyvault-setup.sh`
- **PR#54:** Fix Key Vault parent resource error by creating vault
- **PR#5:** Remove manual GH_PAT requirement from Azure Bootstrap workflow
- **Workflow Run:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/19994518481
