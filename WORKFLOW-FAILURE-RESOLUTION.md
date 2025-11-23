# Workflow Failure Resolution Guide

## Current Issue

Your Azure Bootstrap workflow is failing with this error:

```
Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 1-4): Not Found
RequestError [HttpError]: Not Found - https://docs.github.com/rest/apps/apps#get-a-repository-installation-for-the-authenticated-app
  status: 404
```

## What This Means

✅ **Good News**: The workflow is working correctly and detecting the issue  
❌ **The Problem**: Your GitHub App is NOT installed on this repository

## Understanding the Issue

GitHub Apps work in two steps:
1. **Create the App** - You create it at https://github.com/settings/apps (✅ You've done this)
2. **Install the App** - You install it on specific repositories (❌ This step is missing)

Your workflow found the `APP_ID` and `APP_PRIVATE_KEY` secrets, which means the app exists. But when it tried to generate an installation token, GitHub returned "Not Found" because the app isn't installed on `pavanthakur/XYDataLabs.OrderProcessingSystem`.

## How to Fix This (5 minutes)

### Step 1: Go to GitHub App Installations

Visit: https://github.com/settings/installations

### Step 2: Find Your App

Look for your GitHub App in the list (e.g., "OrderProcessingSystem-SecretManager" or similar name).

### Step 3: Configure the App

Click the **"Configure"** button next to your app.

### Step 4: Add This Repository

In the "Repository access" section:
- Select **"Only select repositories"** (recommended for security)
- Click the **"Select repositories"** dropdown
- Find and check: **XYDataLabs.OrderProcessingSystem**
- Click **"Save"** at the bottom of the page

### Step 5: Verify Installation

1. Go back to https://github.com/settings/installations
2. Click "Configure" again
3. Verify that **XYDataLabs.OrderProcessingSystem** now appears in the repository list

### Step 6: Re-run the Workflow

1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml
2. Click **"Run workflow"**
3. Select your environment (e.g., `dev`)
4. Enable any options you need
5. Click **"Run workflow"**

✅ **The workflow should now succeed!**

## Why Did This Happen?

When setting up a GitHub App, it's easy to miss the installation step because:
- Creating the app and installing it are separate actions
- The app creation page doesn't automatically install it
- You need to explicitly go to the installations page to add repositories

## Alternative: Install on All Repositories

If you want the app to work on all your repositories:

1. Go to https://github.com/settings/installations
2. Click "Configure" next to your app
3. Select **"All repositories"** instead of "Only select repositories"
4. Click "Save"

⚠️ **Note**: This gives the app access to all your repositories, which may not be desired for security reasons.

## Verification Command

You can verify the installation using GitHub CLI:

```bash
gh api /repos/pavanthakur/XYDataLabs.OrderProcessingSystem/installation
```

- **If installed**: Returns installation details ✅
- **If NOT installed**: Returns 404 error ❌

## No Code Changes Needed

The workflow code is **correct and working as designed**. The comprehensive error message you're seeing is the workflow correctly detecting and explaining the issue.

## Other Possible Causes

If the app IS installed but you're still getting the 404 error:

### Wrong APP_ID

- Verify your `APP_ID` secret matches the App ID shown at https://github.com/settings/apps
- The App ID is a number like `123456`

### Invalid APP_PRIVATE_KEY

- Must include `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` lines
- Must be the complete contents of the `.pem` file
- No extra spaces or line breaks before/after

### Missing Permissions

1. Go to https://github.com/settings/apps
2. Click on your app
3. Go to **"Permissions"**
4. Under **"Repository permissions"**, verify:
   - **Secrets**: Read and write ✅

## Summary

**Problem**: GitHub App not installed on repository  
**Solution**: Install the app at https://github.com/settings/installations  
**Time**: 5 minutes  
**Result**: Workflow will succeed ✅

## Related Documentation

- [TROUBLESHOOTING-GITHUB-APP-404.md](./TROUBLESHOOTING-GITHUB-APP-404.md) - Detailed troubleshooting guide
- [APP_INSTALLATION_ID_EXPLAINED.md](./APP_INSTALLATION_ID_EXPLAINED.md) - Why Installation ID is auto-discovered
- [Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md](./Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md) - Complete setup guide

## Still Having Issues?

If you've installed the app and are still seeing the error:

1. Double-check the repository name is exactly: `XYDataLabs.OrderProcessingSystem`
2. Verify the app has "Secrets: Read and write" permissions
3. Ensure `APP_ID` matches your GitHub App ID
4. Verify `APP_PRIVATE_KEY` is the complete `.pem` file contents
5. Wait a few minutes for GitHub's cache to update, then try again
