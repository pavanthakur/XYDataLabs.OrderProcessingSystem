# Automated Bootstrap Guide - Complete End-to-End Setup

## 🎯 Overview

This guide provides complete automation for setting up your CI/CD pipeline with **zero token expiration issues**.

### What Gets Automated

✅ **Azure OIDC Setup** - Fully automated via Azure CLI  
✅ **GitHub App Setup** - One-time 5-minute manual step, then fully automated forever  
✅ **GitHub Secrets Configuration** - Fully automated once App is configured  
✅ **Infrastructure Bootstrap** - Fully automated  
✅ **Validation** - Fully automated  

### Token Expiration: SOLVED ✨

**Problem**: PAT tokens expire (max 1 year) and require manual renewal  
**Solution**: GitHub App generates fresh tokens automatically on every workflow run  
**Result**: Zero maintenance, tokens never expire

---

## 🚀 Complete Setup Flow

### First-Time Setup (One-Time, ~15 minutes total)

#### Step 1: Azure OIDC Setup (Automated - 3 minutes)

1. Go to: **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure:
   ```
   Environment: all
   Setup Azure OIDC: ✅ true
   Setup GitHub App: ✅ true  (we'll configure this next)
   Configure GitHub secrets: ❌ false  (not yet)
   Bootstrap infrastructure: ❌ false  (not yet)
   Enable validation: ❌ false  (not yet)
   ```
3. Click **Run workflow**
4. Workflow will:
   - Create Azure OIDC app registration
   - Set up federated credentials for dev/staging/prod
   - Output Azure credentials for next steps

**Outputs** (copy these for later):
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

#### Step 2: GitHub App Setup (Manual One-Time - 5 minutes)

**Why manual?** GitHub requires interactive authorization for app creation (security requirement).  
**Once configured**: Fully automated forever, no token expiration!

##### 2a. Create GitHub App

1. Open: https://github.com/settings/apps/new
2. Fill in:
   ```
   Name: OrderProcessingSystem-SecretManager
   Homepage URL: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
   Webhook: UNCHECK "Active"
   ```
3. **Permissions** → Repository permissions:
   - **Secrets**: Read and write ✅
4. Click **Create GitHub App**
5. **Copy App ID** from the top of the settings page

##### 2b. Generate Private Key

1. On app settings page, scroll to **Private keys** section
2. Click **Generate a private key**
3. Save the downloaded `.pem` file to a secure location
4. Open the file in a text editor - you'll need the contents

##### 2c. Install App

1. Click **Install App** in the left sidebar
2. Select your account
3. Choose **Only select repositories**
4. Select: `XYDataLabs.OrderProcessingSystem`
5. Click **Install**
6. **Copy Installation ID** from URL:
   - URL format: `https://github.com/settings/installations/12345678`
   - Installation ID = `12345678`

##### 2d. Add GitHub App Secrets

Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

Add these **3 secrets**:

| Secret Name | Value | Example |
|------------|-------|---------|
| `GH_APP_ID` | App ID from step 2a | `123456` |
| `GH_APP_INSTALLATION_ID` | Installation ID from step 2c | `12345678` |
| `GH_APP_PRIVATE_KEY` | **Full contents** of .pem file | Copy entire file including `-----BEGIN...-----` and `-----END...-----` |

#### Step 3: Configure Secrets (Automated - 1 minute)

1. Go to: **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure:
   ```
   Environment: all
   Setup Azure OIDC: ❌ false  (already done)
   Setup GitHub App: ❌ false  (already done)
   Configure GitHub secrets: ✅ true
   Bootstrap infrastructure: ❌ false  (not yet)
   Enable validation: ❌ false  (not yet)
   ```
3. Click **Run workflow**
4. Workflow will automatically:
   - Generate GitHub App installation token
   - Set `AZUREAPPSERVICE_*` secrets from OIDC output
   - Configure for dev, staging, prod environments

#### Step 4: Bootstrap Infrastructure (Automated - 5-10 minutes)

1. Go to: **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure:
   ```
   Environment: all  (or choose specific: dev/staging/prod)
   Setup Azure OIDC: ❌ false
   Setup GitHub App: ❌ false
   Configure GitHub secrets: ❌ false
   Bootstrap infrastructure: ✅ true
   Enable validation: ✅ true
   ```
3. Click **Run workflow**
4. Workflow will automatically:
   - Create Azure resource groups
   - Deploy App Services (API + UI)
   - Configure App Service settings
   - Set up Application Insights
   - Enable pre-deployment validation

---

## ✅ Verification

### Check GitHub App is Working

Run workflow and check logs for:

```
✅ GitHub App configured - automatic token generation
🔑 Generated installation token (expires: 2024-01-22 11:30:00 UTC)
Using GitHub App authentication
✅ Repository secrets configured successfully using GitHub App!
```

### Check Azure OIDC is Working

1. Go to: **Actions** → **Deploy API to Azure** → **Run workflow**
2. Check logs for successful Azure login via OIDC

### Check Infrastructure is Ready

1. Azure Portal: https://portal.azure.com
2. Search for resource groups:
   - `rg-orderprocessing-dev`
   - `rg-orderprocessing-staging`
   - `rg-orderprocessing-prod`
3. Verify App Services are running

---

## 🔄 Ongoing Usage (Fully Automated)

### Deploying Code Changes

**Just push code** - workflows automatically triggered on push to dev/staging/main branches.

```bash
# Deploy to dev
git push origin dev

# Deploy to staging
git push origin staging

# Deploy to production
git push origin main
```

### Manual Deployment

Use workflow dispatch for manual deployments:

1. **Actions** → **Deploy API to Azure** → **Run workflow**
2. Select branch and environment
3. Click **Run workflow**

### Adding New Environment

1. **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure:
   ```
   Environment: [new-env-name]
   Bootstrap infrastructure: ✅ true
   ```
3. Everything else is automated!

---

## 🎯 Key Benefits

### Zero Token Expiration Maintenance

| Before (PAT) | After (GitHub App) |
|--------------|-------------------|
| ⚠️ Expires every 1-365 days | ✅ Never expires |
| ⚠️ Manual renewal required | ✅ Auto-generated |
| ⚠️ Calendar reminders needed | ✅ No maintenance |
| ⚠️ Risk of workflow breakage | ✅ Always works |

### Full Automation After Initial Setup

- **15 minutes** - Initial setup (one-time)
- **0 minutes** - Ongoing maintenance (forever)
- **No expiration tracking** - Tokens generated on-demand
- **No calendar reminders** - Nothing to remember

### Better Security

- **Short-lived tokens** (1 hour expiration)
- **Auto-rotated** on every workflow run
- **Granular permissions** (only secrets access)
- **Full audit trail** in GitHub audit log

---

## 📊 Workflow Decision Tree

```
┌─────────────────────────────────────┐
│  First Time Setup?                  │
└────────┬────────────────────────────┘
         │
         ├─ YES → Follow "First-Time Setup" above
         │
         └─ NO → Already configured?
                  │
                  ├─ Azure OIDC? ✅
                  ├─ GitHub App? ✅
                  ├─ Secrets? ✅
                  └─ Infrastructure? ✅
                       │
                       └─ Just push code!
                          Deployments fully automated
```

---

## 🆘 Troubleshooting

### "GitHub App not configured" Error

**Cause**: Missing `GH_APP_*` secrets

**Fix**:
1. Check secrets exist: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
2. Verify all 3 secrets are present:
   - `GH_APP_ID`
   - `GH_APP_INSTALLATION_ID`
   - `GH_APP_PRIVATE_KEY`
3. If missing, complete Step 2 above

### "Failed to generate installation token" Error

**Causes**:
1. Wrong App ID
2. Wrong Installation ID
3. Malformed private key

**Fix**:
```powershell
# Verify App ID
gh api /app --jq .id

# Check private key format (should show BEGIN line)
$key = Get-Content path\to\key.pem | Select-Object -First 1
Write-Host $key  # Should be: -----BEGIN RSA PRIVATE KEY-----
```

### "Insufficient permissions" Error

**Cause**: App doesn't have Secrets permission

**Fix**:
1. Go to: https://github.com/settings/apps
2. Click your app → **Permissions**
3. Repository permissions → Secrets → **Read and write**
4. Save changes

### OIDC Authentication Fails

**Cause**: Federated credentials not set up correctly

**Fix**:
1. Run workflow with `Setup Azure OIDC: true`
2. Verify credentials in Azure Portal:
   - Azure Portal → Azure Active Directory
   - App registrations → GitHub-Actions-OIDC
   - Certificates & secrets → Federated credentials

---

## 📚 Additional Resources

### Documentation

- **Quick Setup Guide**: [QUICK-SETUP-GITHUB-APP.md](./QUICK-SETUP-GITHUB-APP.md)
- **GitHub App Details**: [GITHUB-APP-AUTHENTICATION.md](./GITHUB-APP-AUTHENTICATION.md)
- **PAT Alternative**: [GITHUB-SECRETS-FIX.md](./GITHUB-SECRETS-FIX.md)
- **Workflow Reference**: [.github/workflows/README-AZURE-BOOTSTRAP.md](../.github/workflows/README-AZURE-BOOTSTRAP.md)

### Scripts

- **OIDC Setup**: `Resources/Azure-Deployment/setup-github-oidc.ps1`
- **Bootstrap Infra**: `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`
- **Secrets Configuration**: `Resources/Azure-Deployment/configure-github-secrets.ps1`

### External Links

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Azure OIDC with GitHub Actions](https://docs.microsoft.com/en-us/azure/developer/github/connect-from-azure)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

---

## 💡 Pro Tips

### Organization-Wide Setup

For multiple repositories:

1. Create GitHub App at **organization level**:
   - https://github.com/organizations/[ORG-NAME]/settings/apps/new
2. Install on **all repositories**
3. Use **organization secrets** for `GH_APP_*` values:
   - https://github.com/organizations/[ORG-NAME]/settings/secrets/actions
4. All repos automatically inherit configuration

### Environment-Specific Apps

For strict separation:

1. Create separate GitHub Apps:
   - `OrderProcessingSystem-SecretManager-Dev`
   - `OrderProcessingSystem-SecretManager-Prod`
2. Use environment secrets instead of repository secrets
3. Each environment uses different app

### Backup & Disaster Recovery

**GitHub App**:
- App credentials stored as repository secrets (encrypted)
- Private key backed up securely offline
- Can generate new private key anytime without breaking automation

**Azure OIDC**:
- Federated credentials stored in Azure AD
- Can be recreated by running `setup-github-oidc.ps1`
- No secrets to backup (uses OIDC tokens)

---

## ✨ Summary

**One-time setup** (15 minutes)→ **Zero maintenance forever** → **Full automation** 🎉

No more:
- ❌ Token expiration tracking
- ❌ Calendar reminders
- ❌ Manual secret updates
- ❌ Workflow breakages

Just:
- ✅ Push code
- ✅ Auto-deploy
- ✅ Zero maintenance
