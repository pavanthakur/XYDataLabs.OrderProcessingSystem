# How to Avoid Critical Configuration Errors

## 🔴 What Went Wrong

On this project, a **critical copy-paste error** occurred during workflow development where the `bootstrap-dev` job was accidentally configured with **prod environment settings**. This would have caused:

- Selecting "dev" but creating prod resources
- Using wrong parameter files (prod.json instead of dev.json)
- Catastrophic misconfiguration if not caught
- **Wasted Azure credits and ChatGPT API costs**

## 🎯 Root Causes

1. **Copy-Paste Errors**: Duplicating similar code blocks and forgetting to update all values
2. **No Automated Validation**: Changes were committed without verification
3. **Complex Multi-Replace Operations**: Using tools that modify multiple sections increases error risk
4. **Insufficient Testing**: Not running validation immediately after changes

## ✅ Prevention Strategy

### 1. **ALWAYS Run Validator Before Committing**

```powershell
# Run this EVERY TIME before committing workflow changes
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

**Exit Code 0** = Safe to commit  
**Exit Code 1** = DO NOT commit, fix errors first

### 2. **Manual Verification Checklist**

Before committing workflow changes, manually verify:

- [ ] `bootstrap-dev` calls `-Environment dev`
- [ ] `bootstrap-dev` logs show `Branch: dev`, `Environment: dev`, `dev.json`
- [ ] `bootstrap-staging` calls `-Environment staging`
- [ ] `bootstrap-staging` logs show `Branch: staging`, `Environment: staging`, `staging.json`
- [ ] `bootstrap-prod` calls `-Environment prod`
- [ ] `bootstrap-prod` logs show `Branch: main`, `Environment: prod`, `prod.json`
- [ ] OIDC setup uses `${{ inputs.environment }}`
- [ ] Configure-secrets uses `${{ inputs.environment }}`

### 3. **Test Scripts Before Azure Deployment**

```powershell
# Dry-run validation (no Azure changes)
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all
```

### 4. **Code Review Process**

When making workflow changes:

1. **Make the change** in one environment (e.g., dev)
2. **Run validator** immediately
3. **Manually verify** the specific lines changed
4. **Copy to other environments** only after validation
5. **Run validator again** after all changes
6. **Commit only if** validator passes

### 5. **Use Search/Replace Carefully**

When copying similar blocks:

```powershell
# Good: Use explicit search to verify each section
Select-String -Path .github/workflows/azure-bootstrap.yml -Pattern 'Bootstrap.*Infrastructure' -Context 5,10
```

Verify each match shows correct environment before committing.

### 6. **Incremental Commits**

Don't batch multiple changes:

```bash
# Bad: Big batch commit
git commit -m "Update all bootstrap jobs"

# Good: Individual commits with validation
# After changing dev:
./Resources/Azure-Deployment/validate-workflow-config.ps1
git add .github/workflows/azure-bootstrap.yml
git commit -m "fix: Update bootstrap-dev configuration"

# After changing staging:
./Resources/Azure-Deployment/validate-workflow-config.ps1
git commit -m "fix: Update bootstrap-staging configuration"
```

## 🛡️ What's Now in Place

### Automated Validation

**validate-workflow-config.ps1** checks:
- ✅ Each bootstrap job calls correct `-Environment` parameter
- ✅ All logging messages match their actual configurations
- ✅ OIDC setup uses dynamic `inputs.environment`
- ✅ Configure-secrets respects environment selection
- ✅ No hardcoded environment lists in wrong places

### Dry-Run Testing

**test-branch-env-mapping.ps1** validates:
- ✅ Branch-to-environment mapping for each environment
- ✅ Parameter files exist and contain correct values
- ✅ Expected OIDC subjects and resource groups
- ✅ Credential counts match selection (2 for single, 6 for all)

### Workflow Input Validation

**validate-inputs job** in workflow provides:
- ✅ Early detection of invalid environment selection
- ✅ Visual display of branch-to-environment mapping
- ✅ Shows expected resources to be created
- ✅ Validates configuration sequence

## 💰 Cost Impact

The critical error that was caught would have:
- ❌ Created prod resources when you selected dev
- ❌ Wasted Azure deployment credits
- ❌ Consumed ChatGPT API credits debugging wrong environment
- ❌ Required manual cleanup of wrong resources
- ❌ Potentially damaged production environment

**Prevention is cheaper than debugging!**

## 📋 Workflow for Agent/Developer

When asked to modify workflows:

1. **Understand the full context** of what's being changed
2. **Make changes incrementally** (one environment at a time)
3. **Run validator immediately** after each change
4. **Verify specific lines** that were modified
5. **Test with dry-run** before Azure deployment
6. **Commit only when** validator gives exit code 0

## ⚠️ Red Flags to Watch For

- ❌ "prod" mentioned in bootstrap-dev job
- ❌ "dev" mentioned in bootstrap-prod job
- ❌ Hardcoded "dev,staging,main" outside conditional blocks
- ❌ Logging messages don't match script parameters
- ❌ Parameter file (dev.json) doesn't match environment
- ❌ Branch name (main) doesn't match job name (bootstrap-dev)

## 🤝 Shared Responsibility

### Agent/Assistant Responsibilities
- ✅ Run validator after every workflow change
- ✅ Verify changes before committing
- ✅ Use incremental approach for complex changes
- ✅ Double-check copy-paste operations

### User/Developer Responsibilities  
- ✅ Review critical changes before running workflows
- ✅ Verify logs match expected configuration
- ✅ Spot-check environment mappings in PRs
- ✅ Run dry-run tests before Azure deployments

## 🎓 Lessons Learned

1. **Automation catches human errors**: The validator would have caught this immediately
2. **Visual verification is critical**: Logs showing actual configuration help catch mismatches
3. **Dry-run testing prevents waste**: Test without Azure changes first
4. **Prevention is cheaper**: Validator takes 2 seconds, debugging takes hours
5. **Incremental changes are safer**: Don't batch multiple environment changes

## 🔄 Future Improvements

Potential additions:
- [ ] Pre-commit hook to run validator automatically
- [ ] GitHub Action to run validator on PR changes to workflows
- [ ] Extended validator to check other workflow files (infra-deploy.yml, etc.)
- [ ] Integration test that deploys to test subscription first
- [ ] Notification system for critical workflow changes

---

**Remember**: Always run `validate-workflow-config.ps1` before committing workflow changes!
