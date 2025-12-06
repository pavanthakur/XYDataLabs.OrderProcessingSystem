# Key Vault Setup Verification - Quick Start

This document helps you verify the Azure Key Vault setup from PR#54 and GitHub workflow automation from PR#5.

## 🚀 Quick Start

### Option 1: Automated Verification (Recommended)

Run the verification script to check everything automatically:

**PowerShell:**
```powershell
cd Scripts
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
```

**Bash/Azure CLI:**
```bash
cd Scripts
./verify-keyvault-setup.sh rg-orderprocessing-dev dev
```

The script will:
- ✅ Check if Key Vault exists and is properly configured
- ✅ Verify required secrets are present
- ✅ Validate App Service managed identity
- ✅ Check Key Vault access policies
- ✅ Verify App Settings reference Key Vault correctly
- ✅ Provide remediation commands for any issues

### Option 2: Manual Verification

Follow the step-by-step guide:
1. Open [Documentation/PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md)
2. Follow the Azure Portal verification steps
3. Check the application integration sections

## 📋 Your Questions Answered

### 1. What should I verify on Azure Portal?

**Quick Checklist:**
- [ ] Key Vault `kv-orderproc-dev` exists in `rg-orderprocessing-dev`
- [ ] Soft Delete is enabled (90-day retention)
- [ ] Secrets exist: `OpenPayAdapter--ApiKey`, `ApplicationInsights--ConnectionString`
- [ ] App Service has system-assigned managed identity enabled
- [ ] Managed identity has Get/List permissions on Key Vault
- [ ] App Settings show Key Vault references with green checkmarks

**Detailed Instructions:** See [Documentation/PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md#1-what-should-i-verify-on-azure-portal-related-to-key-vault)

### 2. How to verify application is using Key Vault values?

**6 Verification Methods:**
1. Check App Service Configuration status (green checkmarks)
2. Review Application Logs for Key Vault errors
3. Check Application Insights telemetry
4. Run automated verification script
5. Test direct secret access with managed identity
6. Check Key Vault diagnostic logs

**Detailed Instructions:** See [Documentation/PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md#2-how-can-i-check-and-verify-the-application-is-using-values-from-key-vault)

### 3. What to verify from PR#5 and PR#54?

**PR#54 (Key Vault Creation):**
- [ ] Key Vault created automatically during deployment
- [ ] Soft delete with 90-day retention
- [ ] Access policies configured for managed identity
- [ ] Deployment workflow completed successfully

**PR#5 (GitHub Workflow Automation):**
- [ ] Workflow uses `GITHUB_TOKEN` (no manual PAT needed)
- [ ] Environment secrets auto-generated
- [ ] Azure Bootstrap workflow runs without errors

**Detailed Instructions:** See [Documentation/PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md#3-what-additional-things-should-i-verify-from-pr5-and-pr54)

## 📚 Documentation Resources

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md)** | Direct answers to your questions | **START HERE** |
| **[KEY-VAULT-VERIFICATION-GUIDE.md](Documentation/KEY-VAULT-VERIFICATION-GUIDE.md)** | Comprehensive verification guide | Detailed steps, troubleshooting |
| **[KEY-VAULT-QUICK-CHECKLIST.md](Documentation/KEY-VAULT-QUICK-CHECKLIST.md)** | Quick reference checklist | Daily operations |
| **[Scripts/README.md](Scripts/README.md)** | Script usage documentation | Running verification scripts |

## 🔧 Common Issues & Quick Fixes

### Issue: Key Vault References Show Red (Not Resolved)

**Quick Fix:**
```bash
# Grant Key Vault access to App Service
PRINCIPAL_ID=$(az webapp identity show --name {app-name} --resource-group {rg-name} --query principalId -o tsv)
az keyvault set-policy --name kv-orderproc-dev --object-id $PRINCIPAL_ID --secret-permissions get list
az webapp restart --name {app-name} --resource-group {rg-name}
```

### Issue: Secrets Missing in Key Vault

**Quick Fix:**
```bash
# Add OpenPayAdapter ApiKey
az keyvault secret set --vault-name kv-orderproc-dev --name "OpenPayAdapter--ApiKey" --value "your-api-key"

# Add Application Insights Connection String  
az keyvault secret set --vault-name kv-orderproc-dev --name "ApplicationInsights--ConnectionString" --value "InstrumentationKey=xxx;..."
```

### Issue: Application Not Reading Key Vault Values

**Checklist:**
1. App Settings format: `@Microsoft.KeyVault(SecretUri=https://...)`
2. Managed identity enabled and has permissions
3. App Service restarted after configuration changes
4. Secrets exist in Key Vault

**More Solutions:** See [Documentation/KEY-VAULT-VERIFICATION-GUIDE.md#troubleshooting](Documentation/KEY-VAULT-VERIFICATION-GUIDE.md#troubleshooting)

## 📍 What PR#54 Created

**Workflow Run:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/19994518481

**Resources Created:**
- ✅ Azure Key Vault (`kv-orderproc-dev`)
  - Standard SKU
  - Soft delete enabled (90-day retention)
  - Access policies for App Service managed identity
- ✅ App Service with System-Assigned Managed Identity
- ✅ Access policy granting Get/List permissions on secrets

**What You Need to Do:**
- Populate the required secrets (scripts will remind you)
- Verify the setup using the provided scripts/documentation

## 📍 What PR#5 Changed

**Changes:**
- ✅ Removed manual Personal Access Token (GH_PAT) requirement
- ✅ Workflow now uses automatic `GITHUB_TOKEN`
- ✅ Zero manual configuration needed

**What to Verify:**
- GitHub workflow runs without PAT errors
- Environment secrets auto-generated
- No manual token setup required

## ⚡ Next Steps

1. **Run Verification Script**
   ```powershell
   cd Scripts
   .\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
   ```

2. **Review Results**
   - If all checks pass: ✅ You're done!
   - If issues found: Follow the remediation commands provided

3. **Populate Missing Secrets** (if needed)
   - The script will tell you exactly which secrets are missing
   - Follow the provided commands to add them

4. **Verify Other Environments**
   - Repeat for staging and production environments
   - Use the same scripts with different environment parameters

5. **Set Up Monitoring** (Optional)
   - Enable Key Vault diagnostic logs
   - Set up alerts for secret access failures
   - Schedule regular verification runs

## 🆘 Need Help?

1. **Quick answers:** [PR-54-AND-PR-5-SUMMARY.md](Documentation/PR-54-AND-PR-5-SUMMARY.md)
2. **Detailed guide:** [KEY-VAULT-VERIFICATION-GUIDE.md](Documentation/KEY-VAULT-VERIFICATION-GUIDE.md)
3. **Troubleshooting:** [KEY-VAULT-VERIFICATION-GUIDE.md#troubleshooting](Documentation/KEY-VAULT-VERIFICATION-GUIDE.md#troubleshooting)
4. **Script help:** Run `.\Verify-KeyVaultSetup.ps1 -Help` or check [Scripts/README.md](Scripts/README.md)

## 📊 Verification Status Template

Use this to track your verification progress:

```
Environment: _______________
Date: _______________
Verified by: _______________

Key Vault Configuration:
[ ] Key Vault exists
[ ] Soft delete enabled (90 days)
[ ] Required secrets present
[ ] Access policies configured

App Service Integration:
[ ] Managed identity enabled
[ ] Key Vault access granted
[ ] App Settings reference Key Vault
[ ] References show green status

Application Verification:
[ ] Application starts without errors
[ ] No Key Vault access errors in logs
[ ] Application Insights receiving data
[ ] Application functioning correctly

Overall Status: [ ] Pass  [ ] Fail  [ ] Needs Attention
Notes: _______________________
```

---

**Related PRs:**
- PR#54: Fix Key Vault parent resource error by creating vault instead of referencing existing
- PR#5: Remove manual GH_PAT requirement from Azure Bootstrap workflow
