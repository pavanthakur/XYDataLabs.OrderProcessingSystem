# Troubleshooting Guide Index

Quick links to troubleshooting guides for common issues with the Azure Initial Setup and Azure Bootstrap & Deploy workflows.

## 🚨 Common Issues

### GitHub App / Authentication Issues

#### ❌ "Not Found - GitHub App Token Generation Failed (404)"
**Error**: `Failed to create token for "XYDataLabs.OrderProcessingSystem" (attempt 1-4): Not Found`

**Cause**: GitHub App is not installed on this repository

**Quick Fix**:
1. Go to https://github.com/settings/installations
2. Configure your GitHub App
3. Add `XYDataLabs.OrderProcessingSystem` to repository access
4. Re-run workflow

---

#### ❌ "APP_ID and APP_PRIVATE_KEY Showing as Missing"
**Error**: 
```
APP_ID                : ❌ Missing
APP_PRIVATE_KEY       : ❌ Missing
```

**Cause**: Workflow not running in environment context, looking for repository secrets instead of environment secrets

**Quick Fix**:
1. Run workflow with specific environment selected (dev/staging/prod)
2. Don't select "all" if using environment secrets
3. Ensure workflow has latest changes with environment context

---

#### ℹ️ "What is APP_INSTALLATION_ID?"
**Question**: Do I need to configure APP_INSTALLATION_ID as a secret?

**Answer**: **No!** Installation ID is automatically discovered at runtime. The `actions/create-github-app-token@v1` action auto-discovers the installation ID via the GitHub API — only `APP_ID` and `APP_PRIVATE_KEY` are needed.

---

### Workflow Update Issues

#### ⚠️ "Workflow Update Requires Manual Action"
**Error**: `refusing to allow a GitHub App to create or update workflow without 'workflows' permission`

**Cause**: GITHUB_TOKEN lacks permission to modify workflow files (security feature)

**Solution**: Manual one-time edit required

**Quick Fix**:
1. Edit `.github/workflows/infra-deploy.yml`
2. Change `if: false  # TODO: Enable after bootstrap` to `if: (github.event_name == 'push') || ...`
3. Commit and push

**Alternative**: Grant your GitHub App "Workflows: Read and write" permission (advanced)

---

### Azure OIDC Issues

#### ❌ "Azure Login Failed"
**Error**: Azure CLI login timeout or authentication failure

**Cause**: Device code not entered within timeout window

**Quick Fix**:
1. Re-run workflow with "Setup Azure OIDC" enabled
2. Complete device code authentication within 3 minutes
3. Ensure you have proper Azure permissions

---

#### ❌ "AADSTS700213: No matching federated identity record"
**Error**: `AADSTS700213: No matching federated identity record found for presented assertion subject 'repo:...:environment:staging'`

**Cause**: The Azure AD App Registration is missing the federated identity credential for the target environment. This happens when Phase 1a was never run, or was run for a single environment instead of `all`.

**Diagnosis**: Bootstrap jobs now include a **Diagnose Azure Login Failure** step that detects this automatically and prints remediation steps in the workflow summary.

**Quick Fix**:
1. Go to **Actions → Azure Initial Setup → Run workflow**
2. Set **Use workflow from** = `dev` branch
3. Defaults are correct (environment=`all`, Phase 1a + 1b enabled) — click **Run workflow**
4. Wait for completion
5. Re-run the original **Azure Bootstrap & Deploy** workflow

---

#### ❌ "OIDC App Not Found"
**Error**: `Failed to create or find OIDC app 'GitHub-Actions-OIDC'`

**Cause**: OIDC setup script failed or insufficient Azure AD permissions

**Quick Fix**:
1. Verify you have Application Administrator role in Azure AD
2. Check Azure CLI is authenticated: `az account show`
3. Re-run workflow with "Setup Azure OIDC" enabled
4. Review OIDC setup logs

---

### SQL Managed Identity (Day 35+)

#### ❌ "Login failed for user '<token-identified principal>'" after clean deployment
**Symptom**: API starts but all DB calls return 500; App Service log shows `Login failed for user '<token-identified principal>'`.

**Cause**: After a clean redeploy (resource group deleted + recreated), the App Service gets a **new managed identity principal ID**. The old SQL contained user is gone with the deleted database. The Bicep deployment sets the AAD admin on the SQL Server, but does **not** create the contained user inside the database — that is a one-time manual step.

**Fix** — re-run the setup script (must be logged in as the AAD admin set in the parameter files):
```powershell
.\Resources\Azure-Deployment\setup-sql-managed-identity.ps1 -Environment dev
# or staging / prod
```

**When to re-run this script:**
| Scenario | Re-run needed? |
|----------|---------------|
| Regular `git push` redeploy | ❌ No |
| Bicep incremental redeploy | ❌ No |
| App Service recreated (same RG) | ✅ Yes — new principal ID |
| Full resource group teardown + recreate | ✅ Yes — new DB + new principal ID |
| First-time setup on a new environment | ✅ Yes |

**Short validation check in SSMS:**
```sql
SELECT login_name, program_name
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
	AND database_id = DB_ID('OrderProcessingSystem_Dev')
```

**Expected result:**
- After bootstrap completes and the API is called, you should see a `Core Microsoft SqlClient Data Provider` row with a GUID-like `login_name` instead of `sqladmin`.
- That GUID-like `login_name` is the expected token-based Azure AD / managed identity session.

> **Note**: `aadAdminObjectId` and `aadAdminLogin` in the parameter files never need updating — they are your permanent Azure AD user identifiers. The SQL contained user setup is automated by `azure-bootstrap.yml` on every run.

#### ❌ "Could not resolve managed identity appId" / "Insufficient privileges to complete the operation"

**Symptom**: `Azure Bootstrap & Deploy` or `Deploy API to Azure` reaches the SQL managed identity step and fails with:

- `Could not resolve managed identity appId`
- `ERROR: Insufficient privileges to complete the operation.`

**Cause**: The existing `GitHub-Actions-OIDC` app registration can authenticate to Azure Resource Manager, but it lacks Microsoft Entra read permission needed to resolve the App Service managed identity `appId/clientId`.

**Azure Portal Fix**:
1. Go to `Azure Portal -> Microsoft Entra ID -> App registrations`
2. Open `GitHub-Actions-OIDC`
3. Open `API permissions`
4. Click `Add a permission`
5. Choose `Microsoft Graph`
6. Choose `Application permissions`
7. Add `Application.Read.All`
8. Click `Grant admin consent`
9. Wait 1 to 3 minutes for propagation
10. Re-run `Azure Bootstrap & Deploy` or `Deploy API to Azure`

If the same error still appears, add `Directory.Read.All`, grant admin consent, wait briefly, and re-run the workflow.

**Do not do this for this error:**
- Do not run cleanup
- Do not recreate the resource group
- Do not rerun Azure Initial Setup unless the OIDC app registration itself was recreated

**Why the fix works:**
- SQL provisioning, Key Vault population, and EF migrations can succeed with Azure Resource Manager access only
- the SQL managed identity automation additionally needs to read Microsoft Entra service principal metadata

---

### Branch / Environment Mismatch

#### ❌ "Branch/environment mismatch"
**Error**: `ERROR: Branch 'staging' does not match expected branch for environment 'dev'`

**Cause**: The workflow requires the branch to match the environment (`dev`→dev, `staging`→staging, `main`→prod).

**Exception**: The **Azure Initial Setup** workflow (Phase 0/1a/1b) does not enforce branch/environment matching — it can be run from any branch. A recommendation message is shown if `environment` is not set to `all`.

**Quick Fix**:
- For **Azure Bootstrap & Deploy** (Phase 2/X/deploy): Use the correct branch (`dev` for dev, `staging` for staging, `main` for prod)
- For **Azure Initial Setup** (Phase 0/1a/1b): Use `branch=dev`, `environment=all` (recommended one-time setup)

---

## 📚 Setup Guides

### Initial Setup
- [QUICK-SETUP-GITHUB-APP.md](./Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md) - 4-minute GitHub App setup
- [GITHUB-APP-AUTHENTICATION.md](./Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md) - Detailed authentication guide
- Auto-discovery: Only 2 secrets needed (`APP_ID` + `APP_PRIVATE_KEY`) — installation ID is discovered at runtime

### Configuration Confirmation
- Use the **Quick Checklist** at the bottom of this page to verify your setup
- See [QUICK-START-AZURE-BOOTSTRAP.md](./Documentation/QUICK-START-AZURE-BOOTSTRAP.md) for bootstrap evaluation and setup walkthrough

---

## 🔍 How to Use This Index

1. **Find your error message** in the sections above
2. **Click the link** to the detailed troubleshooting guide
3. **Follow the Quick Fix** or read the full solution
4. **Re-run the workflow** after applying the fix

---

## 📖 Understanding the Workflow

### ❓ FAQ: What Is the GitHub App For? (Why APP_ID + APP_PRIVATE_KEY?)

**Question**: We store `APP_ID` and `APP_PRIVATE_KEY` in GitHub secrets. The GitHub App is also in GitHub. So what does the GitHub App actually DO?

**Answer**: The GitHub App is a **privileged GitHub API client** used to write secrets from inside a workflow.

| Credential | Can write GitHub secrets? | Can authenticate to Azure? |
|------------|--------------------------|---------------------------|
| `GITHUB_TOKEN` (built-in) | ❌ No — security restriction | ❌ No |
| **GitHub App installation token** | ✅ **Yes — `Secrets: write`** | ❌ No |
| Azure OIDC (`AZUREAPPSERVICE_*`) | ❌ No | ✅ **Yes — `azure/login@v2`** |

`GITHUB_TOKEN` (the automatic token every workflow run gets) does **not** have permission to write repository secrets. The GitHub App installation token — generated at runtime from `APP_ID` + `APP_PRIVATE_KEY` using `actions/create-github-app-token@v1` — **does** have `Secrets: write` permission.

So: `APP_ID` + `APP_PRIVATE_KEY` are stored so the workflow can generate a short-lived token to call `gh secret set AZUREAPPSERVICE_*`. That is their only purpose.

---

### ❓ FAQ: Why Do Phases 1b, 2, and 3 Depend on Azure OIDC?

**Question**: Why does Azure OIDC appear as a dependency in Phase 1b, 2, and 3? Can Phase 0 + 1a alone be used as prerequisites?

**Answer**: The dependency is different for each phase. Phase 1b's "dependency" is NOT the same as Phase 2 and 3.

| Phase | Azure OIDC dependency | What actually happens |
|-------|----------------------|----------------------|
| **Phase 1b** | Needs credential **values** only | Stores clientId/tenantId/subscriptionId as `AZUREAPPSERVICE_*` GitHub secrets. Does NOT authenticate to Azure. |
| **Phase 2** | Needs credentials to **authenticate** | Uses `azure/login@v2` with `AZUREAPPSERVICE_*` to log in to Azure and provision infrastructure. |
| **Phase X (cleanup)** | Needs credentials to **authenticate** | Uses `azure/login@v2` with `AZUREAPPSERVICE_*` to log in to Azure and delete resources. |
| **Deploy (API/UI)** | Needs credentials to **authenticate** | Uses `azure/login@v2` with `AZUREAPPSERVICE_*` to log in to Azure and deploy applications. |

**Phase 0 alone is NOT sufficient for Phase 1b, 2, or X:**
- Phase 0 only creates the GitHub App (for writing GitHub secrets).
- Phase 1a creates the Azure identity and produces the `clientId`/`tenantId`/`subscriptionId` values that Phase 1b stores, and that Phase 2/4/deploy use to authenticate to Azure.
- Phase 2, X, and deploy will always fail without `AZUREAPPSERVICE_*` secrets (which Phase 1b writes).

**Sequence required**: Phase 0 → Phase 1a → Phase 1b → Phase 2 → Phase 3

> **After Phase 1a + 1b run once**, Phase 1a does not need to run again. The `AZUREAPPSERVICE_*` secrets persist in GitHub and are reused by Phase 2 and Phase 3 automatically.

---

### ❓ FAQ: Is the Azure OIDC Login Shared Across Phases? Why Does It Appear Multiple Times?

**Question**: You said Phase 1b doesn't use Azure OIDC. Does that mean Phase 1a, 2, and 3 use the SAME login mechanism? Why does it appear in multiple places?

**Answer**: Yes — `azure/login@v2` with the same three OIDC credentials is the **consistent, commonized mechanism** for all Azure operations. The reason it appears in multiple jobs is a GitHub Actions architectural constraint, not a design choice.

**Why the same login call appears in every job that needs Azure:**  
GitHub Actions jobs run on completely isolated, fresh virtual machine runners. An Azure login from one job is not available to another job. Every job that needs to interact with Azure must call `azure/login@v2` independently — this is required by design, not duplication.

**Which jobs call `azure/login@v2`:**

| Job | Login called? | Login method |
|-----|--------------|--------------|
| `setup-oidc` (Phase 1a, **first-time**) | ❌ No — device code instead | `az login --use-device-code` (user enters code) |
| `setup-oidc` (Phase 1a, **re-run**) | ✅ Yes | `azure/login@v2` (same as Phase 2) |
| `configure-github-secrets` (Phase 1b) | ❌ No | GitHub App token only |
| `bootstrap-dev` (Phase 2) | ✅ Yes | `azure/login@v2` + Validate + Verify |
| `bootstrap-staging` (Phase 2) | ✅ Yes | `azure/login@v2` + Validate + Verify |
| `bootstrap-prod` (Phase 2) | ✅ Yes | `azure/login@v2` + Validate + Verify |
| `deploy-api-to-azure` | ✅ Yes | `azure/login@v2` + credential gate |
| `deploy-ui-to-azure` | ✅ Yes | `azure/login@v2` + credential gate |
| `cleanup-dev/staging/prod` (Phase X) | ✅ Yes | `azure/login@v2` + delete resources |

**The "user input → Azure token" step exists only once (Phase 1a, first-time):**  
The device-code step in Phase 1a (`az login --use-device-code`) is the single point where a human provides credentials to generate an Azure token. This runs exactly once. All subsequent logins — Phase 1a re-runs, Phase 2, Phase X, deploy — are fully automated via OIDC.

**Two login patterns used in the workflow:**
- **Phase 2 (bootstrap jobs)**: 3-step — `Validate Azure Credentials` → `Azure Login (OIDC or Secrets)` → `Verify Azure Login`. This verifies credentials before AND after the login.
- **Phase X (cleanup jobs)**: Same 3-step pattern as bootstrap.
- **Deploy jobs**: 2-step — `Check Azure Credentials` (sets a conditional flag) → `Login to Azure` (only runs if credentials are present). All subsequent deploy steps are gated on the same flag.

See: [Documentation/QUICK-START-AZURE-BOOTSTRAP.md — Azure OIDC Login IS Commonized section](./Documentation/QUICK-START-AZURE-BOOTSTRAP.md)

---

### Workflow Steps
1. **Validate Inputs** - Check configuration
2. **Setup Azure OIDC** (optional) - First-time Azure authentication setup
3. **Setup GitHub App** (optional) - One-time GitHub App setup instructions
4. **Configure Secrets** - Auto-configure GitHub secrets using GitHub App
5. **Bootstrap Infrastructure** - Deploy Azure resources
6. **Cleanup Infrastructure** (optional, destructive) - Delete all resources

### Prerequisites Validation
The workflow checks:
- ✅ OIDC setup completed (if enabled)
- ✅ GitHub App secrets present (APP_ID, APP_PRIVATE_KEY)
- ✅ GitHub App installed on repository
- ✅ GitHub App permissions (Secrets: Read and write)

### Common Failure Points
1. **Step 2 (Generate GitHub App Token)** → App not installed → See "Not Found - GitHub App Token Generation Failed (404)" section above
2. **Step 1 (Azure Login)** → Device code timeout → Re-run with "Setup OIDC" enabled

---

## 🆘 Still Having Issues?

If your issue isn't covered here:

1. **Check workflow logs**: Actions → **Azure Initial Setup** or **Azure Bootstrap & Deploy** → Failed run → View logs
2. **Review error messages**: Workflow provides detailed troubleshooting in failed steps
3. **Verify setup**: Use the **Quick Checklist** at the bottom of this page
4. **Check documentation**: Browse [Documentation/03-Configuration-Guides/](./Documentation/03-Configuration-Guides/)

---

## ✅ Success Indicators

You'll know everything is working when:

✅ **Step 1**: Prerequisite validation shows all checks passing
```
✅ OIDC credentials available
✅ All required GitHub App secrets detected
```

✅ **Step 2**: Token generation succeeds
```
✅ Status: AUTHENTICATED
ℹ️  Token: Generated (expires in 1 hour)
```

✅ **Step 3**: Secrets configured
```
✅ All repository secrets configured successfully!
✅ All environment secrets configured successfully!
```

✅ **Step 4**: Infrastructure deployed
```
✅ DEV INFRASTRUCTURE BOOTSTRAP COMPLETE
```

---

## 📋 Quick Checklist

Before running the workflow:
- [ ] GitHub App created at https://github.com/settings/apps
- [ ] GitHub App installed at https://github.com/settings/installations
- [ ] GitHub App has "Secrets: Read and write" permission
- [ ] Repository `XYDataLabs.OrderProcessingSystem` selected in installation
- [ ] `APP_ID` secret configured (repository or environment)
- [ ] `APP_PRIVATE_KEY` secret configured (full .pem file contents)
- [ ] Environment secrets: Select specific environment (dev/staging/prod) in workflow
- [ ] Azure CLI access (for first-time OIDC setup)

After successful run:
- [ ] Review workflow summary for any warnings
- [ ] Verify Azure secrets configured: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
- [ ] Check Azure resources in portal: https://portal.azure.com

---

## 🛡️ Preventing Configuration Copy-Paste Errors

### The Problem
A critical copy-paste error on this project resulted in `bootstrap-dev` being accidentally configured with prod environment settings — it would have deployed prod resources when dev was selected.

### Manual Verification Checklist (After Any Workflow Edit)
- [ ] `bootstrap-dev` calls `-Environment dev` and logs show `dev.json`
- [ ] `bootstrap-staging` calls `-Environment staging` and logs show `staging.json`
- [ ] `bootstrap-prod` calls `-Environment prod` and logs show `prod.json`
- [ ] OIDC setup uses `${{ inputs.environment }}` (dynamic, not hardcoded)
- [ ] Configure-secrets uses `${{ inputs.environment }}`

### Automated Fix
```powershell
# Run EVERY TIME before committing workflow changes
./Resources/Azure-Deployment/validate-workflow-config.ps1
# Exit Code 0 = ✅ Safe to commit | Exit Code 1 = ❌ Fix first
```

### Safe Commit Pattern
```powershell
# After each environment change (don't batch):
./Resources/Azure-Deployment/validate-workflow-config.ps1
git add .github/workflows/
git commit -m "fix: Update bootstrap-dev configuration"
```

---

## ❌ GitHub Secrets 403 Error (GITHUB_TOKEN Limitation)

### Error
```
failed to fetch public key: HTTP 403: Resource not accessible by integration
Error: Failed to set AZUREAPPSERVICE_CLIENTID
```

### Root Cause
`GITHUB_TOKEN` is read-only for secrets — it **cannot** write repository secrets. This is a GitHub security design. The workflow must use a **Personal Access Token (PAT)** with `repo` scope instead.

### Solution
1. Create a PAT at https://github.com/settings/tokens/new (scope: `repo`)
2. Add it as repository secret named `GH_PAT`
3. Re-run bootstrap workflow — it will use `GH_PAT` for `gh secret set` commands

### Secrets That Require PAT
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

These are required by `deploy-api-to-azure.yml`, `deploy-ui-to-azure.yml`, and `infra-deploy.yml` for Azure login.

---

**Last Updated**: Based on fix for GitHub App installation detection and workflow update handling.
