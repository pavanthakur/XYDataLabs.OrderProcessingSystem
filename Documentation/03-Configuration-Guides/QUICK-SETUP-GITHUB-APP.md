# Quick Setup: GitHub App for Secret Management

## 🎯 Goal
Eliminate PAT token expiration by using GitHub App authentication (tokens never expire, auto-generated on each workflow run).

## ⚡ 4-Minute Setup (Installation ID Auto-Discovered!)

### Step 1: Create GitHub App (2 minutes)

1. Go to: https://github.com/settings/apps/new
2. Fill in:
   ```
   Name: YourRepo-SecretManager
   Homepage URL: https://github.com/[your-username]/[your-repo]
   Webhook: UNCHECK "Active"
   ```
3. **Permissions** → Repository permissions:
   - Secrets: **Read and write** ✅
4. Click **Create GitHub App**

### Step 2: Generate Private Key (30 seconds)

1. Scroll to **Private keys** section
2. Click **Generate a private key**
3. Save the downloaded `.pem` file securely

### Step 3: Install App (30 seconds)

1. Click **Install App** in left sidebar
2. Select your account
3. Choose **Only select repositories** → select your repository
4. Click **Install**
5. ✨ **Installation ID is now auto-discovered - no need to copy it!**

### Step 4: Add Secrets to Repository (1 minute)

Go to: https://github.com/[your-org]/[your-repo]/settings/secrets/actions

Add these **2 secrets** (not 3!):

| Secret Name | Value | Where to Find |
|------------|-------|---------------|
| `GH_APP_ID` | Example: `123456` | App settings page, top of page |
| `GH_APP_PRIVATE_KEY` | Full `.pem` file contents | Open downloaded file, copy ALL text |

✨ **No need for `GH_APP_INSTALLATION_ID`** - the workflow automatically discovers it!

**For GH_APP_PRIVATE_KEY**, copy entire content including:
```
-----BEGIN RSA PRIVATE KEY-----
[multiple lines of key data]
-----END RSA PRIVATE KEY-----
```

### Step 5: Run Workflow ✨

1. Go to Actions → Azure Bootstrap Setup
2. Click **Run workflow**
3. Select:
   - Configure GitHub secrets: ✅ **true**
4. Click **Run workflow**

**Done!** Secrets will be configured automatically. Tokens are auto-generated on every run (no expiration).

## ✅ Verification

Check workflow logs for:
```
✅ GitHub App configured - automatic token generation
🔑 Generated installation token (expires: [timestamp])
Using GitHub App authentication
✅ Repository secrets configured successfully using GitHub App!
```

## 🔄 Migration from PAT

If you're currently using `GH_PAT`:

1. Complete Steps 1-4 above (add GitHub App secrets)
2. **Optional**: Delete `GH_PAT` secret (workflow will automatically prefer GitHub App)
3. Run workflow - it will use GitHub App authentication

**Both can coexist** - workflow prefers GitHub App, falls back to PAT if App not configured.

## 🆚 Comparison

| Feature | GitHub App ⭐ | PAT ⚠️ |
|---------|--------------|--------|
| Token expiration | **Never** (auto-generated) | 1-365 days |
| Maintenance | **Zero** | Manual renewal |
| Security | Short-lived (1 hr) | Long-lived |
| Setup time | **4 minutes** | 2 minutes |
| Manual secrets | **2 secrets** | 1 secret |
| Installation ID | **Auto-discovered** | N/A |
| Revocation impact | None (auto-regenerated) | Breaks workflows |
| Best for | **Production/Teams** | Personal projects |

## 🚨 Troubleshooting

### "Failed to generate installation token"

**Check**:
1. App ID is correct (no typo)
2. Private key includes BEGIN/END lines
3. App is installed on the repository

**Fix**:
```powershell
# Verify App ID
gh api /app --jq .id

# Check private key format (should show BEGIN line)
Get-Content path\to\key.pem | Select-Object -First 1

# Verify app is installed
gh api /repos/[owner]/[repo]/installation
```

### "Insufficient permissions"

**Fix**:
1. Go to app settings: https://github.com/settings/apps
2. Click your app → **Permissions**
3. Repository permissions → Secrets → **Read and write**
4. Save changes

### Still using PAT after setup?

**Fix**: Workflow run may have been cached. Clear workflow cache or trigger a new run.

## 📚 Full Documentation

- Detailed guide: [Documentation/GITHUB-APP-AUTHENTICATION.md](./GITHUB-APP-AUTHENTICATION.md)
- PAT alternative: [Documentation/GITHUB-SECRETS-FIX.md](./GITHUB-SECRETS-FIX.md)

## 💡 Tips

- **Organization-wide**: Create app at org level for multiple repos
- **Shared secrets**: Use organization secrets for `GH_APP_*` values
- **Security**: Private key is like a password - keep it secret!
- **Audit**: All actions logged in GitHub audit log
