# Infrastructure Deployment Workflow Guide

## 🎯 Overview

The `infra-deploy.yml` workflow deploys the active Azure infrastructure surface using Bicep templates.

> **Phase 10 note:** This guide describes the active Azure Container Apps deployment path for Phase 10. Legacy App Service references remain only for historical compatibility and should not be treated as the current target runtime model.

## Phase 10 Ownership

Use `phase10-deploy-orchestrator.yml` as the approval-gated lifecycle entrypoint for the Azure delivery path. It no longer builds images implicitly during deployment: a separately completed immutable release run must be selected and verified first.

- one wrapper for humans to click
- one operator entrypoint for a selected immutable release and target environment
- a separately authorized image/package publication workflow
- an internal reusable workflow for infrastructure execution
- `00 Azure Platform Foundation` owns the persistent ACR registry and pull identity

The wrapper owns the selected environment-scoped application lifecycle. Persistent platform ACR creation/provider registration is separate and owned by workflow `00`:

- `dryRun=true` runs what-if only
- `dryRun=false` and `cleanupInfra=false` deploys or updates the Phase 10 stack, creating the environment-scoped Azure resources when they are missing
- `dryRun=false` and `cleanupInfra=true` tears down the environment-scoped Phase 10 stack

SQL and Redis are explicit slices and default to **off** for routine redeploys. Turn on `deploySql` only when the SQL baseline must be created or intentionally updated; that path generates and stores a new SQL admin password. The configured Entra SQL administrator is passed explicitly and included in the reviewed deployment-identity hash. Turn on `deployRedis` only when its baseline slice must be created or intentionally updated. For a fresh environment, select the slices that are not already provisioned; for an existing environment, leave both off unless the reviewed what-if and task require them.

The workflow summary surfaces the resources that matter for runtime and cleanup:

- Resource Group
- Service Bus
- Log Analytics Workspace
- Application Insights
- Container Apps environment
- Gateway / Orders / Inventory / Notifications / UI Container Apps
- Function App
- dedicated Functions host Storage account and managed identity
- Key Vault

`00 Azure Platform Foundation` registers the Azure resource providers used by the Phase 10 platform and app stacks when `Dry Run=false`. The reusable app deploy workflow verifies that required providers are already registered. The orchestrator also verifies the configured subscription/directory, target-scope `roleAssignments/write`, and provider registration before it can route to deploy. This is read-only preflight: it never grants permissions, registers providers, creates a resource group, or deploys resources.

### Workflow Ownership Table

| workflow | click target | owns RG creation | builds images | deploys app | cleanup | current or legacy |
|---|---|---:|---:|---:|---:|---|
| `phase10-platform-foundation.yml` | yes | yes, platform RG only | no | no | no | current |
| `phase10-dev-hostname-bootstrap.yml` | yes, dev only | yes, dev RG only | no | no | no | current generated-URL prerequisite |
| `phase10-deploy-orchestrator.yml` | yes | yes, through the internal infra path | no | yes, through the internal infra path | yes | current |
| `build-phase10-images.yml` | yes, separately approval-gated release publication | no | yes | no | no | current |
| `infra-deploy.yml` | no, internal only | yes, through Bicep | no | yes | yes | current |
| `phase10-retention-cleanup.yml` | yes | no | no | no | yes, packages/artifacts only | current |
| `azure-bootstrap.yml` | yes, but legacy | yes, legacy App Service stack | no | yes, legacy API/UI apps | yes | legacy |

If you are looking for the other responsibilities in the new Phase 10 model:

- `phase10-platform-foundation.yml` owns the persistent platform ACR and runtime pull identity
- `azure-initial-setup.yml` handles one-time repository and OIDC setup
- `build-phase10-images.yml` produces a separately approved immutable release; it is not invoked implicitly by the deploy orchestrator
- `phase10-docker-dev-http-e2e.yml` handles local-vs-CI validation
- `azure-bootstrap.yml` is the only remaining legacy App Service workflow surface, and its deploy toggles are retired no-ops
- `phase10-retention-cleanup.yml` is the scheduled housekeeping workflow for historical GHCR package versions and GitHub Actions artifacts. ACR inventory is an explicit manual read-only preview; ACR deletion is disabled until digest protections are independently reviewed. It does not deploy or tear down Azure infrastructure.

It supports three execution modes:

1. **Manual immutable release publication** - Builds/pushes six images and packages Functions for the exact selected candidate SHA
2. **Wrapper-driven deployment or what-if** - Verifies the release/evidence and runs preflight before internal infrastructure execution
3. **Reusable workflow call** - Internal infrastructure invocation from the wrapper or other trusted automation

The Bicep what-if call uses Azure validation level `ProviderNoRbac`; however, the orchestrator's separate prerequisite check currently requires effective `roleAssignments/write` at the target scope because a real deployment creates the Functions storage grant. Thus dry-run is non-mutating but may still be BLOCKED when the deploy identity lacks this future-deployment prerequisite.

The current Phase 10 architecture splits ACR ownership into a persistent platform workflow and an environment-scoped app workflow. `00 Azure Platform Foundation` creates the registry and runtime pull identity once. The image-release workflow builds six service images and the Functions ZIP from one exact source SHA, verifies the release manifest, and publishes digest-qualified image references. The orchestrator verifies the producer run, artifact ownership, exact-SHA hosted CI evidence, package hash, image set, and reviewed deployment-parameter identity before Azure authentication. It does not silently build or substitute mutable image tags. Deployed Functions-package verification reads the Kudu `SitePackages/packagename.txt` pointer and the mounted ZIP over HTTPS using publishing credentials retrieved at runtime; it fails closed if SCM authentication or the expected package layout is unavailable. This verifier has not been exercised against Azure.

### Azure environment lease

The deploy orchestrator and Actions `02` runtime smoke, `03` transport/Functions smoke, and `04` payment matrix use the same `phase10-azure-${environment}` concurrency group with `queue: max` and `cancel-in-progress: false`. This prevents those operations from running simultaneously against one environment and prevents a newer run from cancelling an active deployment, migration, replay, or payment acceptance. Up to 100 pending runs wait; if the queue is full, GitHub cancels the excess run before it starts, so it produces no acceptance evidence and must be explicitly rerun if still required. Ordering is by when runs enter the queue and is not guaranteed to match dispatch time. `infra-deploy.yml` is reusable-only and is invoked under the orchestrator lease. This is an Actions-level mutual-exclusion guard, not a durable distributed lock against manual portal/CLI changes or workflows outside these four paths. See [GitHub Actions concurrency documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

Functions now uses a dedicated environment-scoped StorageV2 account and dedicated user-assigned managed identity for `AzureWebJobsStorage`; shared-key and public-blob access are disabled. The storage service endpoint is currently publicly reachable at the network layer (`publicNetworkAccess: Enabled`) and access is authorization-controlled by Entra RBAC; private networking is not implemented in this slice. The identity receives `Storage Blob Data Owner` scoped only to that storage account. The Functions deployment identity therefore requires `Microsoft.Authorization/roleAssignments/write` at the target resource-group scope or inherited scope so Bicep can create this grant. The read-only preflight checks this permission and fails closed; it never elevates the caller. The separate `Assign AcrPull` option in `00 Azure Platform Foundation` remains a privileged-only optional path and is not a substitute for the Functions storage grant.

Storage is a billable resource. Current parameters select `Standard_LRS` for dev/staging and `Standard_GRS` for prod. Review SKU, region, redundancy, quotas, and cost for the target environment before deployment. No storage account or role assignment has been provisioned by these repository changes.

Release provenance distinguishes the immutable artifact **source SHA** from the **deployment workflow SHA**. The release producer and manifest must match the source SHA exactly; that source must be an ancestor of the target branch revision running the orchestrator. Required hosted checks must pass on both exact revisions, with the deployment revision's CI evidence packet downloaded and reconciled separately. The orchestrator itself is checked out at the deployment workflow SHA, so it validates the environment's current deployment code without rebuilding or relabelling the artifact.

The preflight inventory always requires CI and drift validation, then applies the specialist workflow path rules to the union of source and deployment revision changes. Its run summary lists every required and not-applicable workflow with a reason. A missing, incomplete, failed, or cancelled required exact-SHA run blocks release verification; a path-filtered workflow is excluded only with its explicit not-applicable reason.

Promotion branch policy is `dev → dev`, `dev|staging → staging`, and `dev|staging|main → prod`; all promotions retain the same digest-qualified image references and Functions package. Cross-environment execution is still a manually selected workflow, protected by the target GitHub Environment and the separate prerequisite/deployment gates. This provenance check proves source ancestry and hosted checks; it does **not** prove that a release passed deployed staging acceptance. A staging acceptance artifact is not yet machine-enforced by the release verifier: treat staging deployment and acceptance as a mandatory operator gate before any production run. No ACR publication or Azure deployment has been performed by the local contract implementation.

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
| `00 Azure Platform Foundation` | Persistent Azure platform bootstrap | Once, then only if the shared platform foundation or provider registration must be refreshed | Shared ACR, pull identity, Azure resource-provider registration, optional privileged `AcrPull` fallback |
| `01 Phase 10 Azure Deploy Orchestrator` | App environment lifecycle | Normal deploy, dry run, or cleanup | App RG, Container Apps, Service Bus, Key Vault, App Insights, Functions |

Recommended order:

1. Run `Azure Initial Setup` if repository auth is not ready.
2. Run `00 Azure Platform Foundation` only when the shared ACR, pull identity, or provider registrations are missing. Keep `Assign AcrPull=false` for the normal path.
3. For dev generated URLs only, separately review `00a Azure Dev Hostname Bootstrap` with `dryRun=true`, then approve `dryRun=false` to create the dev RG, Log Analytics and ACA environment. Register the reported exact Entra callback/logout origins and set the matching GitHub environment variables. No generated hostname belongs in Git.
4. After separate approval, produce an immutable release for the exact reviewed candidate SHA. This publishes to ACR.
5. Review the release manifest and parameter identity, then run `01 Phase 10 Azure Deploy Orchestrator` with that release. Deployment, dry-run preflight, and cleanup are distinct choices; cleanup is destructive.

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
   | **Dry Run** | Read-only Azure preflight and Bicep what-if using selected immutable release | true/false | true |
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
   - Requests Azure authentication and performs a read-only prerequisite check plus Bicep what-if; it does not deploy or intentionally mutate resources
   - Not a substitute for reviewing the selected candidate, target, identity, provider output, or change plan
   - Requires a valid immutable release artifact and reviewed parameter identity; the source SHA must be an ancestor of the deployment workflow SHA and follow the documented environment promotion policy

   **🚀 Real Deployment:**
   - Set `Dry Run` = `false`
   - Deploys actual infrastructure
   - Creates/updates Azure resources
   - Requires successful exact-candidate hosted CI and release-artifact checks, configured OIDC, registered providers, and scoped role-assignment permission for the Functions storage identity grant
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
   - Azure dev generated mode requires `Bind Aliases=false` and exact live ACA/Entra origin agreement. Staging/prod use stable owned public names from `automation/config/runtime-targets.json`; `Public Domain` is only a compatibility fallback for newly cataloged environments.
   - Release publication is a separate run; the deployment wrapper verifies and consumes the selected exact-run artifact rather than building replacement images
   - The wrapper summary is only the top-level checkpoint; detailed deployment logs and outputs live in the internal infrastructure job
   - SQL Server and Redis are explicit opt-in slices in the wrapper; leave them off for routine redeploys, and select them only for a reviewed provisioning/update. Enabling SQL rotates the SQL admin password.

**Shared contract with local Docker validation:**
- same environment suffix pattern (`dev`, `staging`, `prod`)
- same split-service shape (gateway/orders/inventory/notifications/UI)
- same baseline SQL and Redis availability in the active Phase 10 path
- same cleanup symmetry (`appname-env` resources can be torn down safely)
- different public URL style only at the hosting layer: local Docker uses fixed localhost ports, Azure Container Apps uses generated ingress plus optional aliases
- the image release runs separately from deployment, with one job per service and a run-owned manifest that records immutable digest references

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
- ACR inventory is a manual, read-only preview in `phase10-retention-cleanup.yml`; manifest deletion is disabled until digest-safe protections are reviewed.
- Azure Log Analytics retention is configured on the workspace itself.
- Azure Container Apps image pulls use ACR with managed identity.

Default cleanup policy:

- Keep the last `10` historical GHCR package versions per image.
- Proposed ACR policy: keep at least `10` manifests and `30` days per service, plus active and verified rollback digests. No ACR manifests are currently deleted by automation.
- Keep platform ACR resources persistent. If digest cleanup is separately approved later, delete only reviewed unprotected manifests; do not use tag deletion as a proxy. Current automation deletes no ACR content.
- Workflow uploads use `14`-day artifact retention; the scheduled cleanup can remove any remaining artifacts older than `30` days.
- Scheduled cleanup deletes historical GHCR packages/artifacts only. Manual ACR inventory requires explicit opt-in and remains read-only.

| Area | Source of truth | Default |
|---|---|---|
| ACR images | `phase10-retention-cleanup.yml`, `scripts/phase10-acr-retention.mjs` | Preview only; keep latest `10`, 30 days, active digest, and one verified rollback digest per service; deletion disabled |
| GHCR images | `phase10-retention-cleanup.yml` | Keep last `10` versions per historical image |
| GitHub artifacts | workflow upload step + `phase10-retention-cleanup.yml` | `retention-days: 14` |
| Azure Log Analytics | workspace setting / Bicep / Azure policy | Managed outside the deploy wrapper |

### Enterprise platform priorities

ACR should be treated as a production prerequisite for the runtime image path, not just a convenience follow-up:

| Step | Goal | Current / Future |
|---|---|---|
| Add ACR registry | Host Phase 10 images in Azure ACR | Current Phase 10 target |
| Switch image publish path | Push digest-pinned artifacts to ACR from the separate release workflow | Current Phase 10 target |
| Switch image pull path | Let Azure Container Apps pull from ACR with Azure-native auth | Current Phase 10 target |
| SQL / Redis baseline | Deploy SQL Server and Redis as part of the default Phase 10 path | Current Phase 10 target |
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
| SQL Server | Explicit `deploySql` input, off by default on redeploy; enabling it rotates the SQL admin password | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| Redis | Explicit `deployRedis` input, off by default on redeploy | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
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

## 🔄 Deployment triggers and immutable releases

Branch pushes run hosted validation; they do not deploy Azure. The manual release workflow builds/pushes images and packages Functions for an exact source SHA. The manual orchestrator consumes that same artifact while running from a deployment-workflow SHA on the target branch, requiring source ancestry and exact hosted checks on both revisions:

| Branch | Environment | Parameter File | Trigger |
|--------|-------------|----------------|---------|
| `dev` | dev | `infra/parameters/phase10-dev.json` | Manual release + separately selected deployment |
| `dev` or `staging` | staging | `infra/parameters/phase10-staging.json` | Promote the selected immutable release after dev validation; manual deployment and separate staging acceptance |
| `dev`, `staging`, or `main` | prod | `infra/parameters/phase10-prod.json` | Manual deployment and protected environment approval; staging acceptance is a required operator gate, not yet an automated evidence input |

**Example:**
```bash
# A branch push validates code; it does not publish or deploy Azure.
# Release publication and deployment are separate, manually approved workflows.
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
Do not grant broad subscription Contributor or directory-admin rights by default. The selected deployment identity must have the resource permissions required at target scope, including `Microsoft.Authorization/roleAssignments/write` for the dedicated Functions storage identity grant. The preflight checks effective current-scope permission and provider registration read-only; it does not assign roles or elevate access. Platform foundation/provider registration and directory provisioning have separate permission requirements and approval gates.

---

## 🧪 Testing Strategy

### Step 1: Verify release and run the read-only preflight
```
Confirm exact candidate SHA, producer run, artifact identity, hosted-CI evidence, Functions package hash, and reviewed parameter identity.
Review read-only Azure preflight and Bicep what-if output carefully.
Stop for wrong subscription/directory, missing role-assignment permission, unregistered provider, unresolved diff, or unapproved cost/identity changes.
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
