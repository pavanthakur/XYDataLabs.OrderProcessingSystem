# Quick Start: Testing Pre-Deployment Validation

## 🎯 What is This?

A test workflow that validates your infrastructure configuration **before** you deploy anything to Azure. Think of it as a pre-flight checklist for your deployment.

---

## ⚡ Quick Start (3 Steps)

### Step 1: Navigate to Actions
Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

### Step 2: Find the Workflow
Click on: **"Test Pre-Deployment Validation"** in the left sidebar

### Step 3: Run It
1. Click **"Run workflow"** button (top right)
2. Keep all defaults (they're smart!)
3. Click green **"Run workflow"** button
4. Wait 3-5 minutes
5. Check the results ✅

---

## 🔍 What Gets Tested?

### ✅ Infrastructure Changes (Bicep What-If)
**What it does:** Shows what would change in Azure if you deployed now
**Why it matters:** Catch unexpected deletions or modifications before they happen

### ✅ Authentication Setup (OIDC Verification)
**What it does:** Verifies your GitHub Actions can authenticate to Azure
**Why it matters:** Prevents deployment failures due to auth issues

### ✅ Configuration Consistency (SharedSettings)
**What it does:** Checks all environment configs have the same keys
**Why it matters:** Catches missing settings that would break an environment

---

## 📊 Understanding Results

### ✅ Green = Good
All tests passed! Your configuration is solid. Safe to deploy.

### ⚠️ Yellow = Warning
Something detected but might be expected:
- Infrastructure changes found (review them)
- OIDC app not found (might be intentional)

### ❌ Red = Fix Required
Configuration issues detected:
- Missing config keys
- Invalid Bicep syntax
- Auth problems

---

## 🎛️ Advanced Options

### Test Specific Environment
```yaml
environment: staging  # Test staging instead of dev
```

### Test All Environments at Once
```yaml
test-all-environments: true  # Tests dev, staging, AND prod
```

### Skip Certain Tests
```yaml
run-whatif: false      # Skip Bicep what-if
verify-oidc: false     # Skip OIDC check
check-config: false    # Skip config validation
```

### Use Custom Azure AD App Name
```yaml
oidc-app-name: xydatalabsgithubapp  # If you named your app differently
```

---

## 🆘 Common Issues

### "Azure Login Failed"
**Fix:** Check GitHub secrets are configured
- Go to: Settings → Secrets → Actions
- Verify: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`

### "Config Drift Detected"
**Fix:** Add missing keys to sharedsettings files
- Review the diff output in logs
- Add missing keys to affected environment files
- Re-run test

### "What-If Shows Deletions"
**Fix:** Review carefully - might be expected
- Check what resources would be deleted
- Verify it's intentional before deploying
- If unexpected, check your Bicep template changes

### "OIDC App Not Found"
**Fix:** Specify your custom app name
- If you named your Azure AD app differently (e.g., `xydatalabsgithubapp`)
- Add parameter: `oidc-app-name: xydatalabsgithubapp`
- Default expects: `GitHub-Actions-OIDC`

---

## 💡 Pro Tips

1. **Run before every PR** - Catch issues early
2. **Test all environments periodically** - Detect drift over time
3. **Check the artifacts** - Download logs for detailed analysis
4. **Read the summary** - Key info is at the top of each job

---

## 📚 Need More Help?

- **Full Documentation:** [README-TEST-VALIDATE-DEPLOYMENT.md](./README-TEST-VALIDATE-DEPLOYMENT.md)
- **Validation Details:** [README-VALIDATE-DEPLOYMENT.md](./README-VALIDATE-DEPLOYMENT.md)
- **Operations Guide:** [Operations-Quick-Links-README.md](../../Documentation/Operations-Quick-Links-README.md)

---

## 🚀 Next Steps After Testing

Once all tests pass:

1. **Test Infrastructure Deployment**
   - Go to Actions → Deploy Azure Infrastructure
   - Set `Dry Run = true`
   - Review what-if output

2. **Deploy to Dev**
   - Set `Dry Run = false`
   - Deploy to dev environment first

3. **Verify Deployment**
   - Check Azure Portal
   - Test API/UI endpoints
   - Review Application Insights

4. **Promote to Staging/Prod**
   - Repeat validation tests
   - Deploy with confidence

---

**Remember:** This test workflow is your safety net. Use it liberally! 🛡️
