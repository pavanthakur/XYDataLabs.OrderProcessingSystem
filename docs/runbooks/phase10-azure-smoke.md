# Phase 10 Azure Smoke Runbook

This runbook covers the first live check for the Phase 10 transport slice defined in [docs/internal/phase10-implementation-checklist.md](../internal/phase10-implementation-checklist.md).

## Scope

- Entry point: `infra/main.phase10.bicep`
- Parameters: `infra/parameters/phase10-dev.json`, `infra/parameters/phase10-staging.json`, `infra/parameters/phase10-prod.json`
- Transport path: `Orders -> Service Bus -> Inventory/Notifications`
- Replay path: `order-events-dlq -> dlq-replay -> order-events`
- The Service Bus namespace, transport auth rule, and connection-string lookup are owned by `infra/modules/servicebus.bicep`; `infra/main.phase10.bicep` consumes that module output during deployment.
- GitHub Actions entrypoint: `phase10-deploy-orchestrator.yml` (which calls `infra-deploy.yml` internally)
- Friendly alias inputs: `publicDomain`, `bindAliases`, `aliasMode`
- Phase 10 does not currently deploy Azure SQL Server or Azure Cache for Redis. Those resources belong to the older bootstrap/App Service path or to later platform work, not to the current transport-first container-app stack.
- Application Insights is part of the Phase 10 deployment and should appear in the target resource group when the deployment succeeds.
- The Phase 10 deploy workflow now auto-registers the Azure resource providers it depends on, including `Microsoft.AlertsManagement`, so a clean subscription can still proceed without manual provider setup.

## Phase 10 Operator Checklist

These are the Phase 10 experience improvements that are worth carrying in the active path:

| Include now | Why it belongs in Phase 10 |
|---|---|
| Gateway health and routed API smoke echo or prove the accepted Azure host | Faster diagnosis when the Azure host is rejected or routed incorrectly |
| Deploy summary shows the real gateway/UI URLs, wrapper run ID, and child workflow links | Operators should not have to hunt across nested jobs to confirm the deployment result |
| Preflight logs the exact skip reason, not just `skipped` | Distinguishes gate logic from failure and shortens triage time |
| Cleanup stays symmetric with creation using the same env suffix and resource scope | Prevents partial teardown and name drift across dev/staging/prod |
| Local-vs-CI mapping is documented in the runbook | Keeps VS Code tasks and GitHub Actions aligned for repeatable validation |
| Build logs stay per service while the summary consolidates the end result | Preserves detailed logs without losing the top-level operator view |
| Retention cleanup exists for GHCR and artifacts | Keeps storage and log accumulation under control without touching Azure runtime resources |

Keep these out of the active Phase 10 path unless a later review proves they are needed:

- ACR migration
- Broad shared-contract extraction without real duplication
- Extra platform layers that do not strengthen the current Azure transport slice

### Workflow Order

Use the numbered Phase 10 workflows in this order:

| Order | Workflow | Use it for |
|---|---|---|
| `01` | `01 Phase 10 Azure Deploy Orchestrator` | Azure deploy, dry run, or cleanup |
| `02` | `02 Phase 10 Azure Runtime Smoke` | Runtime proof for gateway, API routing, and UI after deploy |
| `03` | `03 Phase 10 Azure Transport Smoke` | Transport proof for Service Bus publish, consume, DLQ, and replay |
| `99` | `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | Optional local or CI parity for the current container graph |

Rule of thumb:
- Run `01` when you want to change Azure resources.
- Run `02` right after `01` finishes successfully.
- Run `03` after `02` passes.
- Run `99` only when you want optional local/CI parity for the Docker container shape.

### Workflow Responsibilities

| Workflow | Click target | Owns RG creation | Builds images | Deploys app | Cleanup | Current or legacy |
|---|---|---|---|---|---|---|
| `01 Phase 10 Azure Deploy Orchestrator` | Primary Phase 10 click target | Routes to internal deploy workflow | Routes to internal image workflow | Routes to internal deploy workflow | Routes Azure RG cleanup when `cleanupInfra=true` | Current wrapper |
| `02 Phase 10 Azure Runtime Smoke` | Post-deploy smoke | No | No | No | No | Current validation |
| `03 Phase 10 Azure Transport Smoke` | Post-runtime-smoke transport proof | No | No | No | No | Current validation |
| `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | Optional validation | No | Local/runner build only | Local Docker only | Local Docker cleanup | Current validation |
| `Build Phase 10 Service Images (Internal)` | Do not click for normal deploy | No | Yes | No | No | Current internal |
| `Deploy Azure Phase 10 Resources (Internal)` | Do not click for normal deploy | Yes | No | Yes | Yes | Current internal |
| `Phase 10 Retention Cleanup (Internal)` | Housekeeping only | No | No | No | GHCR/artifact retention only | Current internal |
| `Azure Bootstrap & Deploy` | Do not use for Phase 10 | Legacy App Service stack | No | Legacy App Service only | Legacy App Service RG path | Legacy |
| `Deploy API to Azure App Service` | Do not use for Phase 10 | No | No | Legacy API only | No | Legacy |
| `Deploy React Frontend to Azure App Service` | Do not use for Phase 10 | No | No | Legacy UI only | No | Legacy |

| Area | Legacy bootstrap (`azure-bootstrap.yml`) | Active Phase 10 (`phase10-deploy-orchestrator.yml`) |
|---|---|---|
| Hosting model | Azure App Service | Azure Container Apps |
| Image/build path | API/UI code deployment to App Service | Separate service image build + container-app deploy |
| SQL Server | Created by bootstrap path | Not created by Phase 10 path |
| Redis | Historically part of broader app/platform planning | Not created by Phase 10 path |
| App Insights | Created and configured | Created and configured |
| Key Vault | Created and used for app secrets | Created and used for runtime secrets |
| Service Bus | Not the bootstrap focus | Core Phase 10 transport resource |
| Runtime URL style | `azurewebsites.net` | Container Apps ingress or friendly alias |
| Cleanup | Legacy app-stack teardown | Environment-scoped Phase 10 RG teardown |

If you want Azure to match the local Docker containerized experience, treat the following as the explicit follow-up plan:

| Requirement | Current Phase 10 state | What would be needed to match the containerized target |
|---|---|---|
| SQL Server | Not deployed | Reintroduce the SQL module and wire its outputs into the CI/CD parameter flow |
| Redis | Not deployed | Add an Azure Cache for Redis module and pass its connection settings through the deployment workflow |
| App Service URLs | Not part of the containerized target | Use Container Apps ingress plus friendly aliases / Front Door names; do not expect `azurewebsites.net` from the active path |

### CI/CD implementation plan for containerized parity

If the goal is to make Azure Portal and the CI/CD path look like the local Docker container graph, the implementation needs to be explicit:

| Step | What changes | Owner workflow |
|---|---|---|
| 1 | Keep the App Service surface archived and treat Container Apps as the supported runtime path | `phase10-deploy-orchestrator.yml` |
| 2 | Reintroduce SQL Server as a first-class module and expose its outputs in deployment summaries | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| 3 | Add Redis as a first-class module and wire its connection details into app configuration | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| 4 | Decide on the public URL shape: create friendly aliases for Container Apps via DNS / Front Door | `infra-deploy.yml` alias planning and binding |
| 5 | Update the run summary so portal links, SQL/Redis state, and cleanup status are visible in one place | wrapper summary and child deployment summary |
| 6 | Keep the cleanup path symmetrical so every created resource can be removed from the same CI/CD entrypoint | `cleanupInfra=true` or an explicit legacy teardown path |

Practical rule:
- The active target is the containerized solution, not the old App Service runtime model.
- Use Container Apps ingress or friendly aliases so Azure behaves like the local Docker service graph.
- SQL and Redis can be added to the active path, but they need to be intentionally reintroduced into the Bicep and workflow inputs rather than assumed from the portal.
- The gateway health summary echoes the accepted host, so capture that value first when diagnosing Azure host mismatches. Use the routed Orders API smoke URL to prove the gateway can reach the backend service.

### Enterprise platform priorities

Treat the following as the production baseline for the containerized path:

| Capability | Why it matters | Target posture |
|---|---|---|
| Azure Container Registry | Managed Azure-native runtime image registry | P0 before production |
| Managed Identity + Key Vault | Secretless access and reduced credential sprawl | P0 |
| Azure Monitor + Application Insights + Log Analytics | Operational visibility, tracing, and alerts | P0 |
| Azure Front Door + WAF | Global ingress, TLS, custom domains, and protection | P1 |
| Environment promotion | Separate dev / QA / UAT / prod boundaries | P1 |
| CI/CD hardening | Image signing, SBOM, vulnerability and policy checks | P1 |

Treat SQL and Redis as business-driven services:

| Service | Recommendation |
|---|---|
| Azure SQL | Deploy only if the domain requires relational persistence |
| Azure Cache for Redis | Deploy only if caching, session storage, rate limiting, or pub/sub is required |

The practical implication is:
- local Docker remains the service-graph reference
- Azure remains containerized, not App Service-based
- public ingress should use Container Apps + aliases or Front Door/WAF
- GHCR is transitional until ACR is fully wired into the delivery path

### Implementation matrix

Use this matrix as the concrete follow-through plan for the Azure portal / CI/CD end state:

| Concern | Current state | Enterprise target | Where to change | Verification target |
|---|---|---|---|---|
| Runtime images | GHCR with `GHCR_READ_TOKEN` | ACR with Azure-native auth | `build-phase10-images.yml`, `infra-deploy.yml`, `README-INFRA-DEPLOY.md` | Container Apps revisions pull from ACR successfully |
| Azure identity | OIDC for login only | OIDC + Managed Identity for runtime access | `phase10-deploy-orchestrator.yml`, `infra/main.phase10.bicep`, identity modules | No stored Azure client secrets; runtime auth uses identity |
| Public ingress | Container Apps FQDN only | Container Apps FQDN + friendly alias or Front Door/WAF | `infra-deploy.yml` alias handling, wrapper summary | Stable public URL and summary link for gateway/UI |
| SQL Server | Not in active Phase 10 | Add only if the application requires relational persistence | `infra/main.phase10.bicep`, workflow inputs, runbook | SQL output appears in Azure summary and portal |
| Redis | Not in active Phase 10 | Add only if caching/session/rate-limit needs justify it | `infra/main.phase10.bicep`, workflow inputs, runbook | Redis output appears in Azure summary and portal |
| App Service URLs | Legacy only | Not the active target; replace with containerized ingress/aliases | Archive docs/workflows, keep Phase 10 docs containerized | No operator expects `azurewebsites.net` for Phase 10 |
| Observability | App Insights + LAW present | Add Monitor/trace/alerts as production baseline | `infra/main.phase10.bicep`, monitoring modules | Logs, traces, and alerts visible end to end |
| Cleanup | RG teardown plus retention workflow | Symmetric lifecycle for all created resources | `phase10-deploy-orchestrator.yml`, retention cleanup workflow | Every created artifact/resource has a deletion story |

If you want human-friendly public URLs, choose:

- `bindAliases=false` for summary-only runs
- `bindAliases=true` and `aliasMode=direct` for direct custom-domain binding
- `bindAliases=true` and `aliasMode=frontdoor` for DNS or Front Door planning only

When alias binding is enabled, supply a real `publicDomain` value such as `contoso.com`.

Quick chooser:

- Pick `direct` if you want the custom domain to land directly on the Container App ingress.
- Pick `frontdoor` if you want the run to only prepare the alias plan for a Front Door or DNS layer.
- Leave aliasing off for dry run and first deploys unless you already own the public domain.
- `direct` is the safer default when you are testing the Phase 10 path for the first time.

Shared operator rule:
- Local Docker and Azure Container Apps should be treated as the same Phase 10 service graph with different hosting targets.
- Both hosts now consume the same `orderprocessing-*` service image family, so the only contract difference is the runtime host and ingress surface.
- The service names stay environment-suffixed and split by responsibility, so cleanup and redeploy can safely target the exact gateway, Orders, Inventory, Notifications, and UI resources.
- The public hostname layer is the only thing that changes between the two hosts: localhost ports in Docker, ACA ingress or friendly aliases in Azure.
- Local Phase 10 Docker uses the same naming convention through network aliases. By default aliases resolve as `orderprocessing-*-local`; override `PHASE10_ENV_SUFFIX`, `PHASE10_IMAGE_OWNER`, or `PHASE10_IMAGE_TAG` when validating a staging/prod-shaped local image set.
- If you are comparing this path to `azure-bootstrap.yml`, use that workflow only as a historical App Service reference. It used to create the SQL/App Service surface as part of bootstrap; Phase 10 deliberately replaces that with the container-app transport stack and does not expect SQL or Redis from the active deployment path.
- The `AZUREAPPSERVICE_*` GitHub secrets referenced in this repo are environment-scoped OIDC identifiers carried forward from the earlier setup flow; they are used by the active Phase 10 Container Apps workflows, not to imply an App Service deployment target.
- The Phase 10 wrapper is the single end-to-end delivery entry point for Phase 10. On a real deployment it runs in this order: preflight -> image build -> Azure deploy or cleanup workflow -> summary. Dry run stops after validation and does not build or deploy.
- If the architecture is expanded to include shared foundation resources again, they should be owned by the wrapper-owned infra path, not by the legacy App Service workflows.
- The wrapper summary is the top-level checkpoint; the nested build and Azure deployment jobs hold the detailed child summaries, service-by-service logs, and deployment outputs.
- In practice, use the wrapper summary for the overall result, then open the child build and deploy jobs for per-service logs and Azure deployment details.
- Cleanup is split by storage layer:
  - `cleanupInfra=true` removes the Azure environment-scoped resource group and everything inside it.
  - GHCR images are not removed by the deployment wrapper today.
  - GitHub Actions logs and artifacts follow repository retention settings unless a dedicated cleanup flow is added.
  - Log Analytics and Application Insights retain their own retention policies unless you change them separately.
  - `phase10-retention-cleanup.yml` handles GHCR package version cleanup and stale artifact cleanup without touching Azure deployment resources.

Retention source of truth:
- Artifact retention should be set on the upload step whenever the workflow owns the artifact.
- GHCR package retention is handled by the scheduled cleanup workflow.
- Azure Log Analytics retention is configured on the workspace, not in the deploy wrapper.

### Phase 10 include-now / defer-later checklist

| Area | Phase 10 status | Notes |
|---|---|---|
| Accepted-host echo in gateway health plus routed API smoke | Include now | Helps operators confirm the routed Azure host and backend route immediately |
| Wrapper deploy summary with run links and actual URLs | Include now | Matches the operator flow already used by the build/deploy jobs |
| Skip-reason logging in preflight | Include now | Better than a bare `skipped` label |
| Symmetric cleanup by env-suffixed name | Include now | Required for predictable dev/staging/prod teardown |
| Local-vs-CI task mapping | Include now | Prevents drift between VS Code and GitHub Actions |
| Per-service build logs plus consolidated summary | Include now | Retains detail without losing the executive view |
| GHCR + artifact retention cleanup | Include now | Reduces storage and noise without expanding Azure scope |
| ACR migration | Defer | Separate platform decision, not required for the current Phase 10 slice |
| Broad shared-contract extraction | Defer | Add only when duplication is proven across multiple services |
| New platform layer unrelated to transport/deploy/operator UX | Defer | Avoid scope creep in Phase 10 |

Default retention policy:
- Keep the last `10` GHCR package versions per image.
- Delete GitHub Actions artifacts older than `14` days.
- Use dry-run only for manual cleanup previews; the scheduled cleanup run should perform the actual deletion.

| Area | Source of truth | Default |
|---|---|---|
| GHCR images | `phase10-retention-cleanup.yml` | Keep last `10` versions per image |
| GitHub artifacts | workflow upload step + `phase10-retention-cleanup.yml` | `retention-days: 14` |
| Azure Log Analytics | workspace setting / Bicep / Azure policy | Managed outside the deploy wrapper |

| Area | Current state | Remaining? |
|---|---|---|
| Azure resource-group teardown | Covered by `cleanupInfra=true` in the Phase 10 wrapper | No |
| GHCR package cleanup | Covered by `phase10-retention-cleanup.yml` | No |
| GitHub artifact retention | Covered by `retention-days` plus optional cleanup in the housekeeping workflow | No for the updated workflows |
| Azure Log Analytics retention | Separate workspace/Bicep/Azure Policy decision | Yes, optional follow-up |

Local-vs-CI guidance:
- Use the local hook or VS Code tasks when you need to debug the Docker stack interactively.
- Use the GitHub Actions workflow as the pre-merge gate to confirm the same sequence still passes on a runner and still writes the expected log pointers and artifacts.
- In the GitHub Actions run view, the five Phase 10 image builds are expected to appear as one grouped `Build Phase 10 Images` stage with one individual log block per service (`gateway`, `orders`, `inventory`, `notifications`, `ui`).
- If you export the run log, those five service logs may be consolidated into a single file even though the Actions UI still shows them individually.

## Runtime Verification Checklist

Use this checklist to prove the shared contract is behaving the same way across both hosts:

1. Local Phase 10 stack
   - Start the local Phase 10 container stack.
   - Confirm the gateway, Orders, Inventory, Notifications, and UI containers all start with the `orderprocessing-*` image family.
   - Run the local smoke path and confirm the gateway and UI respond on their local ports.
2. Azure infra deploy
   - Run `phase10-deploy-orchestrator.yml` with the target environment and confirm the deployment summary reports the expected gateway and UI ingress outputs.
   - Verify the published image refs match the service-specific `orderprocessing-*` contract for gateway, Orders, Inventory, Notifications, and UI.
   - Verify the resource group contains Service Bus, Log Analytics, Application Insights, Container Apps, Functions, and Key Vault. Do not expect SQL Server or Redis from this path.
   - Open the Gateway Health URL from the summary and confirm `acceptedHost` matches the Azure Container Apps hostname.
   - Open the Orders API smoke URL from the summary: `/api/v1/Info/runtime-configuration`.
   - Open the UI URL from the summary and confirm the frontend responds.
   - On direct UI Container Apps URLs, the UI server proxies same-origin `/api/*` calls to the gateway through `ORDERPROCESSING_API_BASE_URL`.
   - The gateway accepts the public ACA hostname and the same-environment `orderprocessing-gate-<env>` service name.
   - The gateway must not preserve the original public `Host` header when forwarding to internal Container Apps; ACA expects the destination service host for service-to-service routing.
3. Azure smoke and automation
   - Run `02 Phase 10 Azure Runtime Smoke` after the deployment completes.
   - Confirm gateway health, gateway-routed API bootstrap, UI reachability, and UI API proxy bootstrap pass.
   - Run `03 Phase 10 Azure Transport Smoke` after runtime smoke passes.
   - Confirm publish, consume, DLQ, and replay checks pass before promoting aliases or treating the environment as ready.

## GitHub UI Path

To launch the deployment from GitHub:

1. Open the repository in GitHub.
2. Select the `Actions` tab.
3. Click `01 Phase 10 Azure Deploy Orchestrator`.
4. Click `Run workflow`.
5. Choose the target branch.
6. Set `environment`, `location`, and, if needed, `bindAliases`, `aliasMode`, `publicDomain`, and `cleanupInfra`.
7. Click `Run workflow` to start the deployment.

After the deploy finishes:

1. Open **Actions**.
2. Click **02 Phase 10 Azure Runtime Smoke**.
3. Select the same target environment.
4. Click **Run workflow**.
5. Open **Actions** again.
6. Click **03 Phase 10 Azure Transport Smoke**.
7. Select the same target environment.
8. Click **Run workflow**.

## VS Code Local Validation Path

Use these tasks when you want a local replica of the Phase 10 service graph before touching Azure:

1. `1 Run: Phase 10 Local Container Stack 00 Start Stack Only`
2. `1 Run: Phase 10 Local Container Stack 01 Wait Ready + Keycloak`
3. `1 Run: Phase 10 Local Container Stack 02 Playwright Smoke`
4. `1 Run: Phase 10 Local Container Stack 03 Integration Suite`
5. `1 Run: Phase 10 Local Container Stack 04 Payment Matrix`
6. `1 Run: Phase 10 Local Container Stack 05 Full Validation`
7. `1 Run: Phase 10 Local Container Stack 06 Cleanup After Validation`

Log locations for the local container stack:

- `TestResults\Playwright\phase10-docker-http\<timestamp>_profile\...`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_profile\01-env-ready.log`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_smoke\...`
- `TestResults\Integration\<timestamp>\...`
- `TestResults\Playwright\phase10-docker-http\<timestamp>_endtoend\summary.json`
- `TestResults\Playwright\phase10-docker-http\latest-playwright-profile.txt`
- `TestResults\Playwright\phase10-docker-http\latest-playwright-smoke.txt`
- `TestResults\Playwright\latest-playwright-run.txt`

### Single-Command End-to-End Hook

If you want the same validation flow without launching the individual tasks one by one, use the named run-hook:

```powershell
npm --prefix automation run xydatalabs-test-docker-local-e2e-dev
```

Equivalent VS Code task:

```text
1 Run: xydatalabs-test-docker-local-e2e-dev (Docker Dev HTTP E2E)
```

Direct script form:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -StabilizationDelaySeconds 60
```

Use the hook when:

- you want the stack started automatically if it is not already running
- you want a single pass that includes ready, smoke, integration, matrix, and full validation
- you want the same log trail for repeatable validation and handoff
- you want the local order to match the Phase 10 wrapper expectation before you move to Azure

Quick start:

```powershell
npm --prefix automation run xydatalabs-test-docker-local-e2e-dev
```

Use the individual tasks when:

- you are debugging a single step
- you want to pause between phases
- you want to keep the stack alive after one stage for manual inspection

### Common Troubleshooting

- If the hook fails before the stack starts, verify Docker Desktop is running and the engine is healthy.
- If the browser or smoke step times out, verify that the local ports for the gateway and UI are not already in use.
- If the gateway revision keeps activating or restarting, open the Container Apps logs and inspect the startup-probe failure details.
- If you need persistent logs for investigation, run the individual stack tasks instead of the single-command hook so cleanup does not happen until you ask for it.
- If Azure deployment fails with `MissingSubscriptionRegistration` for `Microsoft.AlertsManagement`, rerun the workflow after provider registration or confirm the workflow step `Ensure Azure resource providers are registered` completed successfully.

## Quick Command Checklist

Use this if you want the shortest possible runbook for the first Azure dev proof.

```powershell
$env:AZURE_CONFIG_DIR = "$PWD\.azure-cli"
$deploymentName = "phase10-dev-$(Get-Date -Format yyyyMMddHHmmss)"

az deployment sub what-if `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json

az deployment sub create `
  --name $deploymentName `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json

$outputs = az deployment sub show --name $deploymentName --query "properties.outputs" -o json | ConvertFrom-Json
$resourceGroupName = $outputs.resourceGroupName.value
$serviceBusNamespaceName = $outputs.serviceBusNamespaceName.value
$logAnalyticsWorkspaceName = $outputs.logAnalyticsWorkspaceName.value
$managedEnvironmentId = $outputs.managedEnvironmentId.value
$gatewayContainerAppName = $outputs.gatewayContainerAppName.value
$uiContainerAppName = $outputs.uiContainerAppName.value
$ordersContainerAppName = $outputs.ordersContainerAppName.value
$inventoryContainerAppName = $outputs.inventoryContainerAppName.value
$notificationsContainerAppName = $outputs.notificationsContainerAppName.value
$functionAppName = $outputs.functionAppName.value
$keyVaultName = $outputs.keyVaultName.value
$appInsightsName = $outputs.appInsightsName.value
$gatewayFqdn = $outputs.gatewayContainerAppFqdn.value
$uiFqdn = $outputs.uiContainerAppFqdn.value

az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name inventory-order-created
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name notifications-order-created
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events-dlq
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay

az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az containerapp show --resource-group $resourceGroupName --name $ordersContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $inventoryContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $notificationsContainerAppName --query "properties.template.containers[0].env"
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
Write-Host "Gateway ingress: https://$gatewayFqdn"
Write-Host "UI ingress: https://$uiFqdn"
```

Expected:
- the deployment completes successfully
- the outputs resolve without manual guessing
- the Service Bus namespace, topic, subscriptions, and DLQ path exist
- the runtime settings include the Service Bus connection string and replay values
- the ACA environment and App Insights are wired to the same transport slice
- the gateway and UI ingress URLs resolve from the deployment outputs

## Operator Notes

1. Confirm `az` is authenticated in the target subscription.
2. Confirm the workspace-local Azure config dir is usable if the default profile is locked down.
3. Confirm the repo is clean enough to deploy the current Phase 10 stack.
4. Confirm the target environment is `dev`, `staging`, or `prod`.
5. If `az bicep version` fails, run `az bicep install` once so the local compiler is available for preview and deployment validation.
6. If you are running from GitHub Actions, open `Actions > Phase 10 Deploy Orchestrator > Run workflow`, then set `environment`, `location`, and optionally `publicDomain`, `bindAliases`, `aliasMode`, and `cleanupInfra`.

## Minimal Flow

### 1. Preview the deployment

```powershell
az deployment sub what-if --location centralindia --template-file infra/main.phase10.bicep --parameters @infra/parameters/phase10-dev.json
```

Expected:
- The plan shows the Phase 10 transport stack.
- The plan includes Service Bus, Log Analytics, ACA, Functions, Key Vault, and App Insights resources.

### 2. Deploy the environment

```powershell
az deployment sub create --location centralindia --template-file infra/main.phase10.bicep --parameters @infra/parameters/phase10-dev.json --name phase10-dev-<timestamp>
```

Expected:
- The deployment completes successfully.
- The deployment outputs include the Service Bus namespace, Log Analytics workspace, ACA environment, Function App, Key Vault, and App Insights names.
- The deployment outputs include the gateway and UI ingress FQDNs.

### 3. Capture deployment outputs

```powershell
$deploymentName = "phase10-dev-<timestamp>"
$outputs = az deployment sub show --name $deploymentName --query "properties.outputs" -o json | ConvertFrom-Json
$resourceGroupName = $outputs.resourceGroupName.value
$serviceBusNamespaceName = $outputs.serviceBusNamespaceName.value
$logAnalyticsWorkspaceName = $outputs.logAnalyticsWorkspaceName.value
$managedEnvironmentId = $outputs.managedEnvironmentId.value
$gatewayContainerAppName = $outputs.gatewayContainerAppName.value
$uiContainerAppName = $outputs.uiContainerAppName.value
$ordersContainerAppName = $outputs.ordersContainerAppName.value
$inventoryContainerAppName = $outputs.inventoryContainerAppName.value
$notificationsContainerAppName = $outputs.notificationsContainerAppName.value
$functionAppName = $outputs.functionAppName.value
$keyVaultName = $outputs.keyVaultName.value
$appInsightsName = $outputs.appInsightsName.value
$gatewayFqdn = $outputs.gatewayContainerAppFqdn.value
$uiFqdn = $outputs.uiContainerAppFqdn.value
```

Expected:
- You have the exact Azure names needed for post-deploy verification.
- The values come from the Phase 10 template outputs, not manual guesswork.
- You also have the friendly ingress targets for the gateway and UI.

### 4. Review the workflow summary

If the deployment was launched from GitHub Actions, open the run summary and confirm:

- the environment matches the target
- the resource group and transport outputs are present
- the gateway and UI ingress URLs are shown
- the friendly aliases are shown if `bindAliases` was enabled

If `bindAliases=true`, also confirm the workflow rejected placeholder domains and required a real `publicDomain`.

## Recommended Inputs

Use these defaults for the first pass in each environment:

| Environment | Location | bindAliases | aliasMode | publicDomain |
|-------------|----------|-------------|-----------|--------------|
| dev | `centralindia` | `false` | `direct` | empty |
| staging | `centralindia` | `false` | `direct` | empty |
| prod | `centralindia` | `false` | `direct` | empty |

Enable aliasing only when you are ready to manage a real public domain:

| Environment | bindAliases | aliasMode | publicDomain |
|-------------|-------------|-----------|--------------|
| dev | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |
| staging | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |
| prod | `true` | `direct` or `frontdoor` | `contoso.com` or your real suffix |

## Verify Everything

Use this compact block if you only want the minimum confirmation set after deploy:

```powershell
az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
```

Expected:
- the Service Bus namespace exists and is reachable
- the runtime settings contain the transport connection string and replay values
- the ACA environment and App Insights share the same transport slice
- the environment is ready for the publish / consume / replay smoke
- the gateway and UI ingress URLs are recorded from the same deployment output set

## Fallback Checks

### 4. Verify Service Bus topology

```powershell
az servicebus namespace show --resource-group $resourceGroupName --name $serviceBusNamespaceName
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name inventory-order-created
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events --name notifications-order-created
az servicebus topic show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name order-events-dlq
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay
```

Confirm the deployed namespace contains:
- `order-events`
- `inventory-order-created`
- `notifications-order-created`
- `order-events-dlq`
- `dlq-replay`

Confirm the namespace also contains the Phase 10 transport auth rule.

### 5. Verify runtime configuration

```powershell
az functionapp config appsettings list --resource-group $resourceGroupName --name $functionAppName
az containerapp show --resource-group $resourceGroupName --name $gatewayContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $uiContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $ordersContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $inventoryContainerAppName --query "properties.template.containers[0].env"
az containerapp show --resource-group $resourceGroupName --name $notificationsContainerAppName --query "properties.template.containers[0].env"
```

Confirm the deployed runtime settings include:
- `ServiceBus__Enabled=true`
- `ServiceBus__ConnectionString`
- `ServiceBus__TopicName=order-events`
- `ServiceBus__DeadLetterTopicName=order-events-dlq`
- `ServiceBus__DeadLetterSubscriptionName=dlq-replay`
- `ServiceBus__ReplayEnabled=true`
- `KeyVault__Uri`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`
- `ServiceBus__SubscriptionName` on Inventory and Notifications
- `ServiceBus__SubscriptionName` is not required on Orders because it is the publisher slice

Confirm the runtime can read the Service Bus connection string from configuration instead of falling back to in-memory, and that the connection string was derived from the transport auth rule rather than hand-entered into app settings.

### 6. Verify observability wiring

```powershell
az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName
az resource show --ids $managedEnvironmentId
az resource show --resource-group $resourceGroupName --resource-type Microsoft.Insights/components --name $appInsightsName
```

Confirm:
- the Log Analytics workspace exists and is linked to the ACA environment
- App Insights exists and is emitting to the same transport slice
- ACA container app logs are enabled through the workspace-backed environment
- the Orders, Inventory, and Notifications apps have the transport-first Service Bus settings in their environment payloads
- the Gateway and UI container apps exist in the same ACA environment

### 7. Runtime Smoke

Use the GitHub workflow first:

1. Open **Actions**.
2. Click **02 Phase 10 Azure Runtime Smoke**.
3. Click **Run workflow**.
4. Select the same target environment used by the deploy run, for example `dev`.
5. Click **Run workflow**.

The workflow runs `scripts/run-phase10-azure-runtime-smoke.ps1`.

The smoke verifies:

1. The Gateway Container App exists for the selected environment.
2. The UI Container App exists for the selected environment.
3. The Gateway public ACA URL returns a healthy response and echoes the accepted Azure host.
4. The Gateway-routed Orders API bootstrap endpoint returns runtime configuration JSON.
5. The UI static route serves the React shell.
6. The UI server-side API proxy returns runtime configuration JSON through same-origin `/api/*`.

Expected workflow summary:

| Check | Expected |
|---|---|
| Gateway health | PASS |
| Gateway routed API runtime configuration | PASS |
| UI static route | PASS |
| UI API proxy runtime configuration | PASS |

Local equivalent:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-azure-runtime-smoke.ps1 -Environment dev
```

The local command requires Azure CLI login and access to the selected Phase 10 resource group.

### 8. Transport Smoke

Use the GitHub workflow first:

1. Open **Actions**.
2. Click **03 Phase 10 Azure Transport Smoke**.
3. Click **Run workflow**.
4. Select the same target environment used by the deploy run, for example `dev`.
5. Click **Run workflow**.

The workflow runs `scripts/run-phase10-azure-transport-smoke.ps1`, which calls the `tools/Phase10.TransportSmoke` .NET utility.

The smoke verifies:

1. The Service Bus namespace, main topic, fan-out subscriptions, DLQ topic, and replay subscription exist.
2. A controlled `OrderCreatedV1` smoke message can be published to `order-events-<env>`.
3. `inventory-order-created-<env>` receives and completes its copy.
4. `notifications-order-created-<env>` receives and completes its copy.
5. A controlled message can be dead-lettered from the inventory subscription and forwarded to `order-events-dlq`.
6. `dlq-replay-<env>` receives the dead-lettered message.
7. A replay message can be republished to `order-events-<env>`.
8. Inventory and Notifications both receive and complete the replay message.

Expected workflow summary:

| Check | Expected |
|---|---|
| Publish fanout | PASS |
| Inventory fan-out consume | PASS |
| Notifications fan-out consume | PASS |
| Inventory controlled dead-letter | PASS |
| DLQ replay subscription receive | PASS |
| Publish replay | PASS |
| Inventory replay consume | PASS |
| Notifications replay consume | PASS |

Local equivalent:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-azure-transport-smoke.ps1 -Environment dev
```

The local command requires Azure CLI login and access to the `phase10-transport` Service Bus auth rule.

### 9. Replay Smoke

The automated transport smoke includes the first replay proof:

1. It dead-letters a controlled message from the inventory subscription.
2. It verifies forwarding to `order-events-dlq`.
3. It receives the message from `dlq-replay-<env>`.
4. It republishes a replay message to `order-events-<env>`.
5. It verifies both downstream subscriptions receive the replayed flow.

This proves the operator replay route exists. A later failure-drill can still validate poison-message quarantine and alert behavior.

## Success Criteria

- The transport stack deploys cleanly.
- The runtime uses Service Bus instead of the in-memory publisher.
- The first order-created flow is observable end to end.
- Replay and quarantine behavior are both visible in Azure.
- The Phase 10 transport slice remains separate from the hosting cutover.
- The deployment summary exposes the correct env-suffixed ingress URLs and friendly aliases when enabled.

## If Smoke Fails

- Keep `infra/main.bicep` reserved for the later hosting path.
- Fix the transport wiring or Service Bus config before moving on to broader hosting work.
- Do not introduce `SharedContracts` as a workaround for a transport failure.
