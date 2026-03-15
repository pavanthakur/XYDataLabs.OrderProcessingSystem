# Quick Setup: GitHub App for Secret Management

## 🎯 Goal
Eliminate PAT token expiration by using GitHub App authentication (tokens never expire, auto-generated on each workflow run).

## ⚡ 4-Minute Setup (Installation ID Auto-Discovered!)

### Step 1: Create GitHub App (2 minutes)

1. Go to: https://github.com/settings/apps/new
2. Fill in:
   ```
   Name: YourRepo-SecretManager (e.g., XYDataLabsGitHubApp)
   Homepage URL: https://github.com/[your-username]/[your-repo]
   Webhook: UNCHECK "Active"
   ```
3. **Permissions** → Repository permissions (⚠️ CRITICAL - Set all required permissions):
   
   | Permission | Access Level | Required For |
   |------------|--------------|--------------|
   | **Actions** | Read and write ✅ | Trigger workflows, manage workflow runs |
   | **Administration** | Read and write ✅ | Repository settings, teams, and collaborators |
   | **Contents** | Read ✅ | Access repository files |
   | **Environments** | Read and write ✅ | **CRITICAL** - Create/manage environments and protection rules |
   | **Metadata** | Read ✅ | Mandatory - Basic repository information |
   | **Pull requests** | Read and write ✅ | Create/update PRs in workflows |
   | **Secrets** | Read and write ✅ | **CRITICAL** - Read/write repository & environment secrets |
   | **Workflows** | Read and write ✅ | Modify workflow files, dispatch workflow runs |

   **To set permissions:**
   - Scroll to "Repository permissions" section
   - Find each permission above
   - Click dropdown → Select **"Read and write"**
   - Leave all other permissions as "No access" (unless needed for your specific use case)

4. Click **Create GitHub App**

### Step 2: Generate Private Key (30 seconds)

1. Scroll to **Private keys** section
2. Click **Generate a private key**
3. Save the downloaded `.pem` file securely

### Step 3: Install App on Repository (30 seconds)

1. Click **Install App** in left sidebar
2. Select your account
3. Choose **Only select repositories** → select your repository
4. Click **Install**

### Step 4: Verify Installation & Permissions (IMPORTANT - 30 seconds)

After installation completes, you MUST verify both installation and permissions:

#### 4a. Verify Repository Installation

1. Go to: https://github.com/settings/apps/[your-app-name]/installations
   - Example: https://github.com/settings/apps/xydatalabsgithubapp/installations

2. **Verify** you see your repository listed under "Repository access"
   - ✅ Should show: `pavanthakur/XYDataLabs.OrderProcessingSystem` (or your repo name)
   - ❌ If empty or missing: Click **Configure** → Add the repository

3. **Note the Installation ID** from the URL (optional, auto-discovered by workflow):
   ```
   https://github.com/settings/installations/12345678
                                              ^^^^^^^^
                                         Installation ID
   ```

#### 4b. Verify Permissions (CRITICAL ⚠️)

On the same installation page, scroll to **"Permissions"** section and verify:

| Permission | Should Show | If Missing |
|------------|-------------|------------|
| ✅ Read and write access to actions, pull requests, and workflows | Present | Go to app settings → Permissions & events |
| ✅ Read and write access to secrets | **CRITICAL** | Add this permission immediately |
| ✅ Read access to metadata | Present (automatic) | N/A |

**If "Secrets" permission is missing:**
1. Go to: https://github.com/settings/apps/[your-app-name]/permissions
2. Repository permissions → **Secrets** → Change to **"Read and write"**
3. Save changes. You will need to approve the updated permissions for your repository again.
4. Revisit the app installation link to complete approval: https://github.com/settings/apps/[your-app-name]/installations

---
### Quick Troubleshooting Checklist

1. **Check GitHub App permissions** (Secrets: Read and write)
2. **Verify app is installed on repository**: https://github.com/settings/installations
3. **Review GitHub App configuration**: Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md
---

#### 4c. Ignore "Danger zone" Section ✅

At the bottom of the installation page, you'll see a red **"Danger zone"** section with "Suspend" and "Uninstall" buttons.

> **ℹ️ This is NORMAL** - Every GitHub App installation shows this section. **No action required.**

- **Suspend** - Temporarily blocks app access (only use if you suspect a security issue)
- **Uninstall** - Permanently removes the app (only use if switching authentication methods)

**For normal operation, ignore this section completely.** Your app is properly configured.

> **Why this matters**: 
> - Without repository installation → Workflow cannot authenticate
> - Without Secrets permission → Workflow cannot read/write secrets (authentication will fail)
> - "Danger zone" is just a safety feature - you don't need to interact with it

### Step 5: Add Secrets to Repository (1 minute)

Go to: https://github.com/[your-org]/[your-repo]/settings/secrets/actions

Add these **2 secrets** (not 3!):

| Secret Name | Value | Where to Find |
|------------|-------|---------------|
| `APP_ID` | Example: `123456` | App settings page, top of page |
| `APP_PRIVATE_KEY` | Full `.pem` file contents | Open downloaded file, copy ALL text |

✨ **No need for `APP_INSTALLATION_ID`** - the workflow automatically discovers it!

**For APP_PRIVATE_KEY**, copy entire content including:
```
-----BEGIN RSA PRIVATE KEY-----
[multiple lines of key data]
-----END RSA PRIVATE KEY-----
```

### Step 6: Run Workflow ✨

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

### "Failed to generate installation token" or "App not found"

**Most Common Cause**: App not properly installed on repository

**Fix**:
1. **Verify installation** (CRITICAL):
   - Go to: https://github.com/settings/apps/[your-app-name]/installations
   - Check your repository is listed under "Repository access"
   - If missing: Click **Configure** → Add your repository → Save

2. **Check App ID** (no typo):
   ```powershell
   # Verify from app settings page
   # Should match the GH_APP_ID secret
   ```

3. **Verify Private Key format**:
   ```powershell
   # Should show BEGIN line
   Get-Content path\to\key.pem | Select-Object -First 1
   # Expected: -----BEGIN RSA PRIVATE KEY-----
   ```

4. **Test with GitHub CLI** (if authenticated):
   ```powershell
   gh api /repos/[owner]/[repo]/installation
   # Should return installation details without errors
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

## 💡 Tips

- **Organization-wide**: Create app at org level for multiple repos
- **Shared secrets**: Use organization secrets for `GH_APP_*` values
- **Security**: Private key is like a password — keep it secret!
- **Audit**: All actions logged in GitHub audit log

---

## 🤖 Automation Capabilities Reference

Understanding what can and cannot be automated when setting up GitHub Apps:

| Task | Status | Reason |
|------|--------|--------|
| Secret configuration (bootstrap workflow) | ✅ Fully automated | Uses GitHub App token |
| Environment secret setup | ✅ Fully automated | Via `configure-github-secrets.yml` |
| Token generation | ✅ Fully automated | Auto-generated each workflow run |
| Installation validation | ✅ Fully automated | Checked at workflow start |
| Initial app creation | ⚠️ Manual (one-time) | GitHub requires interactive OAuth approval |
| Private key generation | ⚠️ Manual (one-time) | Security best practice — user must download |
| Initial app installation | ⚠️ Manual (one-time) | Repository owner must approve |
| First-time authorization | ❌ Cannot automate | GitHub security requirement by design |

### Why This Is The Right Approach
- **Token expiration: solved** — GitHub App tokens are generated fresh on every run (no PAT renewal needed)
- **Zero maintenance** — Once configured, the app runs indefinitely
- **One-time setup** — ~5 minutes of manual work, then fully automated forever
