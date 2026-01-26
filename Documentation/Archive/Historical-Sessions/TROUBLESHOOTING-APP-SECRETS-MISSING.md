# Troubleshooting: APP_ID and APP_PRIVATE_KEY Showing as Missing

## The Error You're Seeing

```
🔍 Checking GitHub App secrets...
  APP_ID                : ❌ Missing
  APP_PRIVATE_KEY       : ❌ Missing
  APP_INSTALLATION_ID   : ✨ Auto-discovered at runtime

  ⚠️  GitHub App secrets not configured
```

## Why This Happened (Before the Fix)

The workflow jobs weren't configured with the `environment` context, so they couldn't access your **environment secrets**. They were looking for **repository secrets** instead.

## ✅ Fixed!

I've updated the workflow to add `environment` context to the jobs that need to read your environment secrets:

```yaml
configure-secrets:
  environment: ${{ inputs.environment != 'all' && inputs.environment || 'dev' }}
```

This tells GitHub Actions to run the job in the context of the selected environment, giving it access to that environment's secrets.

## How to Run It Now

### Step 1: Pull Latest Changes

Make sure you have the latest workflow file:

```bash
git pull origin dev
```

Or refresh your browser if you're running from GitHub UI.

### Step 2: Run the Workflow with Specific Environment

1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

2. Click **"Run workflow"**

3. **IMPORTANT:** Select a **specific environment**:
   - ✅ Select: `dev` (recommended for first run)
   - ✅ Or select: `staging`  
   - ✅ Or select: `prod`
   - ❌ Do NOT select: `all` (will default to `dev` environment secrets)

4. Enable: **Configure GitHub secrets** = `true`

5. Click **"Run workflow"**

### Step 3: Verify Success

You should now see:

```
🔍 Checking GitHub App secrets...
  Environment Context: dev
  
  APP_ID                : ✅ Present
  APP_PRIVATE_KEY       : ✅ Present
  APP_INSTALLATION_ID   : ✨ Auto-discovered at runtime

  ✅ All required GitHub App secrets detected
```

## Why You Must Select Specific Environment

Since you configured your secrets at the **environment level**, the workflow needs to know which environment's secrets to use:

### Your Setup
- **dev environment**: Has `APP_ID` and `APP_PRIVATE_KEY`
- **staging environment**: Has `APP_ID` and `APP_PRIVATE_KEY`
- **prod environment**: Has `APP_ID` and `APP_PRIVATE_KEY`

### How Environment Selection Works

| Selection | Environment Secrets Used | Azure Secrets Configured |
|-----------|-------------------------|--------------------------|
| `dev` | dev environment | dev environment only |
| `staging` | staging environment | staging environment only |
| `prod` | prod environment | prod environment only |
| `all` | **dev environment** (default) | dev, staging, AND prod |

⚠️ When you select `all`, the workflow runs sequentially for each environment but uses the **first environment (dev)** for the GitHub App secrets.

## Understanding Environment vs Repository Secrets

### Repository Secrets (Not What You Have)
- Location: `Settings → Secrets and variables → Actions → Repository secrets`
- Scope: Available to all workflow runs, all branches, all environments
- When to use: Single environment or non-sensitive config

### Environment Secrets (What You Have ✅)
- Location: `Settings → Environments → [env name] → Secrets`
- Scope: Only available when workflow runs in that environment context
- Benefits:
  - Separate credentials per environment
  - Environment protection rules (approvals, reviewers)
  - Branch restrictions
  - Better security isolation

Your choice of environment secrets is **better** for a multi-environment setup!

## What Changed in the Fix

### Before (Broken)
```yaml
configure-secrets:
  runs-on: windows-latest
  steps:
    - name: Check secrets
      run: |
        $hasAppId = "${{ secrets.APP_ID }}" -ne ""  # Can't see environment secrets!
```

### After (Fixed)
```yaml
configure-secrets:
  runs-on: windows-latest
  environment: ${{ inputs.environment != 'all' && inputs.environment || 'dev' }}
  steps:
    - name: Check secrets
      run: |
        $hasAppId = "${{ secrets.APP_ID }}" -ne ""  # Now can see environment secrets!
```

## Next Steps

1. ✅ Pull the latest changes (or refresh if using GitHub UI)
2. ✅ Run workflow selecting **specific environment** (dev, staging, or prod)
3. ✅ Verify secrets are detected
4. ✅ Let the workflow configure Azure secrets
5. ✅ Repeat for other environments as needed

Your setup is correct - it was just a workflow configuration issue that's now fixed! 🎉
