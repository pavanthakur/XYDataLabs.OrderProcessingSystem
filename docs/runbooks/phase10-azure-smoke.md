# Phase 10 Azure Smoke Runbook

This runbook covers the first live check for the Phase 10 pre-Azure baseline defined in [docs/internal/phase10-preazure-lld.md](../internal/phase10-preazure-lld.md), with the execution slices expanded in [docs/internal/phase10-implementation-checklist.md](../internal/phase10-implementation-checklist.md).

## Scope

- Platform foundation entry point: `infra/main.phase10.platform.bicep`
- App/runtime entry point: `infra/main.phase10.bicep`
- Parameters: `infra/parameters/phase10-dev.json`, `infra/parameters/phase10-staging.json`, `infra/parameters/phase10-prod.json`
- Transport path: `Orders -> Service Bus -> Inventory/Notifications`
- Current validated replay smoke path: `order-events-dlq -> dlq-replay-<environment> -> order-events-<environment>`
- The Service Bus namespace, transport auth rule, and connection-string lookup are owned by `infra/modules/servicebus.bicep`; `infra/main.phase10.bicep` consumes that module output during deployment.
- GitHub Actions entrypoint: `phase10-deploy-orchestrator.yml` (which calls `infra-deploy.yml` internally)
- The persistent ACR registry and the runtime pull identity are owned by `00 Azure Platform Foundation` and live in `rg-orderprocessing-platform`.
- Friendly alias inputs: `publicDomain`, `bindAliases`, `aliasMode`
- The active `01 Phase 10 Azure Deploy Orchestrator` path does deploy Azure SQL Server and Azure Managed Redis into the environment-scoped app resource group when the baseline runs; they are not part of `rg-orderprocessing-platform`.
- For the next implementation slice, use [docs/internal/phase10-parity-matrix.md](../internal/phase10-parity-matrix.md) as the SQL / Redis / ACR ownership source of truth before changing Azure again.
- Application Insights is part of the Phase 10 deployment and should appear in the target resource group when the deployment succeeds.
- `00 Azure Platform Foundation` registers the Azure resource providers used by the Phase 10 platform and app stacks. `01 Phase 10 Azure Deploy Orchestrator` verifies those providers are already registered and fails early with a clear "run 00 first" message if a clean subscription is missing them.

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
| Retention cleanup exists for ACR, historical GHCR packages, and artifacts | Keeps storage and log accumulation under control without touching Azure runtime resources |

Keep these out of the active Phase 10 transport baseline unless a later review proves they are needed:

- Broad shared-contract extraction without real duplication
- Extra platform layers that do not strengthen the current Azure Phase 10 baseline

### Enterprise Standard Placement

The operator-facing rule is simple:

- **Phase 10 now** owns the execution shape, operator UX, cleanup hygiene, platform foundation, SQL/Redis parity, and live Azure proof, all on top of the governed pre-Azure baseline.
- **Phase 11+** should carry the next hardening layer, especially Managed Identity for SQL and broader OpenTelemetry-based tracing.
- **Deferred** items stay out of the active Phase 10 deployment slice until the repo proves the need with real duplication or an explicit hardening gate.

For the detailed placement map, use the pre-Azure baseline and the internal checklist:

- [docs/internal/phase10-preazure-lld.md](../internal/phase10-preazure-lld.md)
- [docs/internal/phase10-implementation-checklist.md](../internal/phase10-implementation-checklist.md)

### ACR Foundation And Cleanup Plan

Phase 10 uses ACR plus managed identity for runtime image pulls. The active architecture creates the persistent platform ACR and pull identity once in `00 Azure Platform Foundation`, then lets the normal app deploy reuse those values without creating registry RBAC inside the environment RG.

The enterprise target is to keep ACR and the pull identity in a persistent platform foundation so the normal app deploy no longer manages IAM.

| Area | Target owner | Cleanup behavior |
|---|---|---|
| App environment RG | `01 Phase 10 Azure Deploy Orchestrator` | Deleted only when `cleanupInfra=true` |
| ACR registry | `00 Azure Platform Foundation` | Persistent; not deleted by app environment cleanup |
| Pull identity | `00 Azure Platform Foundation` | Created once; not recreated per app RG |
| Optional AcrPull RBAC fallback | `00 Azure Platform Foundation` | Privileged-only path; not required by the normal Phase 10 deploy |
| ACR images and tags | `Phase 10 Retention Cleanup (Internal)` | Scheduled pruning; preserves active revision images |
| GitHub artifacts | Workflow upload steps plus retention cleanup | Retained by `retention-days` and scheduled artifact cleanup |

Target implementation sequence:

1. Run `00 Azure Platform Foundation` once for the shared platform ACR and pull identity.
2. Confirm the platform deployment summary shows the persistent ACR login server and pull identity id.
3. Run `01 Phase 10 Azure Deploy Orchestrator` with the selected environment.
4. Let the wrapper resolve the platform foundation and feed those values into the build and deploy jobs.
5. Keep `phase10-retention-cleanup.yml` as the scheduled ACR image hygiene workflow.

That gives the intended operating model:

- no manual RG-level permission step after app cleanup
- no subscription-scope `User Access Administrator` requirement for the normal app deploy identity
- app environment RGs can be deleted and recreated cleanly
- ACR image history survives app RG cleanup
- scheduled image cleanup remains meaningful

For the current active path:

| Scope | Required capability |
|---|---|
| Platform foundation workflow | One-time setup for the persistent ACR and pull identity; `AcrPull` is an optional privileged fallback |
| Normal Phase 10 deploy workflow | Environment-scoped deployment rights only; creates scoped ACR pull-token credentials and needs no `roleAssignments/write` |

`Assign AcrPull` usage in `00 Azure Platform Foundation`:

| Input | Use it when |
|---|---|
| `Assign AcrPull = false` | You want the normal Phase 10 enterprise path. This is the default and the recommended choice. |
| `Assign AcrPull = true` | You are running the platform workflow with a privileged Azure identity that already has `roleAssignments/write` and you explicitly want the workflow to create the ACR RBAC grant. |

Leave it `false` for normal dev/staging/prod Phase 10 runs.

ACR retention rules stay separate from app deployment:

| Rule | Policy |
|---|---|
| Preserve active images | Query active Container App revisions and do not delete referenced tags |
| Keep recent history | Keep the latest `10` tags per service image |
| Age-based cleanup | Delete stale tags older than `30` days by default |
| Protected tags | Keep release tags such as `phase10`, `latest`, or future signed release labels when marked protected |
| Environment-aware tags | Prefer `dev-<sha>`, `staging-<sha>`, and `prod-<sha>` if the tagging model becomes environment-specific |

### Promotion Order After Local Pre-Azure Completion

After local pre-Azure validation reaches L6 on the target commit SHA, use this promotion order:

| Sequence | Workflow | Required usage |
|---|---|---|
| 1 | `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | Required clean-room CI parity gate before Azure when the change affects Compose, gateway, service images, workflow, Bicep, transport, or payment automation. |
| 2 | `00 Azure Platform Foundation` | Run only when provider registration, persistent ACR, or pull identity must be created or refreshed. Skip it for routine deploys when the platform foundation already exists. |
| 3 | `01 Phase 10 Azure Deploy Orchestrator` | Required Azure deploy entrypoint for dry run, deploy, or intentional cleanup. |
| 4 | `02 Phase 10 Azure Runtime Smoke` | Required immediately after a successful deploy. |
| 5 | `03 Phase 10 Azure Transport Smoke` | Required after runtime smoke passes. |
| 6 | `04 Phase 10 Azure Payment Matrix` | Final Azure business/browser/payment gate after runtime and transport pass. |

Promotion rules:

- Do not start Azure deployment work until local L6 and workflow `99` are both green for the same commit SHA.
- Treat `00` as a conditional platform-maintenance step, not part of every routine deployment.
- Use `01` in `dryRun=true` mode first for infrastructure-affecting changes.
- Use `01` with `cleanupInfra=true` only when intentionally removing or resetting an environment.

### Workflow Catalog

These are the numbered Phase 10 workflows and their responsibilities:

| Order | Workflow | Use it for |
|---|---|---|
| `00` | `00 Azure Platform Foundation` | Persistent platform ACR and pull identity bootstrap |
| `01` | `01 Phase 10 Azure Deploy Orchestrator` | Azure deploy, dry run, or cleanup |
| `02` | `02 Phase 10 Azure Runtime Smoke` | Runtime proof for gateway, API routing, and UI after deploy |
| `03` | `03 Phase 10 Azure Transport Smoke` | Transport proof for Service Bus publish, consume, DLQ, and replay |
| `04` | `04 Phase 10 Azure Payment Matrix` | All-tenant browser/payment E2E proof against the live Azure Container Apps URLs |

### Latest Dev Evidence Snapshot

As of August 8, 2026, the active `dev` Azure validation lane is green with the following workflow evidence:

| Workflow | Run | Result |
|---|---:|---|
| `00 Azure Platform Foundation` | `31264306311` | Passed |
| `01 Phase 10 Azure Deploy Orchestrator` (real deploy) | `31264680030` | Passed |
| `02 Phase 10 Azure Runtime Smoke` | `31266011709` | Passed |
| `03 Phase 10 Azure Transport Smoke` | `31266391019` | Passed |
| `04 Phase 10 Azure Payment Matrix` | `31266516115` | Passed |

Operator note:

- The original `03` failure on August 8, 2026 was caused by stale smoke validation naming (`dlq-intake-<environment>`). The validated topology and smoke path now use `dlq-replay-<environment>`.
| `99` | `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | CI pre-deployment clean-room parity for the current container graph when the change affects Compose, gateway, images, workflows, Bicep, transport, or payment automation |

Rule of thumb:
- Run `99` first as the clean-room pre-deployment parity gate before Azure when a change affects Compose, gateway, service images, workflow, Bicep, transport, or payment-matrix behavior.
- Run `00` once before the first app deploy, and again only if you intentionally recreate the platform foundation or need to refresh subscription-level provider registration.
- Run `01` when you want to deploy Azure resources. Use the same workflow in cleanup mode only when intentionally removing or resetting an environment.
- Run `02` right after `01` finishes successfully.
- Run `03` after `02` passes.
- Run `04` after `03` passes when you want the Azure equivalent of the local all-tenant Docker payment matrix.
- Workflow `99` always starts its own Docker stack on GitHub-hosted runners. Reusing an already running stack is a local script-only option via `scripts/run-phase10-docker-dev-e2e-hook.ps1 -SkipStartIfNeeded`.

Runtime smoke backend-route guardrail:

- `02 Phase 10 Azure Runtime Smoke` now verifies that the gateway health payload reports ACA `https://...azurecontainerapps.io` backend targets for `orders`, `payments`, `inventory`, `notifications`, and `ui`.
- Treat any `localhost` backend, bare short-name backend such as `http://orderprocessing-ord-stg`, or non-HTTPS ACA backend target as a deployment regression and stop before transport or payment validation.

### Environment Operating Matrix

Use the same Phase 10 sequence in each environment, changing only the target environment value.

| Environment | Platform foundation | Azure deploy or cleanup | Runtime smoke | Transport smoke | Cleanup note |
|---|---|---|---|---|---|
| `dev` | Run `00` once, then only when platform ACR or pull identity must be recreated | Run `01` with `cleanupInfra=false` for deploys and `cleanupInfra=true` for teardown | Run `02` after a successful deploy | Run `03` after `02` passes; run `04` for all-tenant payment E2E | Deletes `rg-orderprocessing-dev` only; platform foundation stays persistent |
| `staging` | Run `00` once, then only when platform ACR or pull identity must be recreated | Run `01` with `cleanupInfra=false` for deploys and `cleanupInfra=true` for teardown | Run `02` after a successful deploy | Run `03` after `02` passes; run `04` for all-tenant payment E2E | Deletes `rg-orderprocessing-stg` only; platform foundation stays persistent |
| `prod` | Run `00` once, then only when platform ACR or pull identity must be recreated | Run `01` with `cleanupInfra=false` for deploys and `cleanupInfra=true` only during approved teardown | Run `02` after a successful deploy | Run `03` after `02` passes; run `04` only during approved production validation | Deletes `rg-orderprocessing-prod` only; platform foundation stays persistent |

Default selection guidance:

- Keep `Assign AcrPull=false` for normal dev/staging/prod runs.
- Use `Assign AcrPull=true` only for a privileged platform-admin run that already has `roleAssignments/write`.
- In `00`, use `Dry Run=false` when you want provider registration and platform resources actually created or refreshed. `Dry Run=true` is non-mutating and skips provider registration.
- Use `99` only for optional local or CI parity checks, not for the main Azure environment lifecycle.

### Environment-Specific GitHub Actions Checklists

Use the same gate order in all environments:

1. `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)`
2. `00 Azure Platform Foundation` only when needed
3. `01 Phase 10 Azure Deploy Orchestrator` in dry-run mode first
4. `01 Phase 10 Azure Deploy Orchestrator` real deploy
5. `02 Phase 10 Azure Runtime Smoke`
6. `03 Phase 10 Azure Transport Smoke`
7. `04 Phase 10 Azure Payment Matrix`

Resource-name note:

- Workflow input values are `dev`, `staging`, and `prod`.
- Azure resource names use `dev`, `stg`, and `prod` suffixes in some places.
- In particular, the wrapper resolves `staging -> stg` for names such as the resource group and Container Apps.
- The parameter files still use environment-specific values such as `order-events-staging` and `inventory-order-created-staging`.

#### Dev Checklist

Run this after local pre-Azure L6 is green on the target commit SHA.

1. Run `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)`.
   - Input:
     - `stabilizationDelaySeconds = 120`
   - Wait for:
     - smoke
     - integration
     - payment matrix
     - full validation
   - Stop if it fails.
2. Decide whether `00 Azure Platform Foundation` is needed.
   - Run it only if:
     - this is the first Phase 10 Azure run in the subscription
     - provider registration may be missing
     - persistent ACR was deleted or changed
     - pull identity was deleted or changed
   - Inputs when needed:
     - `environment = dev`
     - `location = centralindia`
     - `dryRun = false`
     - `assignAcrPullRole = false`
3. Run `01 Phase 10 Azure Deploy Orchestrator` dry run.
   - Inputs:
     - `environment = dev`
     - `location = centralindia`
     - `publicDomain =`
     - `bindAliases = false`
     - `aliasMode = direct`
     - `dryRun = true`
     - `cleanupInfra = false`
   - Stop if the what-if summary shows unexpected deletes or wrong scope.
4. Run `01 Phase 10 Azure Deploy Orchestrator` real deploy.
   - Same inputs, except:
     - `dryRun = false`
   - Capture:
     - resource group
     - gateway URL
     - UI URL
     - Service Bus
     - SQL
     - Redis
     - Function App
     - Key Vault
     - App Insights
5. Run `02 Phase 10 Azure Runtime Smoke`.
   - Input:
     - `environment = dev`
   - Expected:
     - gateway health pass
     - routed API pass
     - UI route pass
     - UI API proxy pass
6. Run `03 Phase 10 Azure Transport Smoke`.
   - Input:
     - `environment = dev`
   - Expected:
     - publish pass
     - inventory consume pass
     - notifications consume pass
     - DLQ forward pass
     - replay pass
7. Run `04 Phase 10 Azure Payment Matrix`.
   - Inputs:
     - `environment = dev`
     - `tenantTimeoutMs = 180000`
     - `skipVerification = false`
   - Expected:
     - all discovered tenants covered
     - provider flows covered per current config
     - SQL and verification checks included

#### Staging Checklist

Use this after `dev` is green and you want the same release candidate validated in staging.

1. Run `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` on the same target commit SHA.
   - Input:
     - `stabilizationDelaySeconds = 120`
   - Stop if it fails.
2. Decide whether `00 Azure Platform Foundation` is needed.
   - In normal staging promotion it is usually skipped because the platform foundation is already shared and persistent.
   - Inputs when needed:
     - `environment = staging`
     - `location = centralindia`
     - `dryRun = false`
     - `assignAcrPullRole = false`
3. Run `01 Phase 10 Azure Deploy Orchestrator` dry run.
   - Inputs:
     - `environment = staging`
     - `location = centralindia`
     - `publicDomain =`
     - `bindAliases = false`
     - `aliasMode = direct`
     - `dryRun = true`
     - `cleanupInfra = false`
4. Run `01 Phase 10 Azure Deploy Orchestrator` real deploy.
   - Same inputs, except:
     - `dryRun = false`
   - Capture the same summary fields as `dev`.
   - Expect resource names that use the `stg` suffix, for example:
     - `rg-orderprocessing-stg`
     - `orderprocessing-gate-stg`
     - `orderprocessing-ui-stg`
5. Run `02 Phase 10 Azure Runtime Smoke`.
   - Input:
     - `environment = staging`
6. Run `03 Phase 10 Azure Transport Smoke`.
   - Input:
     - `environment = staging`
7. Run `04 Phase 10 Azure Payment Matrix`.
   - Inputs:
     - `environment = staging`
     - `tenantTimeoutMs = 180000`
     - `skipVerification = false`

#### Prod Checklist

Use this only after `staging` is green and the production change is approved.

1. Run `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` on the same target commit SHA.
   - Input:
     - `stabilizationDelaySeconds = 120`
   - Stop if it fails.
2. Decide whether `00 Azure Platform Foundation` is needed.
   - This should normally be skipped for production promotion unless the shared platform foundation actually needs refresh.
   - Inputs when needed:
     - `environment = prod`
     - `location = centralindia`
     - `dryRun = false`
     - `assignAcrPullRole = false`
3. Run `01 Phase 10 Azure Deploy Orchestrator` dry run.
   - Inputs:
     - `environment = prod`
     - `location = centralindia`
     - `publicDomain =`
     - `bindAliases = false`
     - `aliasMode = direct`
     - `dryRun = true`
     - `cleanupInfra = false`
4. Run `01 Phase 10 Azure Deploy Orchestrator` real deploy.
   - Same inputs, except:
     - `dryRun = false`
   - Capture the same summary fields as `dev`.
5. Run `02 Phase 10 Azure Runtime Smoke`.
   - Input:
     - `environment = prod`
6. Run `03 Phase 10 Azure Transport Smoke`.
   - Input:
     - `environment = prod`
7. Run `04 Phase 10 Azure Payment Matrix`.
   - Inputs:
     - `environment = prod`
     - `tenantTimeoutMs = 180000`
     - `skipVerification = false`
   - Run this only during approved production validation.

Stop rules for all environments:

- If `99` fails, do not run Azure.
- If `01` dry run looks wrong, do not run real deploy.
- If `02` fails, do not run `03`.
- If `03` fails, do not run `04`.

Capture for every environment:

- workflow run IDs
- deploy summary
- runtime smoke summary
- transport smoke summary
- payment matrix artifact bundle
- final gateway and UI URLs

### Latest Verified Dev Proof

Use this as the current known-good Phase 10 baseline when comparing future workflow runs.

| Date | Workflow | Run | Result | Verified |
|---|---|---|---|---|
| 2026-07-13 | `01 Phase 10 Azure Deploy Orchestrator` | `29273224237` | PASS | Preflight, image build, and Azure dev Container Apps deployment. |
| 2026-07-13 | `02 Phase 10 Azure Runtime Smoke` | `29273711615` | PASS | Gateway health, gateway-routed API runtime configuration, UI route, and UI API proxy. |
| 2026-07-13 | `03 Phase 10 Azure Transport Smoke` | `29273881488` | PASS | Service Bus publish, fan-out consume, controlled DLQ forwarding, DLQ replay receive, and replay publish/consume. |
| 2026-07-13 | `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | `29268434294` | PASS | Optional Docker Dev HTTP E2E smoke, integration, matrix, and cleanup parity. |

Current dev URLs from the latest deploy proof:

| Target | URL |
|---|---|
| Gateway | `https://orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io` |
| UI | `https://orderprocessing-ui-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io` |

### Workflow Responsibilities

| Workflow | Click target | Owns RG creation | Builds images | Deploys app | Cleanup | Current or legacy |
|---|---|---|---|---|---|---|
| `01 Phase 10 Azure Deploy Orchestrator` | Primary Phase 10 click target | Routes to internal deploy workflow | Routes to internal image workflow | Routes to internal deploy workflow | Routes Azure RG cleanup when `cleanupInfra=true` | Current wrapper |
| `02 Phase 10 Azure Runtime Smoke` | Post-deploy smoke | No | No | No | No | Current validation |
| `03 Phase 10 Azure Transport Smoke` | Post-runtime-smoke transport proof | No | No | No | No | Current validation |
| `04 Phase 10 Azure Payment Matrix` | Post-transport payment E2E | No | No | No | No | Current validation |
| `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` | Optional validation | No | Local/runner build only | Local Docker only | Local Docker cleanup | Current validation |
| `Build Phase 10 Service Images (Internal)` | Do not click for normal deploy | No | Yes | No | No | Current internal |
| `Deploy Azure Phase 10 Resources (Internal)` | Do not click for normal deploy | Yes | No | Yes | Yes | Current internal |
| `Phase 10 Retention Cleanup (Internal)` | Housekeeping only | No | No | No | ACR plus historical GHCR retention plus artifact retention | Current internal |
| `Azure Bootstrap & Deploy` | Do not use for Phase 10 | Legacy App Service stack | No | Legacy App Service only | Legacy App Service RG path | Legacy |
| `Deploy API to Azure App Service` | Do not use for Phase 10 | No | No | Legacy API only | No | Legacy |
| `Deploy React Frontend to Azure App Service` | Do not use for Phase 10 | No | No | Legacy UI only | No | Legacy |

| Area | Legacy bootstrap (`azure-bootstrap.yml`) | Active Phase 10 (`phase10-deploy-orchestrator.yml`) |
|---|---|---|
| Hosting model | Azure App Service | Azure Container Apps |
| Image/build path | API/UI code deployment to App Service | Separate service image build + container-app deploy |
| SQL Server | Created by the active Phase 10 baseline | Created by `01 Phase 10 Azure Deploy Orchestrator` in the environment RG |
| Redis | Created by the active Phase 10 baseline | Created as Azure Managed Redis by `01 Phase 10 Azure Deploy Orchestrator` in the environment RG |
| App Insights | Created and configured | Created and configured |
| Key Vault | Created and used for app secrets | Created and used for runtime secrets |
| Service Bus | Not the bootstrap focus | Core Phase 10 transport resource |
| Runtime URL style | `azurewebsites.net` | Container Apps ingress or friendly alias |
| Cleanup | Legacy app-stack teardown | Environment-scoped Phase 10 RG teardown |

If you want Azure to match the local Docker containerized experience, treat the following as the explicit verification plan for the active Phase 10 baseline:

| Requirement | Current Phase 10 state | What would be needed to match the containerized target |
|---|---|---|
| SQL Server | Included in the active Phase 10 baseline | Verify the SQL module outputs appear in the deployment summary and portal |
| Redis | Included in the active Phase 10 baseline | Verify the Redis module outputs appear in the deployment summary and portal |
| App Service URLs | Not part of the containerized target | Use Container Apps ingress plus friendly aliases / Front Door names; do not expect `azurewebsites.net` from the active path |

### CI/CD implementation plan for containerized parity

If the goal is to make Azure Portal and the CI/CD path look like the local Docker container graph, the implementation needs to be explicit:

| Step | What changes | Owner workflow |
|---|---|---|
| 1 | Keep the App Service surface archived and treat Container Apps as the supported runtime path | `phase10-deploy-orchestrator.yml` |
| 2 | Keep SQL Server as a first-class module and expose its outputs in deployment summaries | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| 3 | Keep Redis as a first-class module and wire its connection details into app configuration | `infra-deploy.yml` / `phase10-deploy-orchestrator.yml` |
| 4 | Decide on the public URL shape: create friendly aliases for Container Apps via DNS / Front Door | `infra-deploy.yml` alias planning and binding |
| 5 | Update the run summary so portal links, SQL/Redis state, and cleanup status are visible in one place | wrapper summary and child deployment summary |
| 6 | Keep the cleanup path symmetrical so every created resource can be removed from the same CI/CD entrypoint | `cleanupInfra=true` or an explicit legacy teardown path |

Practical rule:
- The active target is the containerized solution, not the old App Service runtime model.
- Use Container Apps ingress or friendly aliases so Azure behaves like the local Docker service graph.
- SQL and Redis are part of the active path and should be verified from the Bicep outputs, workflow summary, and Azure portal after each deploy.
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
| Azure Managed Redis | Deploy only if caching, session storage, rate limiting, or pub/sub is required |

The practical implication is:
- local Docker remains the service-graph reference
- Azure remains containerized, not App Service-based
- public ingress should use Container Apps + aliases or Front Door/WAF
- ACR is the active enterprise runtime image target; GHCR remains only a historical cleanup concern

### Implementation matrix

Use this matrix as the concrete follow-through plan for the Azure portal / CI/CD end state:

| Concern | Current state | Enterprise target | Where to change | Verification target |
|---|---|---|---|---|
| Runtime images | ACR cutover in progress | ACR with Azure-native auth | `build-phase10-images.yml`, `phase10-deploy-orchestrator.yml`, `infra-deploy.yml`, `README-INFRA-DEPLOY.md` | Container Apps revisions pull from ACR successfully |
| Azure identity | OIDC for login only | OIDC + Managed Identity for runtime access | `phase10-deploy-orchestrator.yml`, `infra/main.phase10.bicep`, identity modules | No stored Azure client secrets; runtime auth uses identity |
| Public ingress | Container Apps FQDN only | Container Apps FQDN + friendly alias or Front Door/WAF | `infra-deploy.yml` alias handling, wrapper summary | Stable public URL and summary link for gateway/UI |
| SQL Server | Included in active Phase 10 baseline | Verify the SQL output appears in Azure summary and portal | `infra/main.phase10.bicep`, workflow outputs, runbook | SQL output appears in Azure summary and portal |
| Redis | Included in active Phase 10 baseline | Verify the Azure Managed Redis output appears in Azure summary and portal | `infra/main.phase10.bicep`, workflow outputs, runbook | Redis output appears in Azure summary and portal |
| App Service URLs | Legacy only | Not the active target; replace with containerized ingress/aliases | Archive docs/workflows, keep Phase 10 docs containerized | No operator expects `azurewebsites.net` for Phase 10 |
| Observability | App Insights + LAW present | Add Monitor/trace/alerts as production baseline | `infra/main.phase10.bicep`, monitoring modules | Logs, traces, and alerts visible end to end |
| Cleanup | RG teardown plus retention workflow | Symmetric lifecycle for all created resources | `phase10-deploy-orchestrator.yml`, retention cleanup workflow | Every created artifact/resource has a deletion story |
| ACR image retention | Implemented with the retention workflow | Scheduled ACR cleanup protects active revision images | `phase10-retention-cleanup.yml` | Stale ACR tags/manifests are removed without deleting active revision images |

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
- Swagger is not the Phase 10 smoke gate. Use the gateway health URL plus the routed Orders API smoke URL (`/api/v1/Info/runtime-configuration`) to prove the current Container Apps gateway/API path.
- If the architecture is expanded to include shared foundation resources again, they should be owned by the wrapper-owned infra path, not by the legacy App Service workflows.
- The wrapper summary is the top-level checkpoint; the nested build and Azure deployment jobs hold the detailed child summaries, service-by-service logs, and deployment outputs.
- In practice, use the wrapper summary for the overall result, then open the child build and deploy jobs for per-service logs and Azure deployment details.
- Cleanup is split by storage layer:
  - `cleanupInfra=true` removes the Azure environment-scoped resource group and everything inside it.
  - The cleanup path also checks the environment Key Vault soft-delete reservation and purges it when present, so deterministic names like `kv-orderprocessing-dev` can be recreated on the next deploy.
- ACR image tags and historical GHCR packages are not removed by the deployment wrapper.
  - GitHub Actions logs follow repository or organization retention settings.
  - Phase 10 artifacts uploaded by runtime, transport, and optional Docker E2E workflows use `retention-days: 14`.
  - Log Analytics uses the workspace retention value from `infra/modules/loganalytics.phase10.bicep`, currently defaulted to `30` days.
- `phase10-retention-cleanup.yml` handles ACR stale-tag cleanup, historical GHCR retention cleanup, and stale artifact cleanup without touching Azure deployment resources.

Retention source of truth:
- Artifact retention should be set on the upload step whenever the workflow owns the artifact.
- ACR image retention is handled by the scheduled cleanup workflow for the active runtime image path.
- GHCR package retention is handled by the scheduled cleanup workflow for historical packages only.
- Azure Log Analytics retention is configured on the workspace module, not in the deploy wrapper.

### Scheduled Cleanup Policy

Phase 10 uses scheduled housekeeping for generated storage, not for live Azure environments:

| Storage layer | Owner | Automatic cleanup | Default policy |
|---|---|---|---|
| ACR image tags | `Phase 10 Retention Cleanup (Internal)` | Yes, Sundays at `03:00 UTC` | Keep the latest `10` tags per service, delete stale tags older than `30` days, and skip images referenced by active Container App revisions |
| GHCR container package versions | `Phase 10 Retention Cleanup (Internal)` | Yes, Sundays at `03:00 UTC` | Keep the latest `10` historical versions per image and delete older versions only when they are older than `30` days |
| GitHub Actions artifacts | Upload steps plus `Phase 10 Retention Cleanup (Internal)` | Yes | Uploaded Phase 10 smoke artifacts retain for `14` days; scheduled cleanup deletes stale artifacts older than `30` days as a backup |
| GitHub Actions logs | Repository or organization Actions settings | Yes, by platform setting | Keep at the repo/org standard; do not manage logs from the deploy wrapper |
| Azure Resource Group and live services | `01 Phase 10 Azure Deploy Orchestrator` | No | Manual only with `cleanupInfra=true`; cleanup also purges the environment Key Vault name reservation when Azure exposes it |
| Azure Log Analytics | `infra/modules/loganalytics.phase10.bicep` | Yes, by workspace retention | Default `30` days unless environment policy changes it |

Architectural rule:
- It is safe to schedule cleanup for generated build outputs and stale image versions.
- It is not safe to schedule destructive Azure environment deletion for dev/staging/prod.
- Azure environment cleanup must remain an explicit operator action.

### Phase 10 include-now / defer-later checklist

| Area | Phase 10 status | Notes |
|---|---|---|
| Accepted-host echo in gateway health plus routed API smoke | Include now | Helps operators confirm the routed Azure host and backend route immediately |
| Wrapper deploy summary with run links and actual URLs | Include now | Matches the operator flow already used by the build/deploy jobs |
| Skip-reason logging in preflight | Include now | Better than a bare `skipped` label |
| Symmetric cleanup by env-suffixed name | Include now | Required for predictable dev/staging/prod teardown |
| Local-vs-CI task mapping | Include now | Prevents drift between VS Code and GitHub Actions |
| Per-service build logs plus consolidated summary | Include now | Retains detail without losing the executive view |
| ACR + historical GHCR retention + artifact retention cleanup | Include now | Reduces storage and noise without expanding Azure scope |
| Broad shared-contract extraction | Defer | Add only when duplication is proven across multiple services |
| New platform layer unrelated to transport/deploy/operator UX | Defer | Avoid scope creep in Phase 10 |

Default retention policy:
- Keep the last `10` ACR image tags per service and preserve tags used by active Container App revisions.
- Keep the last `10` historical GHCR package versions per image.
- Upload Phase 10 smoke artifacts with `retention-days: 14`.
- Delete stale GitHub Actions artifacts older than `30` days in the scheduled cleanup workflow as a backup.
- Use dry-run only for manual cleanup previews; the scheduled cleanup run should perform the actual deletion.

| Area | Source of truth | Default |
|---|---|---|
| ACR images | `phase10-retention-cleanup.yml` | Keep last `10` tags per service and preserve active revision images |
| GHCR images | `phase10-retention-cleanup.yml` | Keep last `10` versions per historical image |
| GitHub artifacts | workflow upload step + `phase10-retention-cleanup.yml` | Upload retention `14` days; scheduled cleanup threshold `30` days |
| Azure Log Analytics | `infra/modules/loganalytics.phase10.bicep` / Azure policy | Workspace retention default `30` days |

| Area | Current state | Remaining? |
|---|---|---|
| Azure resource-group teardown | Covered by `cleanupInfra=true` in the Phase 10 wrapper | No |
| GHCR package cleanup | Covered by `phase10-retention-cleanup.yml` for historical packages only | No |
| ACR package cleanup | Covered by `phase10-retention-cleanup.yml` | No |
| GitHub artifact retention | Covered by `retention-days` plus optional cleanup in the housekeeping workflow | No for the updated workflows |
| Azure Log Analytics retention | Covered by the workspace module default; environment-specific policy can tune it later | No blocker |

Local-vs-CI guidance:
- Use the local hook or VS Code tasks when you need to debug the Docker stack interactively.
- Use the GitHub Actions workflow as the pre-merge gate to confirm the same sequence still passes on a runner and still writes the expected log pointers and artifacts.
- In the GitHub Actions run view, the six Phase 10 image builds are expected to appear as one grouped `Build Phase 10 Images` stage with one individual log block per service (`gateway`, `orders`, `payments`, `inventory`, `notifications`, `ui`).
- If you export the run log, those six service logs may be consolidated into a single file even though the Actions UI still shows them individually.

## Runtime Verification Checklist

Use this checklist to prove the shared contract is behaving the same way across both hosts:

1. Local Phase 10 stack
   - Start the local Phase 10 container stack.
   - Confirm the gateway, Orders, Payments, Inventory, Notifications, and UI containers all start with the `orderprocessing-*` image family.
   - Run the local smoke path and confirm the gateway and UI respond on their local ports.
2. Azure infra deploy
   - Run `phase10-deploy-orchestrator.yml` with the target environment and confirm the deployment summary reports the expected gateway and UI ingress outputs.
   - Verify the published image refs match the service-specific `orderprocessing-*` contract for gateway, Orders, Inventory, Notifications, and UI.
   - Verify the environment resource group contains Service Bus, Log Analytics, Application Insights, Container Apps, Functions, Key Vault, SQL Server, SQL Database, and Azure Managed Redis.
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

1. `1 Run: Phase 10 Local Container Stack 00 Start Stack Only (Clean)`
2. `1 Run: Phase 10 Local Container Stack 00 Start Stack Only (Reuse Existing)`
3. `1 Run: Phase 10 Local Container Stack 01 Wait Ready + Keycloak`
4. `1 Run: Phase 10 Local Container Stack 02 Playwright Smoke`
5. `1 Run: Phase 10 Local Container Stack 03 Integration Suite`
6. `1 Run: Phase 10 Local Container Stack 04 Payment Matrix`
7. `1 Run: Phase 10 Local Container Stack 05 Full Validation`
8. `1 Run: Phase 10 Local Container Stack 06 Cleanup After Validation`

Recommended operator pattern:

- Use the clean `00` step to build and start the stack once.
- Let `01` through `05` reuse that same running stack by default.
- Use the reuse variants only for faster debug loops when you intentionally want to skip teardown and rebuild.

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

By default, the hook runs in clean Azure-parity mode. It tears down and recreates the Phase 10 local stack, applies EF migrations to the shared and TenantC databases, verifies the payment-provider baseline rows, checks tenant payment routing, verifies Redis, and then runs smoke, integration, and payment matrix validation. This is the preferred local gate before rerunning Azure `01`.

Use `-ReuseExistingStack` only for a faster inner-loop diagnosis when you intentionally want to keep the current local containers and database state:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -StabilizationDelaySeconds 60 -ReuseExistingStack
```

If you want the same clean-vs-reuse behavior for the local HTTP profile launcher, use the Phase 10 local profile script directly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/start-phase10-local-profile.ps1 -Profile http
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/start-phase10-local-profile.ps1 -Profile http -ReuseExistingStack
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/start-phase10-local-profile.ps1 -Profile http -ReuseExistingStack -SkipStartIfNeeded
```

Use the hook when:

- you want a clean local stack that behaves like a fresh Azure app-RG deployment
- you want migration-owned seed/baseline issues caught before Azure
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
- If Azure deployment fails before Bicep because a provider is not registered, run `00 Azure Platform Foundation` first. Provider registration is subscription-scoped, so deleting `rg-orderprocessing-dev`, `rg-orderprocessing-stg`, or `rg-orderprocessing-prod` does not unregister providers.

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
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay-$environmentName

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
- the ACA environment and App Insights are wired to the same Phase 10 baseline
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
- the ACA environment and App Insights share the same Phase 10 baseline
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
az servicebus topic subscription show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --topic-name order-events-dlq --name dlq-replay-$environmentName
```

Confirm the deployed namespace contains:
- `order-events`
- `inventory-order-created`
- `notifications-order-created`
- `order-events-dlq`
- `dlq-replay-<environment>`

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
- `ServiceBus__DeadLetterSubscriptionName=dlq-replay-<environment>`
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
- App Insights exists and is emitting to the same Phase 10 baseline
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

### 9. Broker Replay Smoke

The automated transport smoke proves the broker path through `tools/Phase10.TransportSmoke`:

1. It dead-letters a controlled message from the inventory subscription.
2. It verifies forwarding to `order-events-dlq`.
3. It receives the message from `dlq-replay-<env>`.
4. It republishes a replay message to `order-events-<env>`.
5. It verifies both downstream subscriptions receive the replayed flow.

This proves topology and controlled receive/republish behavior. It does **not** invoke or prove the deployed `XYDataLabs.OrderProcessingSystem.Functions/DlqReplayFunction.cs`. Phase 10.4 must separately capture the Function package identifier, function discovery, invocation identifier, quarantine/approval state, replay attempt, and downstream business effect before deployed Function behavior is considered complete.

## Success Criteria

- The transport stack deploys cleanly.
- The runtime uses Service Bus instead of the in-memory publisher.
- The first order-created flow is observable end to end.
- Replay and quarantine behavior are both visible in Azure.
- The Phase 10 deployment slice remains separate from the hosting cutover.
- The deployment summary exposes the correct env-suffixed ingress URLs and friendly aliases when enabled.

## If Smoke Fails

- Keep `infra/main.bicep` reserved for the later hosting path.
- Fix the transport wiring or Service Bus config before moving on to broader hosting work.
- Do not introduce `SharedContracts` as a workaround for a transport failure.
