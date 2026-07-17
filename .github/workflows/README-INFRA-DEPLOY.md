# Infrastructure Deployment Workflow Guide

## 🎯 Overview

The `infra-deploy.yml` workflow deploys the active Azure infrastructure surface using Bicep templates.

> **Phase 10 note:** This guide describes the active Azure Container Apps deployment path for Phase 10. Legacy App Service references remain only for historical compatibility and should not be treated as the current target runtime model.

## Phase 10 Ownership

Use `phase10-deploy-orchestrator.yml` as the bootstrap-style single lifecycle owner for the Azure delivery path:

- one wrapper for humans to click
- one end-to-end sequence for deploy or cleanup
- internal reusable workflows for image build and infra execution
- `00 Azure Platform Foundation` owns the persistent ACR registry and pull identity

The active wrapper may own both the Phase 10 runtime stack and any shared foundation resources we intentionally keep in scope:

- `dryRun=true` runs what-if only
- `dryRun=false` and `cleanupInfra=false` deploys or updates the Phase 10 stack, creating the environment-scoped Azure resources when they are missing
- `dryRun=false` and `cleanupInfra=true` tears down the environment-scoped Phase 10 stack

The workflow summary surfaces the resources that matter for runtime and cleanup:

- Resource Group
- Service Bus
- Log Analytics Workspace
- Application Insights
- Container Apps environment
- Gateway / Orders / Inventory / Notifications / UI Container Apps
- Function App
- Key Vault

The reusable deploy workflow also registers the Azure resource providers it depends on before it applies the Bicep template. That includes `Microsoft.AlertsManagement`, which avoids a clean-subscription failure when Azure tries to create monitoring-related resources during deployment.

### Workflow Ownership Table

| workflow | click target | owns RG creation | builds images | deploys app | cleanup | current or legacy |
|---|---|---:|---:|---:|---:|---|
| `phase10-platform-foundation.yml` | yes | yes, platform RG only | no | no | no | current |
| `phase10-deploy-orchestrator.yml` | yes | yes, through the internal infra path | yes | yes, through the internal infra path | yes | current |
| `build-phase10-images.yml` | no, internal only | no | yes | no | no | current |
| `infra-deploy.yml` | no, internal only | yes, through Bicep | no | yes | yes | current |
| `phase10-retention-cleanup.yml` | yes | no | no | no | yes, packages/artifacts only | current |
| `azure-bootstrap.yml` | yes, but legacy | yes, legacy App Service stack | no | yes, legacy API/UI apps | yes | legacy |
| `deploy-api-to-azure.yml` | no, legacy child | no | no | yes | no | legacy |
| `deploy-ui-to-azure.yml` | no, legacy child | no | no | yes | no | legacy |

If you are looking for the other responsibilities in the new Phase 10 model:

- `phase10-platform-foundation.yml` owns the persistent platform ACR and runtime pull identity
- `azure-initial-setup.yml` handles one-time repository and OIDC setup
- `build-phase10-images.yml` handles wrapper-driven ACR image publication
- `phase10-docker-dev-http-e2e.yml` handles local-vs-CI validation
- `azure-bootstrap.yml`, `deploy-api-to-azure.yml`, and `deploy-ui-to-azure.yml` are legacy App Service workflows only and should not be treated as the active Phase 10 path
- `phase10-retention-cleanup.yml` is the scheduled housekeeping workflow for ACR image tags, historical GHCR cleanup-only image versions, and stale GitHub Actions artifacts; it does not deploy or tear down Azure infrastructure

It supports three execution modes:

1. **Wrapper-driven deployment** - Invoked by `phase10-deploy-orchestrator.yml` for the normal manual Phase 10 path
2. **Automatic validation** (pull requests) - What-if analysis only
3. **Reusable workflow call** - Internal invocation from the wrapper or other trusted automation

Dry-run What-If uses Azure validation level `ProviderNoRbac`. This keeps previews useful even when optional privileged paths exist, because preview should not fail only because the caller lacks role-assignment write permission.

The current Phase 10 architecture now splits ACR ownership into a persistent platform workflow and an environment-scoped app workflow. `00 Azure Platform Foundation` creates the registry and runtime pull identity once. `01 Phase 10 Azure Deploy Orchestrator` consumes the ACR and prepares a scoped pull token for Container Apps, so the normal deploy path does not create registry RBAC inside the app resource group.

The normal app deploy identity should not need `roleAssignments/write` for Phase 10. The `Assign AcrPull` option in `00 Azure Platform Foundation` is a privileged-only fallback for teams that explicitly choose managed-identity registry pulls.

Use this setting as follows:

| Input | Recommended use |
|---|---|
| `Assign AcrPull = false` | Default for the normal enterprise path. Use this for Phase 10 platform bootstrap and all routine redeploys. |
| `Assign AcrPull = true` | Only for a privileged platform-admin run that already has `roleAssignments/write` and intentionally wants the platform workflow to create the ACR pull grant. |

If you are following the current Phase 10 normal path, leave `Assign AcrPull` set to `false`.

### Initial Setup vs Platform Foundation

These workflows overlap in that they are both bootstrap-style, but they own different trust boundaries:

| Workflow | Primary purpose | Runs when | Owns |
|---|---|---|---|
| `Azure Initial Setup` | Repository and auth bootstrap | First-time repo setup, or when GitHub App / OIDC secrets must be recreated | GitHub App, Azure OIDC app registration, GitHub environment secrets |
| `00 Azure Platform Foundation` | Persistent Azure platform bootstrap | Once, then only if the shared platform foundation changes | Shared ACR and pull identity; optional privileged `AcrPull` fallback |
| `01 Phase 10 Azure Deploy Orchestrator` | App environment lifecycle | Normal deploy, dry run, or cleanup | App RG, Container Apps, Service Bus, Key Vault, App Insights, Functions |

Recommended order:

1. Run `Azure Initial Setup` if repository auth is not ready.
2. Run `00 Azure Platform Foundation` once to create the shared ACR and pull identity. Keep `Assign AcrPull=false` for the normal path.
3. Run `01 Phase 10 Azure Deploy Orchestrator` for normal deploys and cleanups.

Do not merge `Azure Initial Setup` with `00 Azure Platform Foundation` unless you deliberately want a single high-privilege bootstrap path. Keeping them separate preserves cleaner ownership and a smaller blast radius.

---

## 🚀 Wrapper-Driven Deployment (Recommended for Testing)

### How to Run from GitHub UI

1. **Navigate to Actions Tab:**
   - Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
   - Find: "Phase 10 Deploy Orchestrator"

2. **Click "Run workflow" button** (top right)

3. **Configure Parameters:**

   | Parameter | Description | Options | Default |
   |-----------|-------------|---------|---------|
   | **Environment** | Target environment | dev, staging, prod | dev |
   | **Location** | Azure region | Any region string | centralindia |
| **Dry Run** | What-if only (no deploy) | true/false | true |
| **Cleanup Infra** | Destructive teardown of the environment-scoped resource group | true/false | false |
| **Public Domain** | Optional DNS suffix for friendly aliases | Any real domain suffix | empty |
| **Bind Aliases** | Enable alias planning / binding checks | true/false | false |
| **Alias Mode** | Choose direct ACA binding or front-door planning | direct / frontdoor | direct |

   Alias guidance:

   - Leave `Public Domain` empty and `Bind Aliases=false` for your first dry run.
   - Use `Alias Mode=direct` when you want a custom domain to point straight at the Container App ingress.
   - Use `Alias Mode=frontdoor` when you want the workflow to stay in planning mode for a DNS or Front Door layer you manage separately.
   - Only enable `Bind Aliases=true` after the base deployment works and you have a real domain suffix to use.

4. **Run Types:**

   **🧪 Dry Run (What-If Analysis):**
   - Set `Dry Run` = `true`
   - Reviews changes without deploying
   - Safe to run anytime
   - No Azure resources created/modified

   **🚀 Real Deployment:**
   - Set `Dry Run` = `false`
   - Deploys actual infrastructure
   - Creates/updates Azure resources
   - Works for a clean environment as long as the GitHub OIDC secrets are configured
   - **Use carefully!**

   **🗑️ Cleanup / Teardown:**
   - Set `Dry Run` = `false`
   - Set `Cleanup Infra` = `true`
   - Deletes the environment-scoped resource group for the selected environment
   - Use this only when you want to remove the full Phase 10 stack

**Current Azure Deployment:**
   - Uses `infra/main.phase10.bicep` and `infra/parameters/phase10-<env>.json`
   - Resources follow the environment-suffixed naming pattern so Phase X cleanup can remove the matching stack
   - Gateway, Orders, Inventory, Notifications, and UI are deployed as separate Container Apps with separate images, matching the split-service Docker validation lane
   - The workflow summary shows transport-stack outputs and any wrapper-owned shared foundation outputs we choose to keep in scope
   - If `Bind Aliases` is enabled, provide a real `Public Domain` so the workflow can derive env-aware public names like `api-dev.contoso.com`
   - The wrapper execution order is intentionally `preflight -> build images -> internal deploy or cleanup -> summary`, so a real run should show the image job before the internal infra workflow in Actions
   - The wrapper summary is only the top-level checkpoint; detailed logs and outputs live in the nested build and infra jobs under the run
   - If you need per-service image logs or deployment traceability, open the child jobs under the wrapper rather than relying on the top-level summary alone

**Shared contract with local Docker validation:**
- same environment suffix pattern (`dev`, `staging`, `prod`)
- same split-service shape (gateway/orders/inventory/notifications/UI)
- same cleanup symmetry (`appname-env` resources can be torn down safely)
- different public URL style only at the hosting layer: local Docker uses fixed localhost ports, Azure Container Apps uses generated ingress plus optional aliases
- the image build stage is intentionally grouped into one wrapper step with one individual log block per service, so exported run logs may be consolidated even though the Actions UI still shows each service build separately

**Related validation gate:**
- `phase10-docker-dev-http-e2e.yml` runs the same hook-based Docker Dev HTTP sequence in CI and uploads the matching `TestResults/Playwright/phase10-docker-http` artifacts.
- Use the hook as the merge gate for the local Docker validation chain, and use `phase10-deploy-orchestrator.yml` to drive `infra-deploy.yml` for Azure Container Apps deployment and alias planning.
- Use the same workflow with `Cleanup Infra=true` to tear down the environment-scoped Phase 10 stack when you want to reset the environment.

### Cleanup and Retention Boundaries

Phase 10 cleanup is intentionally scoped to the Azure environment stack:

- `Cleanup Infra=true` deletes the environment-scoped Azure resource group and the resources inside it.
- `Cleanup Infra=true` does **not** delete container images that were published by the build workflow.
- In the target platform foundation model, `Cleanup Infra=true` also does **not** delete the platform ACR or the stable pull identity.
- `Cleanup Infra=true` does **not** purge historical GitHub Actions logs or artifacts beyond the repository retention settings.
- `Cleanup Infra=true` does **not** change Azure Log Analytics or Application Insights retention policies.

If image or log storage needs active housekeeping, add a separate scheduled cleanup workflow or retention policy for that storage layer. Keep that concern separate from the deployment wrapper so the deploy path stays predictable.

Source-of-truth controls:

- GitHub Actions artifact retention is set per upload step where practical.
- Historical GHCR package retention is handled by `phase10-retention-cleanup.yml` for cleanup-only packages.
- ACR image retention is handled by `phase10-retention-cleanup.yml` for the active Phase 10 runtime image path.
- Azure Log Analytics retention is configured on the workspace itself.
- Azure Container Apps image pulls use ACR with managed identity.

Default cleanup policy:

- Keep the last `10` historical GHCR package versions per image.
- Keep the last `10` ACR tags per service image, skip tags referenced by active Container App revisions, and delete stale tags older than `30` days.
- Keep platform ACR resources persistent; prune image tags, not the registry.
- Delete GitHub Actions artifacts older than `14` days.
- Run the scheduled cleanup workflow in delete mode, but keep the manual `workflow_dispatch` entry in dry-run mode unless you explicitly disable it for an audit run.

| Area | Source of truth | Default |
|---|---|---|
| ACR images | `phase10-retention-cleanup.yml` | Keep last `10` tags per service and preserve active revision images |
| GHCR images | `phase10-retention-cleanup.yml` | Keep last `10` versions per historical image |
| GitHub artifacts | workflow upload step + `phase10-retention-cleanup.yml` | `retention-days: 14` |
| Azure Log Analytics | workspace setting / Bicep / Azure policy | Managed outside the deploy wrapper |

### Enterprise platform priorities

ACR should be treated as a production prerequisite for the runtime image path, not just a convenience follow-up:

| Step | Goal | Current / Future |
|---|---|---|
| Add ACR registry | Host Phase 10 images in Azure ACR | Current Phase 10 target |
| Switch image publish path | Push build artifacts to ACR from the wrapper build step | Current Phase 10 target |
| Switch image pull path | Let Azure Container Apps pull from ACR with Azure-native auth | Current Phase 10 target |
| Historical GHCR cleanup | Keep only the cleanup-only path for old package versions | Retained for retention workflow |
| Historical GHCR runtime token | No longer needed for the active Phase 10 runtime image path | Completed for active deploy path |

Target end state:

- `GitHub-Actions-OIDC` remains the Azure login path
- GitHub App remains the repository automation path
- ACR becomes the runtime image registry
- `GHCR_READ_TOKEN` is no longer needed for active Phase 10 container pulls
- Managed identity becomes the normal runtime identity pattern for Azure resources
- Front Door / WAF becomes the preferred public ingress layer when public exposure is required

### Containerized parity follow-up plan

If the goal is to make the Azure Portal experience match the local Docker container graph, the CI/CD path needs an explicit parity plan:

Use [docs/internal/phase10-parity-matrix.md](../../docs/internal/phase10-parity-matrix.md) as the source-of-truth table for the SQL, Redis, ACR, and cleanup ownership split before changing the Azure workflow chain.

| Need | What to add back or decide | Workflow touchpoint |
|---|---|---|
| SQL Server | Reintroduce the SQL module and surface its outputs in the deployment summary | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| Redis | Add an Azure Cache for Redis module and wire its connection details into app settings | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| App Service URLs | Not part of the active containerized target; use friendly aliases / Front Door names for Container Apps | alias planning in `infra-deploy.yml` |
| Portal visibility | Summarize the live portal endpoints and resource inventory in one run summary | wrapper summary + internal deployment summary |

Rule of thumb:
- the active target is the containerized solution, not the old App Service runtime model
- Container Apps means friendly aliases or Front Door, not App Service hostnames
- SQL and Redis must be intentionally reintroduced into the active Bicep/workflow chain if they are required in Azure

### Enterprise Guardrails

Treat the following as the default architecture review checklist for any new Phase 10 implementation or follow-up change:

| Guardrail | Default expectation |
|---|---|
| Identity | Use Azure OIDC for Azure login; never add stored Azure client secrets |
| Registry | Prefer ACR for Azure runtime image pulls; historical GHCR remains cleanup-only |
| GitHub automation | Use the GitHub App for repo-secret automation only |
| Cleanup | Every deployable resource must have a matching cleanup path |
| Naming | Use env-suffixed names consistently (`appname-env`) for deploy and cleanup symmetry |
| Retention | Set retention at the source for images, artifacts, and logs; do not rely on manual cleanup |
| Summaries | Every workflow must expose a top-level summary and child-job traceability links |
| Review stance | Treat enterprise fit as the default: Azure-native when practical, exceptions documented explicitly |

If a new implementation deviates from these defaults, document the exception in the relevant workflow or ADR and give it a follow-up closure trigger.

---

## 📋 Example Scenarios

### Scenario 1: Test Infrastructure Changes (Safe)
```
Environment: dev
Location: centralindia
Dry Run: TRUE ✅
```
**Result:** Shows what would be deployed, no actual changes

### Scenario 2: Deploy Dev Environment
```
Environment: dev
Location: centralindia
Dry Run: FALSE ⚠️
```
**Result:** Creates or updates the dev environment in Azure

### Scenario 3: Deploy Staging
```
Environment: staging
Location: centralindia
Dry Run: FALSE ⚠️
```
**Result:** Creates separate staging environment

---

## 🔄 Automatic Deployment (Push-Based)

When you push to specific branches:

| Branch | Environment | Parameter File | Trigger |
|--------|-------------|----------------|---------|
| `dev` | dev | `infra/parameters/phase10-dev.json` | Any push to `infra/**` |
| `staging` | staging | `infra/parameters/phase10-staging.json` | Any push to `infra/**` |
| `main` | prod | `infra/parameters/phase10-prod.json` | Any push to `infra/**` |

**Example:**
```bash
# Make changes to Bicep files
git add infra/main.phase10.bicep
git commit -m "Update infrastructure"
git push origin dev  # Triggers automatic deployment
```

---

## 🔍 Validation (Pull Requests)

When you create a PR with infra changes:

1. Workflow runs automatically
2. Detects the active infrastructure files and runs the matching `what-if`
3. Shows predicted changes in PR comments
4. **No actual deployment** occurs

**Example:**
```bash
git checkout -b feature/add-storage
# Make changes to infra
git push origin feature/add-storage
# Open PR to dev → Validation runs
```

---

## 📊 Deployment Outputs

After successful deployment, the workflow provides:

### GitHub Actions Summary
- Environment details
- Deployment name
- Resource links
- Next steps

### Available Outputs
- **Resource Group Name:** `rg-orderprocessing-{env}`
- **Service Bus Namespace:** `sb-orderprocessing-{env}`
- **Log Analytics Workspace:** workspace name
- **Managed Environment:** container apps environment
- **Gateway / Orders / Inventory / Notifications / UI:** container app names
- **Function App:** function host name
- **Key Vault:** vault name
- **App Insights Name:** `ai-orderprocessing-{env}`

- Resource Group
- Service Bus Namespace
- Log Analytics Workspace
- Managed Environment
- Gateway / Orders / Inventory / Notifications / UI container app names
- Function App
- Key Vault
- App Insights

---

## 🛠️ Prerequisites

### Required GitHub Secrets
These must be configured in repository settings:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AZUREAPPSERVICE_CLIENTID` | App Registration Client ID | Run `setup-github-oidc.ps1` |
| `AZUREAPPSERVICE_TENANTID` | Azure AD Tenant ID | `az account show --query tenantId -o tsv` |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Azure Subscription ID | `az account show --query id -o tsv` |

**Setup Command:**
```powershell
# From project root
.\Resources\Azure-Deployment\setup-github-oidc.ps1 -Environment dev
```

### Azure Permissions
The service principal needs:
- **Contributor** role on subscription (for resource creation)
- **(Optional)** Directory permissions for identity module

---

## 🧪 Testing Strategy

### Step 1: Dry Run Everything First
```
Always start with Dry Run = TRUE
Review what-if output carefully
Check for unexpected changes
```

### Step 2: Deploy to Dev
```
Environment: dev
Dry Run: FALSE
Verify in Azure Portal
Test endpoints
```

### Step 3: Promote to Higher Environments
```
If dev works → deploy staging
If staging works → deploy prod
```

---

## ⚠️ Important Notes

### Identity Module Limitation
The `identity.bicep` module requires a **User-Assigned Managed Identity** with Microsoft Graph permissions. 

**Current Workaround:**
1. Set `Enable Identity = false` in manual runs
2. Run `setup-github-oidc.ps1` script manually instead
3. Or create the UAMI with proper permissions before deploying

**Why:** Bicep deployment scripts need elevated permissions to create App Registrations and federated credentials.

### Cost Considerations

| SKU | Cost | Best For |
|-----|------|----------|
| F1 | Free | Dev/testing (limited) |
| B1 | ~$13/month | Dev/small apps |
| B2 | ~$26/month | Staging |
| S1 | ~$69/month | Production |
| P1v3 | ~$146/month | High-performance prod |

**Tip:** Always use F1 or B1 for learning/dev!

### Resource Naming
Phase 10 resources are named with the environment-suffixed pattern:
```
{component}-{environment}
```

Examples:
```
orderprocessing-gate-dev
orderprocessing-ui-dev
sb-orderprocessing-dev
kv-orderprocessing-dev
```

This keeps deployment and cleanup aligned with the exact environment that was deployed.

---

## 🐛 Troubleshooting

### Issue: "Deployment script failed"
**Cause:** Identity module needs managed identity  
**Solution:** Set `Enable Identity = false` or use `setup-github-oidc.ps1`

### Issue: "What-if shows unexpected deletions"
**Cause:** Parameter mismatch  
**Solution:** Review parameter values, ensure they match existing resources

### Issue: "Unauthorized to perform action"
**Cause:** Missing RBAC permissions  
**Solution:** Verify service principal has Contributor role

### Issue: "Name already taken"
**Cause:** Resource name collision  
**Solution:** Check the environment suffix and ensure the target stack was cleaned up before redeploying

---

## 📚 Related Documentation

- **Migration Plan:** `docs/guides/deployment/aca-migration-plan.md`
- **Bicep README:** `infra/README.md`
- **OIDC Setup:** `Resources/Azure-Deployment/README.md`
- **Master Curriculum:** `docs/learning/curriculum/1_MASTER_CURRICULUM.md`

---

## 🎓 Learning Path

This workflow corresponds to:
- **Day 29-31:** Bicep modules and infrastructure deployment
- **Week 5-8:** Infrastructure as Code & CI/CD hardening
- **Phase 2:** Enterprise App Service Deployment

**Next Steps:**
1. Run dry run to understand what-if output
2. Deploy dev environment
3. Verify resources in Azure Portal
4. Move to containerization (Week 9)

---

## 📞 Quick Commands

### Check Workflow Status
```bash
gh workflow list
gh workflow view "Phase 10 Deploy Orchestrator"
gh run list --workflow=infra-deploy.yml
```

### Trigger Manual Run (via CLI)
```bash
gh workflow run phase10-deploy-orchestrator.yml \
  -f environment=dev \
  -f location=centralindia \
  -f dryRun=true
```

### View Latest Run
```bash
gh run view
```

---

**Last Updated:** November 21, 2025  
**Status:** ✅ Ready for manual testing
