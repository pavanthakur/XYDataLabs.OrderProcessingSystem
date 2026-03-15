# Troubleshooting Guide Index

Quick links to troubleshooting guides for common issues with the Azure Bootstrap workflow.

## 🚨 Common Issues

### GitHub App / Authentication Issues

#### ❌ "Not Found - GitHub App Token Generation Failed (404)"
**Error**: `Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 1-4): Not Found`

**Cause**: GitHub App is not installed on this repository

**Solution**: [TROUBLESHOOTING-GITHUB-APP-404.md](./TROUBLESHOOTING-GITHUB-APP-404.md)

**Quick Fix**:
1. Go to https://github.com/settings/installations
2. Configure your GitHub App
3. Add `XYDataLabs.OrderProcessingSystem` to repository access
4. Re-run workflow

---

#### ❌ "APP_ID and APP_PRIVATE_KEY Showing as Missing"
**Error**: 
```
APP_ID                : ❌ Missing
APP_PRIVATE_KEY       : ❌ Missing
```

**Cause**: Workflow not running in environment context, looking for repository secrets instead of environment secrets

**Solution**: [TROUBLESHOOTING-APP-SECRETS-MISSING.md](./TROUBLESHOOTING-APP-SECRETS-MISSING.md)

**Quick Fix**:
1. Run workflow with specific environment selected (dev/staging/prod)
2. Don't select "all" if using environment secrets
3. Ensure workflow has latest changes with environment context

---

#### ℹ️ "What is APP_INSTALLATION_ID?"
**Question**: Do I need to configure APP_INSTALLATION_ID as a secret?

**Answer**: **No!** Installation ID is automatically discovered at runtime.

**Details**: [APP_INSTALLATION_ID_EXPLAINED.md](./APP_INSTALLATION_ID_EXPLAINED.md)

---

### Workflow Update Issues

#### ⚠️ "Workflow Update Requires Manual Action"
**Error**: `refusing to allow a GitHub App to create or update workflow without 'workflows' permission`

**Cause**: GITHUB_TOKEN lacks permission to modify workflow files (security feature)

**Solution**: Manual one-time edit required

**Quick Fix**:
1. Edit `.github/workflows/infra-deploy.yml`
2. Change `if: false  # TODO: Enable after bootstrap` to `if: (github.event_name == 'push') || ...`
3. Uncomment `needs: pre-validate`
4. Commit and push

**Alternative**: Grant your GitHub App "Workflows: Read and write" permission (advanced)

---

### Azure OIDC Issues

#### ❌ "Azure Login Failed"
**Error**: Azure CLI login timeout or authentication failure

**Cause**: Device code not entered within timeout window

**Quick Fix**:
1. Re-run workflow with "Setup Azure OIDC" enabled
2. Complete device code authentication within 3 minutes
3. Ensure you have proper Azure permissions

---

#### ❌ "OIDC App Not Found"
**Error**: `Failed to create or find OIDC app 'GitHub-Actions-OIDC'`

**Cause**: OIDC setup script failed or insufficient Azure AD permissions

**Quick Fix**:
1. Verify you have Application Administrator role in Azure AD
2. Check Azure CLI is authenticated: `az account show`
3. Re-run workflow with "Setup Azure OIDC" enabled
4. Review OIDC setup logs

---

## 📚 Setup Guides

### Initial Setup
- [QUICK-SETUP-GITHUB-APP.md](./Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md) - 4-minute GitHub App setup
- [GITHUB-APP-AUTHENTICATION.md](./Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md) - Detailed authentication guide
- [GITHUB-APP-AUTO-DISCOVERY.md](./GITHUB-APP-AUTO-DISCOVERY.md) - How auto-discovery works (2 secrets instead of 3)

### Configuration Confirmation
- [SETUP-CONFIRMATION.md](./SETUP-CONFIRMATION.md) - Verify your setup is correct
- [EVALUATION-AZURE-BOOTSTRAP-RESTORATION.md](./EVALUATION-AZURE-BOOTSTRAP-RESTORATION.md) - Azure bootstrap evaluation

---

## 🔍 How to Use This Index

1. **Find your error message** in the sections above
2. **Click the link** to the detailed troubleshooting guide
3. **Follow the Quick Fix** or read the full solution
4. **Re-run the workflow** after applying the fix

---

## 📖 Understanding the Workflow

### Workflow Steps
1. **Validate Inputs** - Check configuration
2. **Setup Azure OIDC** (optional) - First-time Azure authentication setup
3. **Setup GitHub App** (optional) - One-time GitHub App setup instructions
4. **Configure Secrets** - Auto-configure GitHub secrets using GitHub App
5. **Bootstrap Infrastructure** - Deploy Azure resources
6. **Enable Validation** (optional) - Enable pre-deployment checks

### Prerequisites Validation
The workflow checks:
- ✅ OIDC setup completed (if enabled)
- ✅ GitHub App secrets present (APP_ID, APP_PRIVATE_KEY)
- ✅ GitHub App installed on repository
- ✅ GitHub App permissions (Secrets: Read and write)

### Common Failure Points
1. **Step 2 (Generate GitHub App Token)** → App not installed → See [TROUBLESHOOTING-GITHUB-APP-404.md](./TROUBLESHOOTING-GITHUB-APP-404.md)
2. **Step 5 (Enable Validation)** → Manual workflow edit required → Follow on-screen instructions
3. **Step 1 (Azure Login)** → Device code timeout → Re-run with "Setup OIDC" enabled

---

## 🆘 Still Having Issues?

If your issue isn't covered here:

1. **Check workflow logs**: Actions → Azure Bootstrap Setup → Failed run → View logs
2. **Review error messages**: Workflow provides detailed troubleshooting in failed steps
3. **Verify setup**: Compare your setup against [SETUP-CONFIRMATION.md](./SETUP-CONFIRMATION.md)
4. **Check documentation**: Browse [Documentation/03-Configuration-Guides/](./Documentation/03-Configuration-Guides/)

---

## ✅ Success Indicators

You'll know everything is working when:

✅ **Step 1**: Prerequisite validation shows all checks passing
```
✅ OIDC credentials available
✅ All required GitHub App secrets detected
```

✅ **Step 2**: Token generation succeeds
```
✅ Status: AUTHENTICATED
ℹ️  Token: Generated (expires in 1 hour)
```

✅ **Step 3**: Secrets configured
```
✅ All repository secrets configured successfully!
✅ All environment secrets configured successfully!
```

✅ **Step 4**: Infrastructure deployed
```
✅ DEV INFRASTRUCTURE BOOTSTRAP COMPLETE
```

---

## 📋 Quick Checklist

Before running the workflow:
- [ ] GitHub App created at https://github.com/settings/apps
- [ ] GitHub App installed at https://github.com/settings/installations
- [ ] GitHub App has "Secrets: Read and write" permission
- [ ] Repository `XYDataLabs.OrderProcessingSystem` selected in installation
- [ ] `APP_ID` secret configured (repository or environment)
- [ ] `APP_PRIVATE_KEY` secret configured (full .pem file contents)
- [ ] Environment secrets: Select specific environment (dev/staging/prod) in workflow
- [ ] Azure CLI access (for first-time OIDC setup)

After successful run:
- [ ] Review workflow summary for any warnings
- [ ] Verify Azure secrets configured: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
- [ ] Check Azure resources in portal: https://portal.azure.com
- [ ] Enable validation if not done automatically (one-time manual step)

---

## 🛡️ Preventing Configuration Copy-Paste Errors

### The Problem
A critical copy-paste error on this project resulted in `bootstrap-dev` being accidentally configured with prod environment settings — it would have deployed prod resources when dev was selected.

### Manual Verification Checklist (After Any Workflow Edit)
- [ ] `bootstrap-dev` calls `-Environment dev` and logs show `dev.json`
- [ ] `bootstrap-staging` calls `-Environment staging` and logs show `staging.json`
- [ ] `bootstrap-prod` calls `-Environment prod` and logs show `prod.json`
- [ ] OIDC setup uses `${{ inputs.environment }}` (dynamic, not hardcoded)
- [ ] Configure-secrets uses `${{ inputs.environment }}`

### Automated Fix
```powershell
# Run EVERY TIME before committing workflow changes
./Resources/Azure-Deployment/validate-workflow-config.ps1
# Exit Code 0 = ✅ Safe to commit | Exit Code 1 = ❌ Fix first
```

### Safe Commit Pattern
```powershell
# After each environment change (don't batch):
./Resources/Azure-Deployment/validate-workflow-config.ps1
git add .github/workflows/
git commit -m "fix: Update bootstrap-dev configuration"
```

---

## ❌ GitHub Secrets 403 Error (GITHUB_TOKEN Limitation)

### Error
```
failed to fetch public key: HTTP 403: Resource not accessible by integration
Error: Failed to set AZUREAPPSERVICE_CLIENTID
```

### Root Cause
`GITHUB_TOKEN` is read-only for secrets — it **cannot** write repository secrets. This is a GitHub security design. The workflow must use a **Personal Access Token (PAT)** with `repo` scope instead.

### Solution
1. Create a PAT at https://github.com/settings/tokens/new (scope: `repo`)
2. Add it as repository secret named `GH_PAT`
3. Re-run bootstrap workflow — it will use `GH_PAT` for `gh secret set` commands

### Secrets That Require PAT
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

These are required by `deploy-api-to-azure.yml`, `deploy-ui-to-azure.yml`, and `infra-deploy.yml` for Azure login.

---

**Last Updated**: Based on fix for GitHub App installation detection and workflow update handling.
