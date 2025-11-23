# Troubleshooting: GitHub App Token Generation Failed (404 Not Found)

## The Error You're Seeing

```
Step 2: Generate GitHub App Token

owner and repositories not set, creating token for the current repository ("XYDataLabs.OrderProcessingSystem")
Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 1): Not Found
Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 2): Not Found
Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 3): Not Found
Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 4): Not Found

RequestError [HttpError]: Not Found - https://docs.github.com/rest/apps/apps#get-a-repository-installation-for-the-authenticated-app
  status: 404
  url: 'https://api.github.com/repos/pavanthakur/XYDataLabs.OrderProcessingSystem/installation'
```

## What This Error Means

The workflow successfully found your `APP_ID` and `APP_PRIVATE_KEY` secrets, but when it tried to generate an installation token using the `actions/create-github-app-token@v1` action, GitHub returned a **404 Not Found** error.

This **almost always** means: **Your GitHub App is not installed on this repository**.

## Understanding the Problem

### How GitHub Apps Work

1. **Create the App**: You create a GitHub App at https://github.com/settings/apps
2. **Install the App**: You install that app on specific repositories or organizations
3. **Generate Token**: The workflow uses the App ID and Private Key to generate an installation token **for this specific repository**

### The 404 Error Path

```
Workflow checks: "Does this repository have APP_ID and APP_PRIVATE_KEY secrets?"
✅ Yes! Both secrets exist

Workflow tries: "Generate installation token for this repository"
GitHub API checks: "Is this GitHub App installed on this repository?"
❌ No! App not found on this repository → 404 Not Found
```

## Solution: Install GitHub App on Repository

### Step 1: Verify Your GitHub App Exists

1. Go to: https://github.com/settings/apps
2. Find your GitHub App (e.g., "OrderProcessingSystem-SecretManager" or similar)
3. Click on the app name to view details
4. Note the **App ID** - verify it matches your `APP_ID` secret

### Step 2: Check Current Installations

1. Go to: https://github.com/settings/installations
2. Find your GitHub App in the list
3. Click **"Configure"** next to the app
4. Check the **"Repository access"** section

### Step 3: Install App on This Repository

If `pavanthakur/XYDataLabs.OrderProcessingSystem` is **not** in the repository list:

1. In the **"Repository access"** section:
   - Select **"Only select repositories"** (recommended)
   - Click the **"Select repositories"** dropdown
   - Find and select: **XYDataLabs.OrderProcessingSystem**
   - OR select **"All repositories"** if you want the app on all repos

2. Click **"Save"** at the bottom of the page

3. You should see a confirmation that the installation was updated

### Step 4: Verify Installation

1. Go back to: https://github.com/settings/installations
2. Click **"Configure"** next to your app again
3. Verify **XYDataLabs.OrderProcessingSystem** now appears in the repository list

### Step 5: Re-run the Workflow

1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml
2. Click **"Run workflow"**
3. Select your environment (e.g., `dev`)
4. Enable **"Configure GitHub secrets"** = `true`
5. Click **"Run workflow"**

The token generation should now succeed!

## Other Possible Causes

If the app **IS** installed but you still get 404, check these:

### 1. Wrong APP_ID Secret

**Symptom**: App is installed, but still getting 404

**Check**:
- Get your App ID from: https://github.com/settings/apps → Your App → About → App ID
- Compare with your secret at: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
- If they don't match, update the `APP_ID` secret

### 2. Invalid Private Key Format

**Symptom**: Different error like "Invalid JWT" or authentication failure

**Check**:
- Private key must include the BEGIN/END lines:
  ```
  -----BEGIN RSA PRIVATE KEY-----
  (your key content)
  -----END RSA PRIVATE KEY-----
  ```
- No extra spaces, no line breaks before/after
- Full contents of the `.pem` file

**Fix**: 
1. Go to your app: https://github.com/settings/apps → Your App
2. Scroll to "Private keys" section
3. Click "Generate a private key" (generates new .pem file)
4. Update the `APP_PRIVATE_KEY` secret with the full contents

### 3. App Uninstalled or Deleted

**Symptom**: App used to work, now getting 404

**Check**:
- Go to: https://github.com/settings/apps
- Does your app still exist?
- Go to: https://github.com/settings/installations
- Is the app still installed?

**Fix**: Reinstall the app (steps above) or create a new one if deleted

### 4. App Not Given Repository Permissions

**Symptom**: App installed but no permissions

**Check**:
1. Go to: https://github.com/settings/apps → Your App → Permissions
2. Under **"Repository permissions"**, verify:
   - **Secrets**: Read and write ✅

**Fix**: Update permissions and accept the new permissions in the installation

## How the Workflow Detects This Now

Starting with this fix, when GitHub App token generation fails, the workflow will:

1. ✅ Catch the error (using `continue-on-error: true`)
2. ✅ Display comprehensive troubleshooting guide
3. ✅ Provide step-by-step installation instructions
4. ✅ Explain common causes and solutions
5. ✅ Link to setup documentation

You'll see a detailed error message like:

```
╔════════════════════════════════════════════════════════════════╗
║         GITHUB APP TOKEN GENERATION FAILED                    ║
╚════════════════════════════════════════════════════════════════╝

❌ Failed to generate GitHub App installation token

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 MOST LIKELY CAUSE: GitHub App Not Installed on Repository
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The workflow detected APP_ID and APP_PRIVATE_KEY secrets, but failed
to generate an installation token. This typically means:

  ❌ The GitHub App is created but NOT installed on this repository

📋 SOLUTION: Install GitHub App on Repository
...
```

## Prevention: Setup Checklist

To avoid this issue in future setups:

- [ ] 1. Create GitHub App at https://github.com/settings/apps/new
- [ ] 2. Set permissions: Secrets → Read and write
- [ ] 3. Generate private key (download .pem file)
- [ ] 4. **Install the app** at https://github.com/settings/installations
- [ ] 5. Select this repository during installation
- [ ] 6. Add `APP_ID` secret
- [ ] 7. Add `APP_PRIVATE_KEY` secret (full .pem contents)
- [ ] 8. Run workflow

**Note**: Steps 4-5 (installation) are often forgotten but are **required**!

## Quick Reference

### Verify App Installation Status

```bash
# Using GitHub CLI
gh api /repos/pavanthakur/XYDataLabs.OrderProcessingSystem/installation

# If app is installed: Returns installation details
# If app is NOT installed: Returns 404 error
```

### Links

- **Your GitHub Apps**: https://github.com/settings/apps
- **Your App Installations**: https://github.com/settings/installations
- **Repository Secrets**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
- **Setup Guide**: Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md
- **Detailed Auth Guide**: Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md

## Related Documentation

- [APP_INSTALLATION_ID_EXPLAINED.md](./APP_INSTALLATION_ID_EXPLAINED.md) - Why you don't need to configure Installation ID
- [GITHUB-APP-AUTO-DISCOVERY.md](./GITHUB-APP-AUTO-DISCOVERY.md) - How auto-discovery works
- [TROUBLESHOOTING-APP-SECRETS-MISSING.md](./TROUBLESHOOTING-APP-SECRETS-MISSING.md) - Environment vs Repository secrets

## Summary

**Problem**: 404 Not Found when generating GitHub App token  
**Cause**: GitHub App not installed on repository  
**Solution**: Install the app at https://github.com/settings/installations  
**Verification**: Repository should appear in app's installation list  
**Result**: Token generation succeeds, workflow continues ✅
