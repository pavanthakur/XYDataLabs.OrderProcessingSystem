# Test Pre-Deployment Validation Workflow

## 🎯 Overview

The `test-validate-deployment.yml` workflow is a **standalone testing workflow** designed to validate the pre-deployment validation infrastructure without triggering actual infrastructure deployments. This allows developers and DevOps teams to:

- ✅ Test validation scripts independently
- ✅ Verify configuration consistency before deployment
- ✅ Validate Azure connectivity and permissions
- ✅ Ensure the reusable validation workflow works correctly
- ✅ Catch configuration issues early in the development cycle

---

## 🚀 Quick Start

### Running the Test Workflow

1. **Navigate to GitHub Actions:**
   - Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
   - Find: "Test Pre-Deployment Validation" workflow

2. **Click "Run workflow" button**

3. **Configure Test Parameters:**

   | Parameter | Description | Default | Options |
   |-----------|-------------|---------|---------|
   | **environment** | Target environment to test | dev | dev, staging, prod, uat |
   | **run-whatif** | Test Bicep what-if analysis | true | true, false |
   | **verify-oidc** | Test OIDC credentials verification | true | true, false |
   | **check-config** | Test SharedSettings consistency | true | true, false |
   | **test-all-environments** | Test across all environments | false | true, false |
   | **oidc-app-name** | Azure AD App Registration name | GitHub-Actions-OIDC | Any app name |

4. **Click "Run workflow"**

---

## 📋 Test Scenarios

### Scenario 1: Quick Validation Check (Default)
**Purpose:** Verify all validation components for a single environment

```yaml
environment: dev
run-whatif: true
verify-oidc: true
check-config: true
test-all-environments: false
```

**What it tests:**
- ✅ Bicep what-if analysis for dev environment
- ✅ OIDC federated credentials setup
- ✅ SharedSettings consistency across all config files
- ✅ Reusable validation workflow integration

**Expected Duration:** 3-5 minutes

---

### Scenario 2: Full Multi-Environment Test
**Purpose:** Comprehensive validation across all environments

```yaml
environment: dev
run-whatif: true
verify-oidc: true
check-config: true
test-all-environments: true
```

**What it tests:**
- ✅ Bicep what-if for dev, staging, AND prod
- ✅ OIDC credentials for all environments
- ✅ Configuration drift detection across all sharedsettings files
- ✅ Parameter file existence and validity

**Expected Duration:** 8-12 minutes

---

### Scenario 3: Configuration-Only Test
**Purpose:** Fast check of configuration consistency without Azure calls

```yaml
environment: dev
run-whatif: false
verify-oidc: false
check-config: true
test-all-environments: false
```

**What it tests:**
- ✅ SharedSettings consistency validation only
- ❌ No Azure authentication required
- ❌ No Bicep template validation

**Expected Duration:** < 1 minute

---

### Scenario 4: Infrastructure Drift Detection
**Purpose:** Check for unintended changes in infrastructure

```yaml
environment: staging
run-whatif: true
verify-oidc: false
check-config: false
test-all-environments: false
```

**What it tests:**
- ✅ What changes would be made if deployed now
- ✅ Identifies deletions, modifications, or additions
- ❌ Configuration checks skipped

**Expected Duration:** 2-3 minutes

---

## 🔍 Understanding Test Results

### Test Jobs

The workflow runs **three jobs**:

#### 1. `test-validation` (Direct Script Testing)
Tests validation scripts directly by executing them in sequence:
- Validates Azure authentication
- Runs each validation script independently
- Continues on error to test all components
- Generates detailed test summary

#### 2. `test-reusable-workflow` (Integration Testing)
Tests the actual reusable validation workflow used by deployments:
- Calls `validate-deployment.yml` as a reusable workflow
- Tests with same parameters as actual deployments
- Validates end-to-end integration
- Skipped when `test-all-environments: true`

#### 3. `summary` (Results Aggregation)
Consolidates results from both test jobs:
- Combines outcomes
- Provides final pass/fail status
- Generates comprehensive summary

---

## 📊 Interpreting Test Outcomes

### Success Indicators

✅ **All Tests Passed:**
```
Test Validation: ✅ success
Reusable Workflow Test: ✅ success
```
- All validation components working correctly
- Safe to proceed with deployment
- Configuration is consistent

⚠️ **Partial Success with Warnings:**
```
What-If Analysis: ⚠️ RISKS DETECTED
OIDC Verification: ✅ PASSED
Config Validation: ✅ PASSED
```
- Infrastructure changes detected (may be expected)
- Review what-if output before deployment
- OIDC and config are healthy

❌ **Test Failures:**
```
Config Validation: ❌ DRIFT DETECTED
```
- Configuration inconsistencies found
- Must be fixed before deployment
- Review drift report in logs

---

## 🛠️ What Each Test Validates

### 1. Bicep What-If Analysis Test

**Script:** `validate-parameters-whatif.ps1`

**Validates:**
- ✅ Bicep template syntax is valid
- ✅ Parameter files exist and are parseable
- ✅ Resource groups can be accessed
- ✅ No unexpected deletions or modifications
- ✅ Infrastructure drift detection

**Pass Criteria:**
- Exit code 0: No high-risk changes
- Exit code 2: Deletes/modifications detected (warning)

**Failure Scenarios:**
- Missing parameter files
- Invalid Bicep syntax
- Azure authentication issues
- Resource group access denied

---

### 2. OIDC Credentials Verification Test

**Script:** `verify-oidc-credentials.ps1`

**Validates:**
- ✅ GitHub-Actions-OIDC app exists in Azure AD
- ✅ Federated credentials configured for expected environments
- ✅ Subject claims match repository and branches
- ✅ Issuer is GitHub's OIDC endpoint

**Pass Criteria:**
- All expected environments have credentials
- Subject patterns are correct
- Issuer is `https://token.actions.githubusercontent.com`

**Failure Scenarios:**
- OIDC app not found
- Missing credentials for dev/staging/main
- Incorrect subject patterns
- Azure AD permissions insufficient

---

### 3. SharedSettings Consistency Test

**Script:** `validate-sharedsettings-diff.ps1`

**Validates:**
- ✅ All sharedsettings.{env}.json files exist
- ✅ Top-level keys are consistent across environments
- ✅ Nested object structure is aligned
- ✅ No missing or extra keys between environments

**Pass Criteria:**
- All files have identical key structure
- Value differences are allowed (environment-specific)

**Failure Scenarios:**
- Missing keys in some environments
- Extra keys in some environments
- File not found or unparseable JSON
- Structural mismatches

---

## 🔄 Automated Testing (Pull Requests)

The test workflow **automatically runs** when pull requests modify:
- `.github/workflows/validate-deployment.yml`
- `Resources/Azure-Deployment/validate-*.ps1`
- `Resources/Azure-Deployment/verify-*.ps1`
- `Resources/Configuration/sharedsettings.*.json`

This ensures validation infrastructure changes are tested before merging.

---

## 🐛 Troubleshooting

### Issue: "Azure Login Failed"

**Symptoms:**
```
Error: Login failed with Error: AADSTS700016
```

**Solutions:**
1. ✅ Verify GitHub secrets are set correctly:
   - `AZUREAPPSERVICE_CLIENTID`
   - `AZUREAPPSERVICE_TENANTID`
   - `AZUREAPPSERVICE_SUBSCRIPTIONID`
2. ✅ Check OIDC app registration exists
3. ✅ Verify federated credentials for the environment
4. ✅ Ensure service principal has Contributor role

---

### Issue: "What-If Failed - Resource Group Not Found"

**Symptoms:**
```
Resource group 'rg-orderprocessing-dev' could not be found
```

**Solutions:**
1. ✅ Script auto-creates missing resource groups
2. ✅ Check Azure subscription is correct
3. ✅ Verify sufficient permissions to create resource groups
4. ✅ Review ResourceGroupPrefix parameter

---

### Issue: "Config Validation Shows Drift"

**Symptoms:**
```
Discrepancies detected:
Type: Missing  Key: AppSettings.NewFeature  Present: dev,staging  Missing: prod
```

**Solutions:**
1. ✅ Add missing keys to affected sharedsettings files
2. ✅ Ensure all environments have same top-level structure
3. ✅ Validate JSON syntax in all config files
4. ✅ Re-run test after fixes

---

### Issue: "OIDC App Not Found"

**Symptoms:**
```
GitHub-Actions-OIDC app not found; skipping test
```

**Solutions:**
1. ✅ **If using a different app name**: Set the `oidc-app-name` parameter
   ```yaml
   oidc-app-name: 'xydatalabsgithubapp'  # or your custom app name
   ```
2. ✅ Run OIDC setup: `setup-github-oidc.ps1`
3. ✅ Check Azure AD app registrations manually
4. ✅ Verify script has correct display name
5. ✅ Ensure Azure AD permissions granted

**Note:** If you created your Azure AD app with a custom name (e.g., `xydatalabsgithubapp`), you must specify it using the `oidc-app-name` parameter when running the workflow.

---

## 📦 Artifacts

After each test run, the workflow uploads artifacts containing:

**Artifact Name:** `validation-test-logs-{environment}-{run_number}`

**Contents:**
- All `.log` files generated during validation
- What-if analysis output
- OIDC verification results
- Config drift reports

**Retention:** 7 days

**Access:** Download from Actions run page → Artifacts section

---

## 🔐 Required Secrets

The test workflow requires the following GitHub secrets to be configured:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `AZUREAPPSERVICE_CLIENTID` | Service principal client ID | From Azure AD app registration |
| `AZUREAPPSERVICE_TENANTID` | Azure AD tenant ID | From Azure portal |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Target Azure subscription | From Azure portal |

**Note:** These are the same OIDC credentials used by deployment workflows (automatically configured by `bootstrap-enterprise-infra.ps1`).

---

## ✅ Best Practices

### When to Run This Test

**Always run before:**
- ✅ Modifying Bicep templates
- ✅ Updating parameter files
- ✅ Changing sharedsettings configuration
- ✅ Updating validation scripts
- ✅ Deploying to production

**Run periodically to:**
- ✅ Detect configuration drift
- ✅ Verify OIDC credentials haven't expired
- ✅ Ensure infrastructure hasn't changed unexpectedly
- ✅ Validate after Azure portal manual changes

### Continuous Integration

Consider adding this test to your CI pipeline:
1. Run on every PR to infrastructure or config files (automatic)
2. Run nightly to catch drift
3. Run before scheduled deployments
4. Run after Azure subscription changes

---

## 🔗 Related Workflows

| Workflow | Purpose | Relationship |
|----------|---------|--------------|
| `validate-deployment.yml` | Reusable validation workflow | This tests that workflow |
| `infra-deploy.yml` | Infrastructure deployment | Calls `validate-deployment.yml` |
| `test-enterprise-deployment.ps1` | Full infrastructure test | Broader testing scope |

---

## 📚 Additional Resources

### Internal Documentation
- [Validation Workflow Guide](./README-VALIDATE-DEPLOYMENT.md)
- [Infrastructure Deployment Guide](./README-INFRA-DEPLOY.md)
- [Validation Scripts Documentation](../../Resources/Azure-Deployment/README.md)

### Scripts Tested
- `validate-parameters-whatif.ps1` - Bicep what-if analysis
- `verify-oidc-credentials.ps1` - OIDC credential verification
- `validate-sharedsettings-diff.ps1` - Configuration consistency

### Azure Documentation
- [Azure Bicep What-If](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if)
- [OIDC with GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [Federated Identity Credentials](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)

---

## 📝 Maintenance

### Updating the Test Workflow

When modifying validation scripts, ensure this test workflow is updated to:
1. Test new validation parameters
2. Update expected exit codes
3. Add new test scenarios
4. Update documentation

### Version History

| Date | Change | Author |
|------|--------|--------|
| 2025-11-21 | Initial creation | GitHub Copilot |

---

## 🎓 Learning Objectives

By using this test workflow, you will learn:
- ✅ How pre-deployment validation works
- ✅ How to interpret Bicep what-if output
- ✅ How OIDC authentication is verified
- ✅ How configuration consistency is maintained
- ✅ How to debug validation failures
- ✅ Best practices for infrastructure testing

---

## 💡 Tips

1. **Start with single environment tests** before running multi-environment tests
2. **Review what-if output carefully** - not all changes are problematic
3. **Use test-all-environments sparingly** - it takes longer and consumes more resources
4. **Keep config files in sync** - use this test to catch drift early
5. **Run tests before making PR** - catch issues before code review

---

## 🆘 Support

**Need Help?**
- Check [Troubleshooting](#-troubleshooting) section above
- Review test logs in GitHub Actions
- Download artifacts for detailed error messages
- Check related documentation links
- Review validation script source code

**Found a Bug?**
- Check if validation scripts need updates
- Verify Azure permissions
- Ensure GitHub secrets are current
- Test scripts locally using PowerShell

---

## ✨ Future Enhancements

Potential improvements to this test workflow:
- [ ] Add Bicep linting validation (az bicep lint)
- [ ] Schema validation for parameter files
- [ ] Cost estimation testing
- [ ] Slack/Teams notification integration
- [ ] Automatic remediation suggestions
- [ ] Performance benchmarking
- [ ] Security scanning integration
- [ ] Drift remediation automation

---

**Questions or Feedback?**
This workflow is part of the enterprise infrastructure testing suite. For questions about usage or to suggest improvements, please refer to the [Operations Quick Links](../../Documentation/Operations-Quick-Links-README.md).
