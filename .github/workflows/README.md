# GitHub Actions Workflows - CI/CD Automation

This directory contains GitHub Actions workflows for automated CI/CD deployment to Azure App Services using OIDC authentication.

## 📋 Overview

**Component-based deployment workflows** that automatically build, test, and deploy when specific parts of the codebase change:

| Workflow | Triggers On | Deploys To | Description |
|----------|-------------|------------|-------------|
| `azure-initial-setup.yml` | Manual | One-time setup | **[See README-AZURE-INITIAL-SETUP.md](./README-AZURE-INITIAL-SETUP.md)** - Phase 0 (GitHub App), Phase 1a (OIDC), Phase 1b (secrets) |
| `azure-bootstrap.yml` | Manual | Infrastructure + deploy | **[See README-AZURE-BOOTSTRAP.md](./README-AZURE-BOOTSTRAP.md)** - Phase 2 (infrastructure), API/UI deploy, Phase X (cleanup) |
| `configure-github-secrets.yml` | Called by initial-setup | Secret configuration | **[See README-CONFIGURE-GITHUB-SECRETS.md](./README-CONFIGURE-GITHUB-SECRETS.md)** - GitHub App setup and secret management (can run independently) |
| `infra-deploy.yml` | Manual | dev/staging/prod | **[See README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)** - Deploys Bicep infrastructure with manual workflow dispatch |
| `validate-deployment.yml` | Called by infra-deploy | Reusable workflow | **[See README-VALIDATE-DEPLOYMENT.md](./README-VALIDATE-DEPLOYMENT.md)** - Pre-deployment validation workflow |
| `test-validate-deployment.yml` | Manual or PR changes | Test only | **[Quick Start](./QUICK-START-TEST-VALIDATION.md)** \| **[Full Docs](./README-TEST-VALIDATE-DEPLOYMENT.md)** - Tests validation workflow independently |
| `deploy-api-to-azure.yml` | API/Backend code changes | All branches (dev/staging/main) | Builds and deploys API to environment-specific Azure Web App |
| `deploy-ui-to-azure.yml` | UI/Frontend code changes | All branches (dev/staging/main) | Builds and deploys UI to environment-specific Azure Web App |
| `docker-health.yml` | Docker script changes | main branch only | Validates Docker startup scripts |
| `validate-adrs.yml` | ADR file, script, or lint config changes | Push/PR to main/dev/staging, or manual | **[See README-VALIDATE-ADRS.md](./README-VALIDATE-ADRS.md)** — Validates ADR filename pattern, H1 heading, `**Status:**` frontmatter, and markdownlint rules |

### Branch-to-Environment Mapping

| Git Branch | API Deployment Target | UI Deployment Target |
|------------|----------------------|---------------------|
| `dev` | orderprocessing-api-xyapp-dev | orderprocessing-ui-xyapp-dev |
| `staging` | orderprocessing-api-xyapp-stg | orderprocessing-ui-xyapp-stg |
| `main` | orderprocessing-api-xyapp-prod | orderprocessing-ui-xyapp-prod |

Workflow YAML still enforces this policy explicitly.
Azure deployment scripts consume the same defaults from `Resources/Azure-Deployment/branch-policy.json`; if governance changes, update the workflow guards and the shared policy file together.

---

## 🔐 Required GitHub Secrets

Before workflows can execute, the following repository secrets **must be configured**:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AZUREAPPSERVICE_CLIENTID` | Azure AD App Registration Client ID | Run `bootstrap-enterprise-infra.ps1` (auto-configured) |
| `AZUREAPPSERVICE_TENANTID` | Azure AD Tenant ID | From Azure subscription |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Azure Subscription ID | From Azure subscription |

### Automatic Secret Configuration

If you ran `bootstrap-enterprise-infra.ps1` with GitHub CLI installed and authenticated, secrets are **already configured**.

Verify at: https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions

### Manual Secret Configuration

If automatic configuration failed:

1. **Copy secrets** (they were copied to clipboard during bootstrap script execution)
2. **Navigate to**: Repository → Settings → Secrets and variables → Actions → New repository secret
3. **Add each secret** with exact names shown above

---

## 🚀 Workflow Execution

### Automatic Triggers

Workflows trigger automatically based on **what code changed**:

```bash
# Change API code and push → triggers deploy-api-to-azure.yml
git add XYDataLabs.OrderProcessingSystem.API/
git commit -m "feat: Update API endpoint"
git push origin dev  # Deploys API only to dev environment

# Change UI code and push → triggers deploy-ui-to-azure.yml
git add XYDataLabs.OrderProcessingSystem.UI/
git commit -m "feat: Update UI styling"
git push origin dev  # Deploys UI only to dev environment

# Change both API and UI → triggers BOTH workflows in parallel
git add XYDataLabs.OrderProcessingSystem.API/ XYDataLabs.OrderProcessingSystem.UI/
git commit -m "feat: Update API and UI"
git push origin dev  # Deploys both API and UI to dev environment
```

### Path-Based Triggering

**API Workflow** (`deploy-api-to-azure.yml`) triggers on changes to:
- `XYDataLabs.OrderProcessingSystem.API/**`
- `XYDataLabs.OrderProcessingSystem.Application/**`
- `XYDataLabs.OrderProcessingSystem.Domain/**`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/**`
- `XYDataLabs.OrderProcessingSystem.SharedKernel/**`

**UI Workflow** (`deploy-ui-to-azure.yml`) triggers on changes to:
- `XYDataLabs.OrderProcessingSystem.UI/**`
- `XYDataLabs.OrderProcessingSystem.Application/**`
- `XYDataLabs.OrderProcessingSystem.Domain/**`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/**`
- `XYDataLabs.OrderProcessingSystem.SharedKernel/**`

**Docker Workflow** (`docker-health.yml`) triggers on:
- Any push to `main` branch
- Pull requests targeting `main` branch

### Pull Request Behavior

**IMPORTANT**: Workflows do **NOT** trigger on Pull Request events.

- ❌ Opening a PR does **not** trigger deployment
- ❌ Merging a PR via GitHub UI does **not** trigger deployment (unless merge creates a push event)
- ✅ Merging via command line with push **does** trigger deployment:
  ```bash
  git checkout staging
  git merge dev
  git push origin staging  # ← This triggers deploy-staging.yml
  ```

### Manual Triggers

Workflows can be triggered manually via GitHub Actions UI:

1. Navigate to: **Actions** tab → Select workflow
2. Click **Run workflow** button
3. Select branch → Click **Run workflow**

---

## 📦 Workflow Stages

Both API and UI workflows execute in 2 stages:

### Stage 1: Build (Windows Runner)
- ✅ Checkout code
- ✅ Setup .NET 8 SDK
- ✅ Restore NuGet packages for specific project
- ✅ Build project (Release configuration)
- ✅ **Run unit tests** (entire test suite)
- ✅ Publish project
- ✅ Upload build artifact

### Stage 2: Deploy (Windows Runner)
- ✅ Determine target environment (dev/staging/prod) from branch name
- ✅ Download build artifact
- ✅ Login to Azure using OIDC (passwordless authentication)
- ✅ Deploy to environment-specific Azure Web App
- ✅ Wait 30 seconds for service stabilization
- ✅ Run health checks (API: `/` + `/swagger`, UI: `/`)
- ✅ Display deployment URLs

---

## 🔍 Monitoring Deployments

### View Workflow Runs

Navigate to: https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions

### Workflow Status Badges

Add to README.md:

```markdown
## Deployment Status

[![Deploy Dev](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-dev.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-dev.yml)

[![Deploy Staging](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-staging.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-staging.yml)

[![Deploy Production](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-main.yml/badge.svg)](https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions/workflows/deploy-main.yml)
```

---

## 🛠️ Customization

### Smart Path Filtering

Workflows use **path-based triggering** - they only run when relevant code changes:

**Benefits:**
- ✅ **Efficiency**: Documentation changes don't trigger deployments
- ✅ **Speed**: Only affected components are deployed
- ✅ **Cost**: Fewer workflow minutes consumed
- ✅ **Safety**: Isolated deployments reduce blast radius

**Example Scenarios:**

```bash
# Scenario 1: Only API code changed
# Changed: XYDataLabs.OrderProcessingSystem.API/Controllers/OrderController.cs
# Result: Only deploy-api-to-azure.yml runs ✅

# Scenario 2: Only UI code changed  
# Changed: XYDataLabs.OrderProcessingSystem.UI/Pages/Index.razor
# Result: Only deploy-ui-to-azure.yml runs ✅

# Scenario 3: Shared domain model changed
# Changed: XYDataLabs.OrderProcessingSystem.Domain/Entities/Order.cs
# Result: BOTH workflows run (API and UI depend on Domain) ✅

# Scenario 4: Documentation updated
# Changed: Documentation/README.md
# Result: NO workflows run (documentation changes ignored) ✅
```

### Changing Web App Names

If you used custom names during bootstrap, update `app-name` in workflows:

```yaml
- name: Deploy to Azure Web App (API)
  uses: azure/webapps-deploy@v3
  with:
    app-name: 'YOUR-CUSTOM-API-NAME-dev'  # ← Update here
    package: ./api
```

---

## 🔒 Security Best Practices

### OIDC Authentication

Workflows use **OpenID Connect (OIDC)** for Azure authentication:

- ✅ No long-lived secrets stored in GitHub
- ✅ Short-lived tokens (1 hour expiration)
- ✅ Federated credentials tied to specific branches
- ✅ Principle of least privilege (Contributor role on Resource Group only)

### Permissions

Workflows require minimal permissions:

```yaml
permissions:
  id-token: write    # Required for OIDC token request
  contents: read     # Required to checkout code
```

### Service Principal Scope

The OIDC service principal has:
- **Role**: Contributor
- **Scope**: Resource Group level only (not subscription-wide)
- **Branches**: Separate federated credentials derived from the shared branch policy (currently dev, staging, main)

---

## 🧪 Testing Workflows

### Test Without Deployment

To test workflow syntax without deploying:

1. **Fork the repository** to your personal account
2. **Update workflow files** with your test app names
3. **Push to test branch**
4. **Observe workflow execution** (it will fail at deployment but validate syntax)

### Local Workflow Validation

Install `act` to run workflows locally:

```bash
# Install act (Windows)
winget install nektos.act

# Test dev workflow
act push -W .github/workflows/deploy-dev.yml
```

**Note**: Local execution won't have Azure credentials, but validates syntax.

---

## 🐛 Troubleshooting

### Workflow Not Triggering

**Problem**: Pushed to branch but workflow didn't run

**Solutions**:
1. ✅ Check branch name matches the enforced workflow mapping (`dev`, `staging`, `main` by default)
2. ✅ Verify push succeeded: `git push origin dev --verbose`
3. ✅ Check if changes were in ignored paths (Documentation, .md files)
4. ✅ View Actions tab for any disabled workflows

### Authentication Failed

**Problem**: `Error: Login failed with Error: AADSTS700016: Application not found`

**Solutions**:
1. ✅ Verify GitHub secrets are configured correctly
2. ✅ Check OIDC App Registration exists in Azure AD
3. ✅ Verify federated credentials for branch exist
4. ✅ Re-run `bootstrap-enterprise-infra.ps1` to recreate OIDC setup

### Deployment Failed

**Problem**: Build succeeded but deployment failed

**Solutions**:
1. ✅ Check Azure Web App exists and is running
2. ✅ Verify app name in workflow matches actual Azure resource
3. ✅ Check RBAC role assignments (Service Principal needs Contributor role)
4. ✅ Review Azure App Service logs for deployment errors

### Build Failed

**Problem**: Build stage fails with compilation errors

**Solutions**:
1. ✅ Verify solution builds locally: `dotnet build XYDataLabs.OrderProcessingSystem.sln`
2. ✅ Check all NuGet packages are restored
3. ✅ Review build logs in GitHub Actions for specific error
4. ✅ Ensure .NET 8 SDK is used (workflow specifies `dotnet-version: '8.0.x'`)

---

## 📚 Additional Resources

### GitHub Actions Documentation
- [GitHub Actions Overview](https://docs.github.com/actions)
- [Workflow Syntax](https://docs.github.com/actions/reference/workflow-syntax-for-github-actions)
- [Azure Login Action](https://github.com/marketplace/actions/azure-login)
- [Azure WebApps Deploy Action](https://github.com/Azure/webapps-deploy)

### Azure Documentation
- [Azure OIDC with GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [Azure App Service Deployment](https://learn.microsoft.com/azure/app-service/deploy-github-actions)
- [Federated Identity Credentials](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)

### Internal Documentation
- **[Infrastructure Deployment Guide](./README-INFRA-DEPLOY.md)** ⭐ Manual Bicep deployment with dry run
- [Bootstrap Workflow Summary](../../Documentation/Bootstrap-Workflow-Summary.md)
- [Azure Deployment Guide](../../Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md)
- [Master Curriculum](../../Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md)

---

## 📝 Workflow Change Log

| Date | Workflow | Change | Author |
|------|----------|--------|--------|
| 2025-11-21 | test-validate-deployment.yml | Added test workflow for pre-deployment validation | GitHub Copilot |
| 2025-11-20 | All | Initial creation with OIDC authentication | GitHub Copilot |

---

## ✅ Next Steps

### For Testing Validation Workflow (New!)
**👉 Start here to test pre-deployment validation:**
1. **Read the guide**: [README-TEST-VALIDATE-DEPLOYMENT.md](./README-TEST-VALIDATE-DEPLOYMENT.md)
2. **Run validation test**: Go to Actions → Test Pre-Deployment Validation → Run workflow
3. **Review test results**: Check for configuration drift or issues

### For Infrastructure Deployment
**👉 After validation tests pass:**
1. **Read the guide**: [README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)
2. **Run dry run**: Go to Actions → Deploy Azure Infrastructure → Run workflow
3. **Deploy infrastructure**: Set dry run = false after validation

### For Application Deployment
After infrastructure is deployed:

1. **Verify secrets configured**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

2. **Test dev workflow**:
   ```bash
   git checkout dev
   git commit --allow-empty -m "test: Trigger dev workflow"
   git push origin dev
   ```

3. **Monitor workflow**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

4. **Verify deployment**: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net

5. **Promote to staging** (after dev validation):
   ```bash
   git checkout staging
   git merge dev
   git push origin staging
   ```

---

**Questions or Issues?** 
- Validation Testing: See [README-TEST-VALIDATE-DEPLOYMENT.md](./README-TEST-VALIDATE-DEPLOYMENT.md)
- Pre-Deployment Validation: See [README-VALIDATE-DEPLOYMENT.md](./README-VALIDATE-DEPLOYMENT.md)
- Infrastructure: See [README-INFRA-DEPLOY.md](./README-INFRA-DEPLOY.md)
- Application Deployment: Check [Bootstrap Workflow Summary](../../Documentation/Bootstrap-Workflow-Summary.md)
- Full Learning Path: [Master Curriculum](../../Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md)
