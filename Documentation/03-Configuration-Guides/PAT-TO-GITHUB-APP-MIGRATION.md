# PAT to GitHub App Migration Guide

## Overview

As of the latest version, **Personal Access Tokens (PAT) are no longer supported** for secret automation in this repository. GitHub Apps are now the **required authentication method** for automated secret configuration.

This guide will help you migrate from PAT to GitHub App authentication.

---

## Why This Change?

### Problems with Personal Access Tokens
- **Expiration**: PATs expire (maximum 1 year), requiring manual renewal
- **Maintenance burden**: You must track expiration dates and renew tokens
- **Security risk**: Long-lived tokens increase attack surface
- **Manual intervention**: Token renewal requires human action

### Benefits of GitHub Apps
- ✅ **Never expires**: Tokens auto-generate on every workflow run
- ✅ **Zero maintenance**: No tracking, no renewals, no calendar reminders
- ✅ **Better security**: Short-lived tokens (1 hour), automatically renewed
- ✅ **Full automation**: Set it once, forget forever
- ✅ **Fine-grained permissions**: Precise control over what the app can access

---

## Migration Steps

### Step 1: Remove PAT Secret (if exists)

1. Go to your repository secrets:
   ```
   https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions
   ```

2. Find and delete the `GH_PAT` secret (if it exists)
   - This prevents confusion about which authentication method is in use
   - The workflow will now require GitHub App authentication

### Step 2: Create GitHub App

Follow our quick setup guide to create a GitHub App in about 5 minutes:

📖 **[Quick Setup Guide](./QUICK-SETUP-GITHUB-APP.md)**

Or for comprehensive details:

📘 **[Detailed GitHub App Authentication Guide](./GITHUB-APP-AUTHENTICATION.md)**

### Summary of GitHub App Setup:
1. Create GitHub App at: https://github.com/settings/apps/new
2. Configure permissions (Secrets: Read and write)
3. Generate private key
4. Install app on your repository
5. Add three repository secrets:
   - `APP_ID`
   - `APP_INSTALLATION_ID`
   - `APP_PRIVATE_KEY`

### Step 3: Verify Configuration

Run the workflow again to verify GitHub App authentication:

1. Go to Actions → Azure Bootstrap Setup
2. Select "Run workflow"
3. Enable: "Configure GitHub secrets"
4. Run the workflow

Expected output:
```
✅ GitHub App configured - automatic token generation
   No expiration maintenance required!
```

---

## Troubleshooting

### Error: "GitHub App authentication is REQUIRED"

**Cause**: The workflow detected no GitHub App secrets.

**Solution**:
1. Verify all three secrets exist:
   - `APP_ID`
   - `APP_INSTALLATION_ID`
   - `APP_PRIVATE_KEY`
2. Check the private key is in PEM format (includes `-----BEGIN RSA PRIVATE KEY-----`)
3. Verify the GitHub App is installed on your repository

### Error: "Failed to generate token"

**Cause**: GitHub App installation or permissions issue.

**Solutions**:
1. **Check app installation**:
   - Go to: https://github.com/settings/installations
   - Verify the app is installed on your repository
   - Click "Configure" and ensure the repository is selected

2. **Check app permissions**:
   - The app must have "Secrets: Read and write" permission
   - Edit app settings if needed: https://github.com/settings/apps

3. **Verify installation ID**:
   - The installation ID in the URL should match `APP_INSTALLATION_ID` secret
   - Format: `https://github.com/settings/installations/12345678`
   - Installation ID = `12345678`

### Error: "API 403: Resource not accessible"

**Cause**: GitHub App doesn't have required permissions.

**Solution**:
1. Go to app settings: https://github.com/settings/apps
2. Click your app name
3. Go to "Permissions & events"
4. Under "Repository permissions", set:
   - **Secrets**: Read and write ✅
5. Click "Save changes"
6. You may need to approve the permission change in your repository settings

---

## Comparison: PAT vs GitHub App

| Feature | Personal Access Token | GitHub App |
|---------|----------------------|------------|
| **Expiration** | Yes (max 1 year) | Never |
| **Maintenance** | Manual renewal required | Zero maintenance |
| **Token lifetime** | Long-lived (up to 1 year) | Short-lived (1 hour) |
| **Auto-renewal** | ❌ No | ✅ Yes |
| **Security** | Higher risk (long-lived) | Lower risk (short-lived) |
| **Setup complexity** | Easy | Moderate (one-time) |
| **Ongoing effort** | High (tracking, renewal) | None |
| **Automation** | Breaks on expiration | Always works |

---

## FAQs

### Q: Can I still use PAT?
**A**: No. PAT support has been removed. GitHub App is now required for secret automation.

### Q: What if I don't want to use automation?
**A**: You can still configure secrets manually without GitHub App:
1. Get Azure credentials from OIDC setup step
2. Manually add secrets at: https://github.com/YOUR_REPO/settings/secrets/actions
3. Required secrets:
   - `AZUREAPPSERVICE_CLIENTID`
   - `AZUREAPPSERVICE_TENANTID`
   - `AZUREAPPSERVICE_SUBSCRIPTIONID`

### Q: Is GitHub App more secure than PAT?
**A**: Yes, significantly:
- Tokens are short-lived (1 hour vs up to 1 year)
- Tokens auto-expire and regenerate
- Fine-grained permissions per repository
- Auditlog shows app activity separately from user activity

### Q: Do I need to create a new GitHub App for each repository?
**A**: No. One GitHub App can be installed on multiple repositories. Simply install the same app on other repos.

### Q: Can I share my GitHub App with team members?
**A**: Yes. The app belongs to your GitHub account or organization. Anyone with access to the repository can see it's installed, and admins can configure it.

### Q: What happens to my existing secrets?
**A**: Nothing changes with existing secrets. GitHub App only affects **how** secrets are automated, not the secrets themselves.

---

## Need Help?

### Documentation
- **[Quick Setup Guide](./QUICK-SETUP-GITHUB-APP.md)** - 5-minute setup
- **[Detailed Authentication Guide](./GITHUB-APP-AUTHENTICATION.md)** - Complete reference
- **[Automated Bootstrap Guide](./AUTOMATED-BOOTSTRAP-GUIDE.md)** - Full workflow documentation

### Common Issues
- **[GitHub Secrets Troubleshooting](./GITHUB-SECRETS-FIX.md)** - Secret configuration problems
- **[Workflow Automation Guide](./WORKFLOW-AUTOMATION-VISUAL-GUIDE.md)** - Visual workflow diagrams

### Still Stuck?
1. Check workflow logs for detailed error messages
2. Review the troubleshooting section above
3. Verify all three GitHub App secrets are configured correctly
4. Ensure the GitHub App is installed on your repository

---

## Summary

**Migration checklist:**
- [ ] Remove `GH_PAT` secret (if exists)
- [ ] Create GitHub App
- [ ] Add three secrets: `APP_ID`, `APP_INSTALLATION_ID`, `APP_PRIVATE_KEY`
- [ ] Run workflow to verify
- [ ] Confirm automated token generation works

**Time required**: ~5-10 minutes one-time setup

**Future maintenance**: None! Set it and forget it.

---

*Last updated: 2025-11-22*
