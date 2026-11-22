# Phase 10 Implementation Checklist

This checklist turns the Phase 10 kickoff into a repo-specific pre-Azure execution plan.
It intentionally does **not** reopen Phase 1-9 work; any new enterprise refinements must be captured here in Phase 10 or pushed into later phases.

The canonical pre-Azure architecture baseline for the remaining Phase 10 work is [Phase 10 Pre-Azure LLD](phase10-preazure-lld.md). Treat this checklist as the execution companion to that baseline: the LLD defines the target architecture and governance gates, while this file expands them into the implementation slices, evidence, and operator flow. The checklist must not weaken or reinterpret the L0.5 architecture baseline gate, the architecture invariants, or the three independent L6 acceptance gates defined by the LLD.

Current temporary architecture exceptions are tracked in [Phase 10 Architecture Exception Manifest](phase10-architecture-exception-manifest.md). Any new exception must be recorded there and reflected in the matching architecture test before it is considered an approved transitional dependency.

Phase 10.1 local baseline reconciliation is the 00-05 ladder below: tool readiness, repository validation, Docker infrastructure, optional messaging lane, IDE debug mode, integration tests, and Docker Compose E2E full validation.

Before starting or changing Phase 10 implementation work, validate the developer machine against the canonical tool setup and Environment Readiness Gate in [Phase 10 Tool Prerequisites](../guides/development/phase10-tool-prerequisites.md). Keep installation commands there instead of duplicating them in this checklist.

Current architectural anchor flow:
- `Orders` owns order state and emits `OrderCreatedV1`.
- `Payments` owns payment initiation, callbacks/webhooks, and payment result publication.
- `Service Bus` carries the durable handoff between publishers and consumers.
- `Inventory` and `Notifications` own their downstream business effects.
- `Functions/Operations` own DLQ intake, approval, and replay.
- `SharedContracts` remains deferred unless real duplication proves the need.

## Phase 10 Implementation And Validation Lifecycle

Adopt this as the governing Phase 10 lifecycle. Use a graduated validation model: small local changes get fast checks, platform changes get full Docker and applicable hosted checks, and Azure is used only after local evidence is clean. Hosted parity is required only where the runner can safely reproduce the target environment; approved exceptions must be explicit in the gate scope. Each stage may begin only after the previous required stage passes, unless an explicit exception is documented.

### Validation Stages

| Stage | Name | Required proof |
|---:|---|---|
| 0 | Environment Readiness | Tooling is installed and usable: .NET 8 SDK, PowerShell 7, Node/npm, Docker Compose, Azure CLI, Bicep, Functions Core Tools, GitHub CLI; `global.json` pins the approved .NET 8 SDK; `Resources/Docker/.env.local` exists when Docker profiles require it. |
| 1 | Repository Validation | Restore, build, and unit tests pass before Docker starts: `dotnet restore XYDataLabs.OrderProcessingSystem.sln`, `dotnet build XYDataLabs.OrderProcessingSystem.sln --no-restore`, and `dotnet test XYDataLabs.OrderProcessingSystem.sln --no-build`. |
| 2 | Local Infrastructure Validation | Backing services start and pass health checks in Docker: SQL Server, Redis, Keycloak, Azurite, and Service Bus emulator when selected. No application debugging or browser E2E belongs in this stage. |
| 3 | Local Application Debug | Docker runs backing services while Visual Studio, VS Code, or command-line hosts run the gateway, APIs, UI, workers, and Functions worker for breakpoints and fast defect fixes. |
| 4 | Local Integration Validation | Integration tests prove SQL, Redis, Blob abstractions, messaging abstractions, startup wiring, idempotency, and tenant/provider behavior before browser E2E. |
| 5 | Local Docker Compose End-to-End | Full local Docker validation proves profile startup, gateway routing, Playwright/browser smoke, integration suite, payment matrix, logs, and artifacts. The payment matrix evidence must include the persisted order id, order reference, amount, and currency for each tenant/provider journey. Required before Azure for gateway, auth, Docker, messaging, infrastructure, image, or deployment changes. |
| 6 | CI Pre-Deployment Validation Gate | GitHub-hosted checks validate the changes that can safely run on hosted runners before Azure deployment. Under DW-028 Option A, the local Docker hook is the manual acceptance check and hosted workflow `99` is excluded; never weaken its guard to obtain parity. |
| 7 | Azure Deployment | `00 Azure Platform Foundation` runs only when provider registration, ACR, or pull identity must be created or refreshed. `01 Phase 10 Azure Deploy Orchestrator` deploys the selected environment. Use cleanup mode only when intentionally removing or resetting an environment. Use dry run first for infrastructure changes. |
| 8 | Azure Infrastructure And Configuration Verification | Provisioned resources are healthy; managed identities are assigned; required environment variables are present; secrets resolve from Key Vault; Container Apps revisions are healthy; Function App host runs; Storage, Service Bus, SQL, and Redis are reachable. |
| 9 | Azure Runtime Smoke | `02 Phase 10 Azure Runtime Smoke` proves gateway health, routed API JSON, UI route, and UI API proxy/bootstrap. |
| 10 | Azure Messaging Smoke | Default `03 Phase 10 Azure Transport Smoke` proves publish, fan-out consume, broker DLQ forwarding, and deployed Functions intake only. An opt-in dev-only input can prepare a uniquely identified transient replay candidate; it does not approve or prove replay. IaC now defines a separate dev-only drill request queue and optional entity-scoped runner roles; staging/prod have no drill queue. Orders is the sole Container App replay publisher in source IaC; the deployed Function stays on its normal queue. An optional exact replay-request filter prevents unrelated pending approvals from being routed during a drill. Read-only Azure inspection on 2026-11-22 found the deployed Orders, Payments, Inventory, and Notifications publishers all enabled against the normal queue, with no request-ID filter; the source correction and isolated queue are not deployed. Do not approve a replay until this mismatch is corrected and every enabled publisher is paused/verified during the drill. The authenticated replay gate and two duplicate-delivery cases remain separate acceptance items: redelivery after processed state, and failure after business-event publish but before replay-state/queue completion. Verify the consumer inbox prevents a second durable effect. Historical transport runs do not certify these cases. |
| 11 | Azure Business Validation | `04 Phase 10 Azure Payment Matrix` proves all-tenant business/browser/payment flows against live Azure Container Apps URLs after runtime and messaging pass. |
| 12 | Evidence And Documentation | Capture run summaries, test results, logs, screenshots/traces when applicable, workflow links, deployment outputs, and known issues. Update Phase 10 status docs only after evidence exists. |

### Post-L6 Promotion Sequence

After local pre-Azure L6 passes on a target commit SHA, promote in this exact order:

1. Run `scripts/run-phase10-docker-dev-e2e-hook.ps1` on local Docker Desktop for manual Docker acceptance. Hosted workflow `99` parity is excluded under DW-028 Option A.
2. Run `00 Azure Platform Foundation` only if provider registration, persistent ACR, or pull identity must be created or refreshed.
3. Run `01 Phase 10 Azure Deploy Orchestrator` with `dryRun=true` first for infrastructure-affecting changes, then with `dryRun=false` for the real deployment.
4. Run `02 Phase 10 Azure Runtime Smoke`.
5. Run `03 Phase 10 Azure Transport Smoke`.
6. Run `04 Phase 10 Azure Payment Matrix`.

Do not treat workflow numbering as execution order. The local Docker hook is the manual acceptance check under DW-028 Option A; hosted workflow `99` parity is excluded, while other applicable hosted checks remain required on the reviewed SHA. Workflow `00` remains conditional platform-foundation deployment.

Environment note:

- Use workflow inputs `dev`, `staging`, and `prod`.
- Expect some Azure resource names to shorten `staging` to `stg` in resource-group and app names.
- Treat `Resources/Azure-Deployment/branch-policy.json` as the single source of truth for branch, GitHub environment, resource suffix, and Azure SQL suffix mapping.
- Run `Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` whenever Azure workflow, parameter, or naming changes are introduced. CI PR validation now runs this contract automatically.
- Use the environment-specific checklist in [phase10-azure-smoke.md](../runbooks/phase10-azure-smoke.md) for the exact operator inputs and capture rules for `dev`, `staging`, and `prod`.

### August 11, 2026 Dev Azure Evidence Snapshot

At that time, the `dev` candidate completed the Azure execution lane recorded below; this is historical evidence, not current-candidate acceptance:

| Workflow | Run | Result |
|---|---:|---|
| `00 Azure Platform Foundation` | `31264306311` | Passed |
| `01 Phase 10 Azure Deploy Orchestrator` (real deploy) | `31264680030` | Passed |
| `02 Phase 10 Azure Runtime Smoke` | `31457036766` | Passed |
| `03 Phase 10 Azure Transport Smoke` | `31458734458` | Passed |
| `04 Phase 10 Azure Payment Matrix` | `31459588541` | Passed |

Notes:

- `02` passed on commit `5a1dc0af97420c4d74386ff98b52525ddadc3fc4`; `03` and `04` passed on the follow-up transport-smoke fix commit `bb388e73e4a1983304bec40082e5f71beeed6525`.
- The August 11, 2026 transport-smoke proof is topology-driven: active tenant topology is resolved from the deployed runtime, tenant/provider and dedicated-database contracts are validated before execution, and success is measured through durable SQL effects plus DLQ/replay proof.
- This evidence clears the `dev` lane. Staging remains the next promotion gate; do not treat `prod` as in scope until staging is clean.

### Graduated Gate Policy

| Change type | Required validation |
|---|---|
| Business logic only | Stage 1 plus relevant Stage 4 tests |
| API endpoint | Stage 1 plus Stage 4; use Stage 3 local debug when needed |
| Database/repository | Stage 1 plus SQL-focused Stage 4 tests |
| Messaging/Functions | Stage 1 plus Stage 4 plus Stage 5 |
| Docker/Compose profile | Stage 1 plus Stage 2 plus Stage 5 |
| Gateway/auth/routing | Stage 1 plus Stage 5 plus Azure Stages 7-10 |
| Infrastructure/Bicep/workflow | Stage 1 plus Stage 5 plus Stage 6 plus Azure Stages 7-10 |
| Payment/browser automation | Stage 1 plus Stage 5 plus Stage 6 plus Azure Stage 11 when deployed |

### Stop And Rollback Rules

- Do not start a later stage after a failed required stage.
- If Stage 5 fails, do not deploy to Azure.
- If Stage 6 fails, do not deploy to Azure.
- If Stage 8 fails, do not run Azure runtime smoke.
- If Stage 9 fails, do not run Azure messaging smoke.
- If Stage 10 fails, do not run Azure payment matrix.
- Cleanup is not part of normal promotion; use cleanup mode only for intentional environment reset or removal.
- For Azure failures, either fix and redeploy or run the documented cleanup path through `01 Phase 10 Azure Deploy Orchestrator` with cleanup enabled.

### Lifecycle Assumptions

- Docker Compose remains the canonical local runtime.
- Visual Studio and VS Code are both supported debug environments.
- Aspire remains optional and is not part of the required Phase 10 validation path.
- Service Bus emulator is conditional; where incomplete, local tests use abstractions and Azure validates the real broker.
- Azure Functions project and trigger code are Phase 10 implementation work, not machine-tool prerequisites.
- Legacy App Service workflows are not used for Phase 10 validation.
- Stage ownership can be added later if multiple contributors need a formal responsibility matrix.

### Concrete Local Setup Execution Plan

Use this as the Phase 10 local-first implementation sequence before Azure deployment work.

For a single operator run that executes every pre-Azure local milestone in order, use `2 Run: Phase 10 Pre-Azure Sequence`.

Pre-Azure artifacts and cleanup contract:

- Every L1-L6 run writes immediately under `TestResults/Phase10/local-preazure/`.
- Each milestone creates `run-plan.txt`, `progress.log`, `current-step.txt`, `summary.json`, and latest/failure pointer files before long-running work begins.
- Use `3 Cleanup: Phase 10 Pre-Azure Local Stack (Preserve Volumes)` for the normal teardown path after L5/L6 evidence review.
- Use `3 Cleanup: Phase 10 Pre-Azure Local Stack + Volumes` only when you intentionally want a clean reset of containers and persisted volumes.
- Before L5/L6, make sure rollback proof has a retained previous inventory image available. Set `PHASE10_PREVIOUS_IMAGE_TAG` in `Resources/Docker/.env.local`, or keep a local image tagged with the `phase10-prev-*` convention so the NFR proof can execute rollback instead of documenting it only.
- L5 and L6 now include an explicit `Rollback readiness` gate before the NFR proof so missing image-tag evidence fails fast with a dedicated artifact packet.

| Stage | VS Code / IDE task | Purpose | Exit criteria |
|---:|---|---|---|
| 0 | `1 Run: Phase 10 Local Setup 00 Environment Readiness` | Validate required local tools, `global.json`, Docker Compose config, and Docker `.env.local`. | Tool checks pass and the Phase 10 compose app profile validates. |
| 1 | `1 Run: Phase 10 Local Setup 01 Repository Validation` | Restore, build, and run non-integration unit/regression tests before starting Docker. | Solution build and non-Docker test projects succeed against the pinned .NET 8 SDK. |
| 2 | `1 Run: Phase 10 Local Setup 02 Infrastructure Up (Data + Identity + Storage)` | Start SQL Server, Redis, Keycloak, and Azurite through Docker Compose. | SQL, Redis, Keycloak, Azurite Blob/Queue/Table endpoints are reachable and compose config validates. |
| 2.5 | `1 Run: Phase 10 Local Setup 02.5 Messaging Up (Optional Service Bus Emulator)` | Start the Service Bus emulator lane only when the selected transport strategy needs it. | Emulator SQL is separate from app SQL; emulator AMQP and health endpoints respond when selected. |
| 3 | `1 Run: Phase 10 Local Setup 03 IDE Debug Mode (Backing Services Ready)` | Keep infrastructure in Docker and run gateway, APIs, UI, workers, and Functions worker from Visual Studio or VS Code for breakpoints. | Developer can debug app code locally without replacing Docker Compose as the canonical runtime. |
| 4 | `1 Run: Phase 10 Local Setup 04 Infrastructure Integration Tests` plus the existing application integration suite | Split infrastructure-contract checks from application integration behavior. | Local setup contract tests pass; application integration tests still prove tenant/provider/idempotency behavior. |
| 5 | `1 Run: Phase 10 Local Setup 05 Docker Compose E2E Full Validation` | Run the full Docker Compose validation path after code and infrastructure seams are stable. | Profile startup, gateway routing, Playwright smoke, integration suite, matrix, logs, and cleanup all pass. |

Stage 0 and Stage 1 create evidence immediately under `TestResults/Phase10/local-setup/`:

- `latest-environment-readiness.txt` points to the latest Stage 0 run folder.
- `latest-repository-validation.txt` points to the latest Stage 1 run folder.
- Each run folder contains `progress.log` and `summary.json`.

Compose profile contract:

- `data` owns SQL Server and Redis.
- `identity` owns local Keycloak.
- `storage` owns Azurite.
- `messaging` owns the Service Bus emulator and its dedicated emulator SQL dependency.
- `apps` owns the gateway, service APIs, and UI.
- `functions` owns the Dockerized Functions worker after the local Functions project can run.
- There is intentionally no `all` profile; scripts must compose the required profiles explicitly.

Local debugging contract:

- Run backing services in Docker.
- Run application processes from Visual Studio or VS Code when breakpoints are needed.
- Use `.NET user-secrets` for non-Docker local secrets, layer `Resources/Docker/.env.local.example` plus `Resources/Docker/.env.local` for Docker local defaults/secrets, GitHub secrets for CI, and Key Vault for Azure runtime secrets.
- Keep Service Bus emulator usage conditional. Application logic must remain testable through transport abstractions if the emulator does not support a required production behavior.
- For local HTTP payment validation, the API uses deterministic local payment-provider adapters so TenantA, TenantB, and TenantC can be exercised without relying on the live provider sandbox; Docker Dev HTTP remains the full parity lane.

## Revised Phase 10 Completion Contract

This section is the authoritative completion contract for the remainder of Phase 10. Existing scaffolds, broker utilities, provisioned hosts, and historical smoke runs are inputs to this work; they are not substitutes for production behavior or current evidence.

### Required Phase 10 Scope

| Capability | Required outcome |
|---|---|
| Independently deployable workloads | Orders, Payments, Inventory, Notifications, Gateway, UI, workers, and Functions are runnable, health-checked workloads. Payments must have an executable host. |
| Real business behavior | Azure and Docker routes execute real handlers and persistence. No workload may return hardcoded tenants, provider assignments, customers, payments, or successful business outcomes. |
| Dynamic tenancy and providers | The tenant registry remains authoritative for active tenant, shared-versus-dedicated database tier, and payment provider assignment. Automation must discover and verify this data instead of hardcoding `TenantA`, `TenantB`, `TenantC`, OpenPay, or Razorpay behavior. |
| Durable publication | Committed outbox records are published to Service Bus with the canonical envelope and trace, tenant, correlation, causation, and message identifiers. |
| Real consumers | Inventory and Notifications consume broker messages through module-owned handlers and persist observable business effects. |
| Delivery safety | Inbox/idempotency protection is applied before side effects; retries, restart recovery, duplicate delivery, and permanent failure are deterministic. |
| DLQ operations | Intake, quarantine, approval, replay, replay limits, and poison-message handling have separate ownership and auditable state transitions. |
| Deployed Functions | Versioned Function code is deployed. Smoke evidence includes the deployed Function identity and invocation evidence, not only equivalent behavior from a test utility. |
| Azure identity | Workloads use managed identity and RBAC for Service Bus. Azure users authenticate with Entra ID JWTs. Keycloak remains the local OIDC provider. |
| Secret handling | Runtime secrets are sourced from Key Vault; Service Bus SAS connection strings are removed from Azure workload environment settings after managed-identity proof. |
| Safe delivery | Images and Function packages are immutable, database changes use expand/contract migrations, previous healthy revisions remain available, and exact rollback evidence is captured. |
| Acceptance evidence | Local, Docker, CI clean-room, and Azure validation produce machine-readable result packets and operator evidence before Phase 10 is closed. The local payment matrix must capture persisted order id, order reference, amount, and currency in the result packet. |

### Formal Phase 12 Deferrals

These capabilities remain required roadmap outcomes but are deliberately rephased to Phase 12. Their deferral is governed by ADR-025 and the Deferred Work Log; it is not permission to remove them.

| Deferred capability | Phase 10 boundary | Phase 12 target |
|---|---|---|
| APIM and private YARP ingress | YARP is the Phase 10 ingress and routing proof. Do not add a temporary APIM Consumption topology that cannot reach the intended private backend. | APIM Standard v2 or a then-approved VNet-capable tier fronts private YARP ingress. |
| Private networking | Phase 10 validates authenticated public Azure service endpoints in lower environments. | VNet integration, private DNS, and private endpoints are implemented as one tested network topology. |
| Service Bus Private Link | Phase 10 uses Service Bus Standard with Entra ID/RBAC and transport abstractions. | Move to Service Bus Premium and Private Link when the private network topology is implemented. |
| Blob attachments and Event Grid | Phase 10 Functions are limited to DLQ intake/replay and transport operations. | Add order attachments, Blob lifecycle, and Event Grid-driven processing before Document Intelligence enrichment. |
| SQL managed identity | Phase 10 keeps current SQL bootstrap credentials in Key Vault while service extraction and migrations stabilize. | Move runtime SQL access to managed identity with tested migration/bootstrap ownership. |
| Front Door and WAF | Phase 10 proves the application and transport stack without an unfinished edge tier. | Add Front Door/WAF with APIM and private ingress hardening. |

### Execution Slices

| Slice | Goal | Definition of done | Estimated effort |
|---|---|---|---:|
| 10.2 Real Service Migration | Replace service stubs with real module behavior and data access. | Browser/API flows write authoritative SQL state; all active tenants resolve the configured database tier and provider; Payments is independently hosted; Compose, ACR, ACA, and YARP include every workload. | 7-10 days |
| 10.3 Real Service Bus Processing | Connect outbox publication to real Inventory and Notifications consumers. | One committed order creates one effect in each consumer; duplicate delivery is harmless; restart resumes; permanent failure reaches DLQ; Azure uses RBAC rather than SAS. | 5-7 days |
| 10.4 DLQ And Functions | Separate intake, quarantine, approval, and replay responsibilities and deploy the Functions package. | Poison messages are not auto-replayed; approved transient failures replay once; loops are bounded; Azure evidence proves the deployed Function invocation. | 5-7 days |
| 10.5 Identity And Secretless Transport | Use portable OIDC/JWT authorization and managed identity for Azure transport. | Anonymous requests return 401, invalid tenant/audience returns 403, valid Entra tokens pass Azure policies, local Keycloak remains configuration-only, and Azure workloads have no Service Bus SAS setting. | 5-8 days |
| 10.6 Operations And Non-Functional Proof | Establish measurable delivery, recovery, replay, and latency behavior. | The NFR baseline, failure drills, alerts, dashboards, rollback path, and lower-environment load proof pass. | 3-5 days |
| 10.7 Acceptance And Closeout | Execute the lifecycle gates and publish auditable evidence. | Current local, Docker, CI, and Azure result/evidence packets pass with no unresolved critical risks or undocumented exceptions. | 3-5 days |

Estimated remaining elapsed engineering effort is **28-42 working days**, excluding external approval, quota, and Azure incident delays.

### Detailed Implementation Guardrails

#### 10.2 Real Service Migration

- Characterize existing stub routes before replacement so contracts remain stable.
- Route service hosts through module handlers and repositories; do not introduce dual writes.
- Add a Payments executable host and real Inventory/Notifications behavior.
- Add service-specific liveness and readiness checks for required dependencies.
- Publish immutable commit-SHA image tags and add Payments to Compose, ACR, ACA, and YARP.
- Run migration/seeder jobs before promoting a revision.
- Keep shared/dedicated database choice and payment-provider choice registry-driven.

#### 10.3 Real Service Bus Processing

- Introduce reusable consumer orchestration while keeping business handlers module-owned.
- Resolve tenant context from validated envelope metadata before opening the tenant database.
- Record inbox/idempotency state before business side effects and complete the broker message only after the transaction commits.
- Classify transient and permanent failures explicitly and apply subscription filters where event ownership requires them.
- Use a local connection string only for the emulator; use `DefaultAzureCredential` and scoped Service Bus RBAC in Azure.

#### 10.4 DLQ And Functions

- Use separate `dlq-replay-<environment>` subscription intake and `dlq-replay-requests` approval paths. Intake classifies and quarantines; replay consumes only approved requests.
- Do not attach intake and replay Functions to the same subscription.
- Set `AutoCompleteMessages = false` wherever completion, abandonment, or dead-lettering is controlled by application code.
- Preserve message body, content type, application properties, message/correlation/causation/tenant identifiers, trace context, failure reason, and original enqueue metadata.
- Enforce a replay-attempt ceiling of `5`, a kill switch, and one replay owner per message.
- Package Functions by commit SHA or workflow run ID, deploy through the orchestrator, and verify host, function discovery, and invocation.
- Use scale-to-zero-capable Function hosting for the final Phase 10 topology.

#### 10.5 Identity And Secretless Transport

- Configure ASP.NET Core `JwtBearer` variants for local Keycloak and Azure Entra ID.
- Use Authorization Code with PKCE in the React client.
- Enforce authorization policies and tenant claim/header consistency at ingress and service boundaries.
- Keep provider webhooks anonymous only at the authentication layer; require provider signature verification.
- Assign least-privilege Service Bus data roles to each workload identity.
- Source provider and SQL bootstrap secrets from Key Vault and remove Azure Service Bus SAS settings after RBAC proof.

### Non-Functional Baseline

The following lower-environment targets are provisional Phase 10 acceptance values. Any change requires an evidence-backed exception in the closeout packet.

| Concern | Phase 10 target |
|---|---|
| Delivery guarantee | At-least-once transport with one idempotent business effect |
| Maximum message size | 256 KB; larger payloads require the deferred Blob claim-check design |
| Message TTL | 7 days |
| Maximum broker delivery count | 10 |
| Maximum replay attempts | 5 |
| Ordering | No global ordering; decide through ADR-023 whether per-order sessions are required |
| Restart recovery | No committed outbox message or committed consumer effect is lost |
| Burst proof | 100-message lower-environment burst with no lost or duplicate business effects |
| Consumer latency | P95 under 30 seconds in lower environments |
| Approved replay visibility | Under 60 seconds in lower environments |
| Recovery point | No committed outbox loss |
| Operational recovery time | 30 minutes for the documented rollback or recovery path |

Required SLIs include outbox-to-broker latency, broker-to-consumer latency, failure/retry rate, DLQ depth and oldest age, replay latency, Function invocation/rejection/failure, and order/payment outcomes.

### Rollback Contract

- Retain the previous healthy ACA revision and immutable commit-SHA image references.
- Retain Function packages by commit SHA or workflow run ID.
- Make transport publication, each consumer, and replay independently disableable.
- Introduce Service Bus topology additively; drain old entities before deletion.
- Use forward-only expand/contract database migrations and keep the old route until the real endpoint passes.
- Never auto-remove the last healthy environment after a failed deployment.
- Record the exact rollback command, target revision/package, operator, timestamp, and result in the evidence packet.

### Risk Register

| Risk | Priority | Required mitigation |
|---|---|---|
| Stub replacement breaks payment behavior | Critical | Characterization tests, one-service cutover, database assertions, and rollback route |
| Duplicate replay creates duplicate side effects | Critical | Inbox uniqueness, replay-attempt ceiling, approval state, and duplicate-delivery tests |
| DLQ intake and replay compete for one subscription | Critical | Separate entities and single-purpose Functions |
| Function host deploys without executable code | High | Versioned package deployment plus function-discovery and invocation proof |
| Tenant resolves the wrong database | Critical | Registry-driven resolution and shared/dedicated integration tests |
| Provider routing becomes hardcoded | High | Registry-driven provider assertions in API and browser matrices |
| Managed-identity RBAC is incomplete | High | Role-assignment verification and SAS-free Azure runtime smoke |
| Database migration cannot roll back safely | High | Expand/contract sequencing and retained compatible revision |
| Rephased cloud hardening disappears | Medium | ADR-025, Phase 12 roadmap entries, and Deferred Work Log closure triggers |

### Evidence Contract

Keep the automated result packet separate from the operator evidence packet.

Automated result packet:

- `summary.json`, TRX/JUnit results, stage statuses, and process exit code.
- Git commit SHA, image digests, Function package identifier, workflow/run ID, environment, and IST timestamps.

Operator evidence packet:

- Function host/function/invocation identifiers.
- Service Bus message, correlation, subscription, DLQ, and replay identifiers.
- Application Insights traces and authoritative SQL state.
- Replay approval, attempt, quarantine, and completion metadata.
- Azure configuration/RBAC verification.
- Failure-only browser screenshots/traces plus known issues and approved exceptions.

## Tracker Status (Historical snapshot; see the dated 16 November completion record below for current bounded acceptance)

| Area | Status | Notes |
|---|---|---|
| Phase 10 repo transport scaffold | Broker baseline verified in dev | The Service Bus topology, transport adapter layer, startup seam, and utility-driven replay path are in the repo. Real consumers and deployed Function invocation remain open under 10.3 and 10.4. |
| Phase 10 docs and runbooks | Completion contract aligned | The checklist, smoke runbook, DLQ replay guide, progress tracker, ADRs, and Phase 12 deferrals describe the same required scope. |
| Phase 10 operator-experience hardening | Verified in dev | Accepted-host echo, deploy-summary traceability, skip-reason logging, cleanup symmetry, local-vs-CI mapping, and per-service build logs are present in the active workflow path. |
| SharedContracts extraction | Deferred | Keep it out unless transport work proves real duplication across multiple services. |
| Earlier phase scope | Frozen | Do not back-port new enterprise refinements into Phases 1-9; keep them in Phase 10 or later only. |
| Azure dev deploy | Verified | GitHub Actions run `29273224237` built the Phase 10 images and deployed the dev Container Apps transport stack successfully. |
| Phase 10 runtime smoke | Verified | GitHub Actions run `29273711615` proved gateway health, gateway-routed API JSON, UI static route, and UI API proxy bootstrap. |
| Phase 10 broker transport / replay smoke | Verified | GitHub Actions run `29273881488` proved Service Bus publish, fan-out consume, controlled DLQ forwarding, DLQ replay receive, and utility-driven replay publish/consume; it did not invoke or prove the deployed Azure Functions worker. |
| Azure Functions infrastructure | Provisioned host | `infra/modules/functions.bicep` creates the Function App host and identity plumbing. |
| Azure Functions worker implementation | Local replay source corrected; runtime proof pending | The .NET 8 isolated host includes startup validation, DLQ intake, and guarded replay. The local NFR probe now requests approval through the existing Keycloak PKCE session and protected API instead of synthesizing approval with SQL; its runtime path is not yet exercised. Azure deployment, Functions invocation, and replay effects remain pending. |
| SQL / Redis baseline wiring | Automatic baseline | The wrapper and child deploy workflows include SQL and Redis as part of the default Phase 10 path; no manual parity toggle is required in the normal operator form. |
| Cleanup policy closeout | Partial | GHCR/artifact retention remains scheduled and Azure teardown remains manual. ACR deletion is disabled until digest inventory, active revision protection, and verified rollback evidence are complete. |
| ACR image cleanup policy | Preview implemented; deletion blocked | Manual inventory preview includes Payments. Digest selection has fixture tests; scheduled ACR deletion is disabled because the prior tag-based check did not protect digest-qualified deployed images or establish a verified rollback digest. |
| P0 cost controls | Budget recorded; original test window expired | Owner-created ₹5,000 monthly subscription budget on subscription ending `980c`, with one 50% actual-cost alert recipient and expiry `2028-10-31`, was recorded. Owner/cleanup approver: Pavan Thakur. Original planned window: 13 Nov 2026 20:15 IST to 15 Nov 2026 06:57 IST. A later extension expired 15 Nov 22:30 IST. Evidence and later read-only cost observation are recorded in the dated completion section below. Budget alerts do not stop charges. |
| P4.1/P4.2 Azure foundation | Provisioned (historical read-back) | Workflow `00` run [43445749120](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43445749120) and `00a` run [43446186450](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43446186450) succeeded for `f334548f`. Read-back confirmed platform ACR/UAMI, dev resource group, Log Analytics workspace and ACA environment at that time. Generated ACA domain recorded then: `jollydune-ba9fd8a5.centralindia.azurecontainerapps.io`; verify current state before new operations. |
| P4.3 Entra configuration | Provisioned; admin assigned | API/SPA registrations and service principals exist; delegated `access_as_user`, `platform-admin` role, application-tenant extension, generated dev callback/logout URLs, and eight GitHub dev variables read back consistently. The current signed-in account received the API `platform-admin` role and Graph read-back verified it. Named regular-user assignments/claims remain pending before P6.1. |
| P4.4 deployment permissions | Scoped grants created; workflow proof passed | GitHub OIDC principal `b017387c-ae72-4495-90a4-36fec97c8360` has condition-limited `Role Based Access Control Administrator` at `rg-orderprocessing-dev`, restricted to `Storage Blob Data Owner` assignments for service principals. The platform ACR pull UAMI has `AcrPull` scoped to that registry. Workflow `01` preflight passed OIDC and subscription/RBAC checks. |
| P5.1 immutable release | Complete | Build run [43452746987](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43452746987) published six digest-qualified application images and the Functions package from `f334548f`; release manifest and package checksum validated locally. |
| P5.2 first Azure dev deployment | Deployed; bounded runtime/payment acceptance later completed; operational acceptance remains open | Historical deployment runs and known Functions indexing issue are documented here. Subsequent repairs/deployments and the bounded six-case Azure payment matrix are recorded below. Do not treat that payment matrix as proof of workflow `02`, transport/replay, regular-user isolation, NFR or rollback acceptance. Verify deployment/image identity before further tests. |
| P6.0/P6.1 Azure identity and payments | Admin preflight and six Azure-dev sandbox positives passed in a reconciled run; broader identity acceptance open | See the 21 November checkpoint below. This is not uninterrupted payment acceptance, unattended workflow `04`, regular-user isolation, token expiry, or full security acceptance. |
| P2 cost snapshot | Implemented; live read-only snapshot captured | The helper and supported output normalization are described in `scripts/README.md`. Snapshot `TestResults/AzureCost/phase10-dev-20261116-cost-snapshot.json` is a lagging month-to-date observation; missing SQL size limits remain unknown, not zero. |

> **Historical status correction (14 November 2026):** The P5.2 statement “No cloud deployment or live recheck occurred” and the initial no-charge P6.0 preflight describe the state at that time only. They are superseded by the bounded 15 November Azure payment record and 16 November completion record below; those later records do not certify broader Azure transport, identity, recovery, or workflow acceptance.

### Azure-dev checkpoint — 21 November 2026

- Recorded deployment: workflow `01` run `44910591587` used workflow SHA `6fbc5454` and immutable application release source `47970357`. Runtime smoke `44912299578` and transport smoke `44913188578` passed within their recorded scope. The transport run proved deployed Functions quarantine, not approved replay. Hosted workflow `04` run `44913439630` was service-preflight only. Automation commit `1afc4edd` separately passed its four triggered hosted checks; it is not the application release SHA.
- The original matrix `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-21T16-53-18-386Z/summary.json` remains **FAIL** (four verified, TenantC/Razorpay provider-confirmed but verifier failed, TenantC/OpenPay not started, sign-out not verified). The read-only reconciliation sidecar `checkpoint-reconciled-a321ac7f-cd34-467f-b1be-64519632d191-evidence.json` in the matching child `payment-automation-2026-11-21T16-53-18-386Z` directory records TenantC/Razorpay verification PASS without resubmission. The original verifier exit cause was not established.
- Resumed matrix `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-21T17-21-05-312Z/summary.json`: **PASS 6/6**, four carried-forward cases, one read-only reconciled case, one fresh TenantC/OpenPay payment. Entra preflight, sign-out and settings restoration passed. For carried-forward provider status, consult original confirmation artifacts; the resumed summary does not requery providers for those rows. OpenPay 3DS was temporarily off during testing; the Azure baseline was on and was restored. Neither report proves uninterrupted fresh acceptance or a hosted payment run.
- Still open: named regular-user Entra isolation and expiry, approved deployed replay plus both duplicate-delivery cases, supported sandbox negatives, Azure NFR/rollback, and unified release-bound evidence. Revalidate live identity and agree a new scoped dev test window before execution. This checkpoint does not close Phase 10 or authorize Azure changes.

### Enterprise Standard Placement

Use this table to keep the enterprise plan aligned with the current Phase 10 scope instead of mixing everything into the same release slice.

| Enterprise item | Where it fits | Why |
|---|---|---|
| Single `runId` correlation, one run folder, one summary, one artifact packet | Phase 10 now | This is the execution model and operator UX standard for the current repo flow. |
| GitHub Actions summary and per-run artifact packet | Phase 10 now | This shortens diagnosis and makes CI output deterministic. |
| Secure secrets via GitHub Secrets / Key Vault | Phase 10 now | Required for the live Azure deploy and local parity paths already in the repo. |
| Structured logging with `runId` | Phase 10 now | Needed for the current deploy / smoke / transport traceability. |
| Clean/reuse local validation modes | Phase 10 now | Keeps the operator flow fast while still allowing full rebuilds when needed. |
| ACR lifecycle cleanup plus artifact retention | Phase 10 now | Required to keep image and log storage under control for the live Phase 10 path. |
| Azure platform foundation ACR and pull identity | Phase 10 now | Supports the persistent registry/runtime-pull model without manual RG-level IAM. |
| SQL / Redis parity in Azure | Phase 10 now | Covered by the active Phase 10 baseline and should remain part of the default deploy path. |
| Managed Identity for SQL runtime access | Phase 12 / DW-021 | Apply after service migration and database bootstrap/migration ownership stabilize. |
| OpenTelemetry trace/span expansion | Phase 10.6 | Required for transport, consumer, Function, DLQ, replay, and business-outcome SLIs. |
| SharedContracts extraction | Deferred unless duplication is proven | Keep module boundaries clean until transport code proves real cross-service duplication. |

Practical rule:

- **Phase 10 now** owns execution shape, operator UX, cleanup hygiene, platform foundation, SQL/Redis parity, and live Azure proof.
- **Phase 12** owns the explicitly rephased private-platform and SQL managed-identity hardening under ADR-025.
- **Deferred** items only move forward when the repo proves the need with real duplication or an explicit hardening gate.

### Post-Phase-10 Multitenant Hardening Placement

Use this placement rule so the current Phase 10 closure remains narrow and future multitenant hardening does not disappear into general backlog noise.

| Topic | Phase | Why |
|---|---|---|
| Topology artifact and promotion-safe topology proof | Phase 10 | Protects the current runtime and promotion model without expanding into general hardening |
| Topology evidence in each environment where Phase 10 smoke or payment-matrix execution runs | Phase 10 | Evidence is part of the current validation contract, not a future platform enhancement |
| `staging` / `prod` promotion-safe topology proof even when full payment matrix is not executed | Phase 10 | Promotion safety must be explicit before final closeout |
| Tenant lifecycle operations: onboarding, activation, shared/dedicated moves, provider reassignment, rollback | Phase 11 | Follow `phase11-implementation-plan.md`: provision and validate DB, migrations, secrets, provider contracts, and identity grants before the final registry activation |
| Discovery = registry truth; validation = infra/secret/runtime contract | Phase 11 | This becomes a governed operator workflow once transport closeout is done |
| Drift detection and repair between registry, secrets, DB topology, and runtime execution | Phase 11 | Reconciliation belongs with service autonomy and topology operations |
| Order-based pending-payment recovery and adversarial browser coverage | Phase 11 | Owner-approved local sandbox carry-forward DW-023; original-provider recovery and edge cases remain unverified, not production-ready |
| Razorpay S2S entitlement and real OpenPay negative fixtures | Phase 11 | Owner-approved carry-forward DW-024; unsupported paths remain unavailable and cannot be reported as real-provider PASS |
| Observability dashboards, alerting, provider rotation, DR, quotas, noisy-neighbor policy, security hardening closure | Phase 12 | These are platform-operability concerns, not Phase 10 transport/runtime exit criteria |

### Verified Azure Dev Proof

| Proof | Run | Result | What it proves |
|---|---|---|---|
| Deploy orchestrator | `29273224237` | PASS | Preflight, per-service image build, and Azure dev resource deployment completed through the wrapper path. |
| Runtime smoke | `31457036766` | PASS | Gateway health, gateway-routed API runtime configuration, UI route, and UI API proxy returned `200` on the current August 11 validation lane. |
| Broker transport smoke | `31458734458` | PASS | Service Bus topology exists, runtime tenant/provider topology resolves, durable inventory/notification SQL effects are observed, DLQ forwarding succeeds, and replay-subscription proof passes; deployed Function invocation was not exercised. |
| Azure payment matrix | `31459588541` | PASS | All-tenant Azure browser/payment automation completed, verification remained enabled, and the run packet uploaded successfully on the current August 11 validation lane. |
| Local/CI container parity | `29268434294` | PASS | Docker Dev HTTP E2E passed smoke, integration, payment matrix, and cleanup on the optional CI parity workflow. |

### Cleanup Policy Snapshot

| Area | Current state | Remaining? |
|---|---|---|
| Azure resource-group teardown | Covered by `cleanupInfra=true` in the Phase 10 wrapper | No |
| GHCR package cleanup | Covered by `phase10-retention-cleanup.yml`; weekly schedule keeps latest `10` historical package versions and deletes older versions after `30` days | No |
| ACR manifest cleanup | Manual inventory preview only; deletion disabled pending complete digest and rollback evidence | Yes |
| GitHub artifact retention | Covered by `retention-days: 14` on Phase 10 uploads plus scheduled stale-artifact cleanup after `30` days | No |
| Azure Log Analytics retention | Covered by `infra/modules/loganalytics.phase10.bicep` default `30` day workspace retention | No blocker |
| Azure resource-group scheduled deletion | Intentionally not automated | No; keep destructive cleanup manual |

### ACR Cleanup Implementation Plan

ACR is the enterprise target for Phase 10 runtime images. The ACR cutover is not complete unless image cleanup is implemented alongside image publishing and runtime pull changes.

| Step | Implementation requirement | Done when |
|---|---|---|
| 1 | Provision the persistent platform ACR and runtime pull identity from `00 Azure Platform Foundation` | The platform resource group contains the registry and pull identity; `AcrPull` is granted only when the privileged platform path is allowed to manage RBAC |
| 2 | Build and push gateway, Orders, Payments, Inventory, Notifications, and UI images to ACR | The Phase 10 build workflow publishes all six service-specific ACR image refs |
| 3 | Point the app deployment at the platform ACR and pull identity | Container Apps pull ACR images without `GHCR_READ_TOKEN` and without the app deployment itself creating RG-level role assignments |
| 4 | Keep SQL and Redis in the automatic deploy baseline | The wrapper and child workflow provision SQL and Redis as part of the default Phase 10 path so the operator does not need to toggle them on |
| 5 | Add safe ACR retention automation | Preview is implemented; digest-level deletion remains blocked until complete cross-environment active revision inventory, one verified rollback digest per service, and release/cleanup coordination are proven |
| 6 | Retire GHCR runtime dependency | `GHCR_READ_TOKEN` is no longer required by the active Azure deployment path |
| 7 | Update summaries and runbooks | Deploy summary identifies ACR image refs, parity flags, and the cleanup policy owner |

ACR retention policy proposal for dev (deletion currently disabled):
- Keep the latest `10` manifests per service and at least `30` days of history.
- Protect the current deployed digest and one verified rollback digest per service.
- Require a complete read-only preview and separate review before any future deletion implementation; do not enable a schedule by default.

ACR retention posture for staging/prod:
- Use a longer retention window than dev.
- Preserve digest-qualified images referenced by active and verified rollback Container App revisions; tags are descriptive and are not the protection key.
- Do not delete images referenced by active or rollback Container App revisions.

Use the existing envelope and metadata types as the canonical shape:
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelope.cs`
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelopeMetadata.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Contracts/Events/OrderCreatedV1.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedDomainEventMapper.cs`

## Phase 10 Exit Gate

Phase 10 is ready to call complete only when all of the following are true:

- Slices 10.2 through 10.7 satisfy the Revised Phase 10 Completion Contract.
- Orders, Payments, Inventory, and Notifications are real independently runnable workloads, not compatibility stubs.
- Tenant database tier and payment-provider routing are registry-driven and proven across shared and dedicated database scenarios.
- The order-created flow uses the canonical envelope, committed outbox publication, real Service Bus consumers, inbox/idempotency, and observable SQL business effects.
- DLQ intake, quarantine, approval, and replay have separate ownership, bounded retries, and no competing triggers.
- The deployed Azure Function package is discovered and invoked in smoke evidence; a broker utility performing equivalent operations is not sufficient.
- Azure workload transport uses managed identity and scoped RBAC without Service Bus SAS settings.
- Entra ID protects Azure ingress and APIs; local Keycloak exercises the same JWT/OIDC policy model.
- Immutable images/packages, expand/contract migrations, retained healthy revisions, and an executed rollback proof are documented.
- The NFR baseline and required failure drills pass.
- Current Stage 0-12 result and evidence packets are complete and traceable to the same commit SHA.
- A topology artifact exists for every environment where the Phase 10 smoke or payment-matrix path executes.
- `staging` and `prod` promotion evidence includes topology contract proof even when the full payment matrix is not part of the normal promotion path.
- Phase 12 deferrals are present in ADR-025, `ARCHITECTURE-EVOLUTION.md`, and the Deferred Work Log.
- `SharedContracts` remains deferred unless real cross-service schema duplication proves the need.

If any one of those items is not true, Phase 10 is still in progress.

## Remaining Pre-Azure Implementation Board

### Current Non-Azure Acceptance and L6 Checkpoint — 12 November 2026

**Status clarification (12 November): L6 gate C is closed/PASS for `494ab4fd` under DW-028 Option A, not pending or unrun.** The separate combined report gate `l6-ci-parity-and-azure` remains NOT-RUN because Azure acceptance has not been executed; it is not the scoped non-Azure L6 gate C. Workflow `99` is intentionally local-only, not a failed required hosted check. Proposed Checkpoint A improvements (no-PR CI triggers, service-path coverage and truthful summaries) are prospective delivery improvements, not remediation required to reopen or re-pass this accepted gate. Later candidates still require their applicable checks; no acceptance is transferred automatically.

### Checkpoint A — Hosted-CI improvement status

The implementation adds direct push/manual validation to existing `ci.yml`, removes bypassable path filters, enforces a read-only no-deployment contract with parsed-YAML regression tests, emits revision-bound PASS/FAIL/INCOMPLETE evidence and sanitized TRX artifacts, and documents the local-Docker/Azure distinction. Local contract, sanitizer, repository-governance and foundation checks pass. The push-triggered hosted acceptance passed on `1665030e64450475c48c97cf424c2b5cbdf71fa1`: [CI run 43134179936](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43134179936) concluded successfully and uploaded `hosted-ci-43134179936-1`; its evidence JSON reports PASS with event and checkout SHA matching, and all five TRX files contain passing tests (18 Domain, 79 Application, 165 API, 13 Gateway, 98 Architecture). Applicable same-SHA checks passed: [Documentation Links](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43134179904), [AI Prompts](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43134179883), [Drift Scanner](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43134179910), and [AI Customization](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43134179961). ADR validation was skipped by its applicability filter because this change did not touch ADRs. Manual dispatch was not separately exercised. GitHub reported a Node 20 deprecation annotation for `actions/setup-node@v4` and existing .NET analyzer warnings; these did not fail validation and were not changed in this checkpoint. This work does not rerun Docker, payments, or Azure and does not alter the `494ab4fd` L6 C PASS; it is future-candidate CI hardening, not a defect in historical gate C.

**Result: bounded non-Azure Docker acceptance and the three scoped L6 gates passed on clean candidate `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`.** The Docker E2E run `phase10-docker-http-20261111-230915653` and NFR run `phase10-docker-nfr-20261111-234505649` use the same 13 service image IDs and reconcile to PASS. The sealed L5-R report has no issues and contains measured backend, frontend, and integration coverage. A current-candidate architecture conformance run passed 42 architecture-invariant tests and one Gateway topology test. Hosted checks on this SHA passed: [AI Customization](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43078347658) on Windows and Linux, [Documentation Links](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43078354940), and [Drift Scanner](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43070162309). Under DW-028 Option A, hosted workflow `99` is excluded and its local manual Docker check remains the acceptance path.

| Gate | Current bounded verdict | Evidence and limits |
|---|---|---|
| A — Architecture conformance | **PASS** | Candidate `494ab4fd`; `TestResults/Phase10/local-preazure/20261111-235924285_architecture-conformance` (42 architecture invariants + 1 Gateway topology test). |
| B — Local Docker, operations, NFR and rollback | **PASS (bounded local evidence)** | Candidate `494ab4fd`; E2E/NFR runs above. Six deterministic and six sandbox payments across TenantA/B/C × Razorpay/OpenPay; 100/100 message effects at 2.273 s P95; replay 1.080 s; outage recovery 26.201 s with zero loss/duplicates; Inventory rollback and restore passed. |
| C — Deployment-readiness hosted checks | **PASS under DW-028 Option A** | Same candidate SHA: AI Customization Windows/Linux, Documentation Links, and Drift Scanner passed. Workflow `99` hosted parity is intentionally excluded. No mandatory-PR requirement was introduced. |

The sanitized tracked projection is `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`; the exact reconciliation and raw evidence remain in ignored local `TestResults`. This is **not full Phase 10 closure**: Azure and the combined `l6-ci-parity-and-azure` acceptance remain NOT-RUN; DW-023/DW-024 remain Phase 11 deferrals; visible OpenPay 3DS, Razorpay S2S, fulfillment, installments, and ACA revision rollback are not certified. The checklist evidence is bound to candidate `494ab4fd`, not to later documentation-only commits.

### Historical Non-Azure Acceptance Checkpoint — 11 November 2026

**Result: non-Azure local acceptance PASS on one clean committed candidate `f2bd3587`.** The owner authorized the non-Azure implementation and local acceptance run; Azure and Phase 11 stayed excluded. At the time this checkpoint was first recorded, nothing had been pushed; subsequent documentation-only scope/evidence updates are recorded below and at `3659a743`. Run `npm --prefix automation run reconcile:phase10-acceptance -- --e2e <docker-run> --nfr <nfr-run>` combines the sealed Docker E2E run (`phase10-docker-http-20261111-024241244`) and the NFR run (`phase10-docker-nfr-20261111-023057463`) into one verdict bound to a single commit with a clean worktree at start and finish. The compact tracked evidence is `TestResults/Phase10/accepted/phase10-local-acceptance-f2bd3587.json`; its source checksum identifies the full reconciliation packet, which remains in ignored local `TestResults`.

### Historical Non-Azure L6 Gate Verdicts (11 November 2026)

This dated record is superseded for current status by the 12 November checkpoint above. Its mixed-revision limitation is historical; same-candidate acceptance was subsequently established on `494ab4fd`.

| Gate | Verdict | Evidence |
|---|---|---|
| A — Architecture conformance | **PASS** | Commit `3659a743`; 42 architecture-invariant tests and 1 gateway-topology test passed in `TestResults/Phase10/local-preazure/20261111-080024980_architecture-conformance`. |
| B — Local Docker, operations, NFR and rollback | **PASS (bounded local evidence)** | Commit `f2bd3587`; the accepted E2E/NFR packet above includes six deterministic and six sandbox payment journeys, messaging/Functions, persistence, restoration, replay/recovery and a single-service rollback/restore. No new payment run was performed. |
| C — Deployment-readiness hosted checks | **PASS under DW-028 Option A** | Commit `3659a743`: [AI Customization](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42945848330) passed on Windows and Linux; [Documentation Links](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42945847974) and [Drift Scanner](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42945848074) passed. ADR validation was skipped by its path filter. Hosted workflow `99` was intentionally excluded; the manual local hook is the accepted Docker check. |

These are individually bound gate results, not a new all-in-one report: A/C are on `3659a743`, while B remains on `f2bd3587`. No application/runtime source changed between those revisions; the later environment-contract validator was separately checked at `3659a743` (178 passes, 0 failures). Do not rewrite the historical Docker packet or claim a fresh payment run. Before Azure promotion, satisfy the Pre-Azure LLD's one-target-SHA and image-identity evidence requirement or obtain a separately reviewed exception. This scoped non-Azure gate result does not complete Phase 10 or certify Azure.

Passed gates: sealed completion, foundations, smoke, integration, OpenPay baseline, baseline validation, customer directory, TenantC routing, deterministic and sandbox payments (3 tenants x 2 providers), currency order entry, messaging/Functions, persistence restart, provider restoration, storage; L5-R report with no reconciliation issues and measured backend, frontend and integration coverage; NFR functional, performance, tenant, payments, operational, recovery and security; 100-message burst (P95 2.0 s, limit 30 s); approved replay visibility 1.07 s (limit 60 s); consumer-outage backlog recovery 26 s with 0 lost and 0 duplicate effects (limit 30 min); rollback to the previous inventory image executed and the current image restored.

Scope limits that remain explicit:

1. **Rollback evidence is a single-service local image swap.** The previous image `phase10-prev-290d0fba` was built from a clean export of the committed base `290d0fba` (provenance in `TestResults/Phase10/rollback-baseline/290d0fba/provenance.json`). No application source differs from the base, so it proves the swap/restore mechanism and schema readiness, not a behavioural difference, and it is not an ACA revision rollback. Images are locally built and have no registry digest.
2. **DW-023 order continuation and DW-024 provider capability remain deferred to Phase 11** and are never counted as PASS. Fulfillment, installments and unresolved-payment recovery are not certified.
3. **Non-Azure L6 gates A/B/C have the bounded verdicts above.** DW-028 Option A scopes workflow `99` to local/manual acceptance; its hosted parity is excluded and the safety guard is unchanged. The evidence revisions differ (`f2bd3587` for B; `3659a743` for A/C), so no single refreshed same-SHA acceptance packet is claimed. Azure stages (`00`-`04`) remain NOT-RUN and separately approval-gated; Phase 10 is not complete.
4. A visible OpenPay 3DS challenge and Razorpay S2S remain uncertified.

### Pre-Azure Image-Integrity Implementation Checkpoint — 11 November 2026

**Historical checkpoint, not the current action list.** The then-pending same-candidate/image-identity acceptance described below was subsequently completed on `494ab4fd`; see the 12 November checkpoint above. Preserve these earlier limitations as evidence history, not as instructions to repeat payment or Docker acceptance. Azure acceptance remains separately pending.

**Runtime evidence on `58c361a9` is historical PASS under the old v1 reconciler, not image-bound acceptance.** The E2E run `phase10-docker-http-20261111-103838867` and NFR run `phase10-docker-nfr-20261111-102444152` both recorded the same clean source SHA `58c361a9d0c594da604c0a274204c8dbb72090ea`. E2E recorded six deterministic and six sandbox payment journeys across TenantA/B/C and both providers. NFR recorded 100 messages/effects, P95 **2.16305 s** (limit 30 s), replay visibility **1.085 s** (limit 60 s), backlog recovery **28.027 s** (limit 1,800 s), zero lost messages and zero duplicate effects, plus local image rollback/restore. The old reconciler returned PASS because it did not compare image identities.

The available image observations are not a sealed before/after pair. E2E `rollback-images.json` recorded Inventory `sha256:d619aefc…`; the NFR retained-image digest log also recorded `sha256:d619aefc…`. A separate supplemental E2E inventory captured after that E2E run recorded Inventory `sha256:926ef950…`, but its candidate was null, it was captured after the run, and it was not included in completion-v3 hashes. Therefore image identity for the runtime runs is **BLOCKED / not proven**; do not treat the supplemental inventory as conclusive evidence of the image used during E2E. Hashes and sanitized facts are in `TestResults/Phase10/accepted/phase10-preazure-image-evidence-58c361a9.json`.

The 11 November implementation changes the Gateway and Functions restore inputs, captures the 13 expected project-owned Compose image identities before/after E2E and NFR, seals E2E manifests in completion-v4, renders validated IDs in the preview, and rejects same-SHA/different-image E2E/NFR evidence. Historical v1-v3 verification remains available. Focused mocked tests and TypeScript checks pass; **no Docker build or runtime acceptance has run for these changes**, and the worktree is now dirty at base `58c361a9`.

Warning disposition from the historical Gateway build log (`docker-compose-apps-build.log`, SHA-256 `2566cbe7…`): the preliminary Gateway restore emitted NU1902/NU1903 warnings for Azure.Identity 1.0.0, OpenTelemetry instrumentation 1.6.0, and Yarp.ReverseProxy 1.0.0, plus NU1701 for Serilog 0.1.6. These occurred before central package files were copied; the later Gateway publish step did not repeat those advisory warnings in the captured log. A forced local .NET Gateway publish after restore now resolves Azure.Identity 1.13.2, OpenTelemetry instrumentation 1.10.1/1.10.0, Yarp.ReverseProxy 2.2.0 and Serilog 4.2.0; the current NuGet vulnerability audit reported no vulnerable packages. Its `deps.json` SHA-256 and scope are in the sanitized evidence summary. This verifies current local publish resolution, **not** the historical or future Docker image: the historical published dependency manifest was not retained, so its exact package set remains **UNKNOWN**. The corrected Dockerfile restore ordering still requires a separately approved cold build and image dependency-manifest inspection. The local Gateway build also reports existing S1694 (`SharedKernel/Specifications/Specification.cs`), CA1062 (`CorrelationMiddleware.cs` and `EntraIdentityExtensions.cs`), and MA0074 (`TenantClaimConsistencyMiddleware.cs`) analyzer warnings; they are unrelated to restore ordering, remain unsuppressed and unmodified, and need their own scoped code review. The existing Openpay 1.0.25 NU1701 compatibility warning remains visible; no broad package upgrade or warning suppression was made.

**Next acceptance gate:** review the implementation diff; after separate authorization, freeze a clean candidate, cold-build once, run E2E and then NFR against those same image IDs (pass E2E `docker-image-identities-before.json` through `-ExpectedImageManifest`), and reconcile the v4 packet. Run the required payment matrix only as part of that approved candidate acceptance; never retry an ambiguous charge. Then verify applicable hosted checks on that candidate. Azure remains NOT RUN; Phase 10 is not complete.

Findings fixed while reaching this result: skipped or blocked NFR categories were counted as passed (now `incomplete`, covered by `scripts/tests/test-phase10-nfr-aggregate.ps1`); a missing rollback image blocked the drills; non-ASCII test names broke discovered-versus-TRX reconciliation (UTF-8 helper, covered by `scripts/tests/test-phase10-dotnet-inventory.ps1`); `tenantc-routing-regression` was never produced and is now derived from run evidence; the report preview wrongly flagged integration bookkeeping JSON. Changes to application/runtime behavior, payment flows, images, or evidence generation after `f2bd3587` invalidate affected evidence; CI/governance-only changes require their applicable targeted checks and do not inherit an L6 PASS.

Remaining work, in order: before Azure, satisfy the Pre-Azure LLD's same-target-SHA and image-identity evidence requirement or approve a reviewed exception; then obtain separate approval for the Azure stages. DW-023/DW-024 remain Phase 11 deferrals.

Use this board instead of the older transport-first wave notes. It matches the finalized L0-L6 architecture and keeps the next change sets aligned with the current Phase 10 objective.

| Slice | Primary outcome | Main repo areas | Evidence required |
|---|---|---|---|
| L0 | Preserve the current known-good baseline | `docs/internal/`, `TestResults/Phase10/`, workflow summaries, image tags/digests | Characterization tests, commit SHA, image digests, rollback baseline |
| L0.5 | Lock the architecture baseline and invariants | `docs/internal/phase10-preazure-lld.md`, `docs/internal/phase10-architecture-exception-manifest.md`, architecture tests, ADRs | Context map, dependency graph, route/schema/event ownership matrices, invariant enforcement |
| L1.1 | Orders becomes a real independently executable service | `XYDataLabs.OrderProcessingSystem.Orders.*`, Gateway routes, Orders tests | Readiness, authoritative order state, no hardcoded tenant/customer/order success behavior |
| L1.2 | Payments becomes a real independently executable host | `XYDataLabs.OrderProcessingSystem.Payments.*`, Orders internal payment-context contract, Gateway routes, Payments tests | Authoritative payment context, registry-driven provider resolution, idempotent callbacks/webhooks |
| L1.3 | Inventory becomes a real independently executable service | `XYDataLabs.OrderProcessingSystem.Inventory.*`, Inventory tests, downstream event handling | Module-owned reservations, idempotent duplicate handling, registry-driven tenant routing |
| L1.4 | Notifications becomes a real independently executable service | `XYDataLabs.OrderProcessingSystem.Notifications.*`, Notifications tests, downstream event handling | Module-owned deliveries, idempotent duplicate handling, registry-driven tenant routing |
| L1.5 | Gateway ownership cutover and startup migration removal | `XYDataLabs.OrderProcessingSystem.Gateway`, Compose/startup wiring, migrator, architecture tests | One owner per route, no monolith fallback in validated path, zero startup DDL |
| L2 | Durable publication and real consumers | Outbox publisher, Service Bus transport, consumer hosts, inbox/idempotency tests | One committed order -> one downstream business effect per consumer; duplicates harmless |
| L3 | Governed DLQ intake, approval, replay, and Functions proof | `XYDataLabs.OrderProcessingSystem.Functions`, operations endpoints, replay state, runbooks | Quarantine, idempotent approval, bounded replay, deployed/executable Function proof |
| L4 | Portable local identity and policy enforcement | UI auth wiring, Gateway auth, downstream auth, Keycloak config, identity tests | PKCE flow passes; `401/403` behavior correct; operator-only replay approval |
| L5 | Functional, performance, operational, security, and rollback proof | NFR harness, identity proof, test automation, diagnostics, rollback scripts/workflows | Functional/performance/operational/security categories pass independently |
| L5-R (remaining) | Unified HTML automation and coverage dashboard | Existing test runners, TRX/JSON adapters, coverage configuration, static report generator | One per-run HTML entry point reconciles all required suites, coverage, Docker gates, and explicit deferrals; see the plan below |
| L6 | Final pre-Azure acceptance | Architecture conformance gate, manual local Docker hook, applicable hosted checks, evidence packet docs; hosted workflow `99` excluded under DW-028 Option A | Architecture, operational, and deployment gates all green on one commit SHA; workflow `99` hosted parity is explicitly not claimed |

### Parked Findings — Phase 10 Remediation Backlog

The owner requested on 10 November 2026 that issues found during the AI-governance rollout be recorded here for later remediation. Parking permits unrelated governance work to continue; it does not turn a failed check into PASS, resume Phase 10 application work, or waive release gates.

| ID | Finding / owner | Status and remediation acceptance |
|---|---|---|
| P10-R1 / DW-025 | Resolved local environment-contract / targeted TenantC regression conflict. Owner: platform/test-automation maintainer. | **RESOLVED (local/mocked), 10 November**: removed the sample-filtered live payment invocation; normal execution retains the discovered-tenant matrix. `test-phase10-payment-fixture.ps1` executes real preparation/restoration assignments against mocked SQL for TenantC and arbitrary `Clinic-West-47`, with an explicit unrelated database mapping. Native argument capture proves baseline/extended matrix calls have no tenant/provider filters. Focused tests pass; unchanged environment-contract validator now reports **178 passes / 0 failures**. No seed, application routing or checker relaxation. Earlier 177/1 evidence is historical. Live Docker/provider revalidation remains unexecuted and is not certified by this correction. |
| P10-R2 / DW-026 | Governance regression process-level exit status disagrees with successful case summary. Owner: governance/tooling maintainer. | **CLOSED (hosted CI green, 10 November)**: runner now ends with an explicit `exit 0` after complete success (`a82afab`), covered by `scripts/tests/test-ai-customization-exit.ps1` (14 local cases pass: success exits 0; failed, not-tested, missing, extra, errored and aborted runs exit 1). [Run 42802711936](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42802711936) at `1000ff6` passed on Windows and Linux. Historical failure: [run 42795579199](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42795579199) at `d84cd8e` reports all 29 cases, including symlink rejection, passed on both Windows/Linux, but both jobs exit 1. Earlier `f52b06c` run 42783224695 has the same pattern. This is consistent with retained negative-test subprocess exit status; reproduce and correct the runner under separate implementation approval, retaining nonzero exits for real failures/incomplete cases. Historical local 28-pass/one-NOT-TESTED evidence remains at `TestResults/AIGovernance/regression-57932721cb3d47ef9e7cba5ca5c7e517/summary.json`. No elevation or Docker-backend use. Errors were not suppressed. Drift Scanner is a separate failing workflow (`Invoke-Expression` match in `scripts/test-phase10-payment-fixture.ps1`), not part of this finding. |
| P10-R3 / DW-027 | Controlled fresh-session behavior is not certified for Codex/Copilot. Owner: AI-governance maintainer with client operator. | **BLOCKED / NOT TESTED**: Copilot continuation attempted with only read tools, scoped paths and disabled mutation/web/MCP tools. Configured model rejected as unsupported; a same-permission per-run `auto` correction timed out without an answer and only its verified processes were stopped. One scenario attempted, two CLI launches; no semantic PASS, eleven other scenarios unexecuted. Codex safe execution controls remain unverified. Evidence: `TestResults/AIGovernance/remediation-20261110/summary.json`; original readiness packet retained. Requires a supported responsive Copilot model plus an approved controlled Codex setup, not credential extraction or weaker permissions. Batch 4 and overall governance acceptance remain incomplete; no application/Azure acceptance implied. |

### Remaining Phase 10 Work: Unified HTML Automation Report (L5-R)

**Repository-only extension checkpoint (16 November 2026):** the existing report now has an optional Azure evidence section that remains independent from the local Docker verdict. It validates dev deployment identity (six immutable application-image digests, Functions package digest and non-secret configuration identity), runner/deployment binding, required identity/payment/Functions/recovery/rollback/restoration contracts, and a gate-specific `evidence-manifest.json` by hashing the listed bounded files from disk. Regular-user identity evidence must cover every assigned-tenant × requested-tenant pair. The report contract suite is 39/39 and TypeScript compiles; report/replay/static tests are source-level checks only. Current smoke and runtime producers do not yet emit the full deployment/evidence envelope, so no Azure gate is thereby passed. Historical local L5-R acceptance below remains bound only to its recorded run/candidate; this extension does not certify a new Docker or Azure candidate.

**Prior status: local/Docker reporting accepted on `f2bd3587` under completion v3.** The 11 November closeout adds completion v4, automatic before/after image capture, image-aware reconciliation, and identity display in the offline preview. Those code changes are not runtime acceptance; the new images and v4 packets still require separately approved Docker validation. Six fixed automation suites have a versioned expected-test inventory; five foundation .NET suites and the isolated integration runner discover current candidate test identities before execution and reconcile hashed IDs/statuses against actual TRX identities. The report does not establish the full Phase 10 expected-scenario inventory by itself and does not cover Azure.

**Historical execution result (11 November 2026): L5-R accepted for the local/Docker scope on `f2bd3587` under the then-current contract.** The sealed preview remains non-certifying; acceptance is decided by the separate same-candidate reconciler. The reconciled run `phase10-docker-http-20261111-024241244` produced PASS under schema `phase10-local-acceptance-v1`. The later candidate `58c361a9` also has passing E2E/NFR reports under that older contract, but its image identity is not integrity-bound and the strict image-aware verdict is BLOCKED; see the current implementation checkpoint below. Earlier provisional runs (`phase10-docker-http-20261110-localacceptance001` and the intermediate `0a5e4602` run) remain historical. Azure reporting integration and CI artifact publication are still separate.

**Deliverable:** one automatically generated `index.html` in the existing per-run `TestResults` directory on Q:, with a supporting artifact folder that can be shared as a ZIP. The summary must open locally without a reporting service or external CDN; detailed coverage, logs, screenshots, and other approved artifacts remain linked rather than embedded into one oversized file.

Implementation plan:

1. Define a versioned result contract and expected-suite inventory. Record run ID, commit SHA, dirty-worktree state, environment, selected suites/profile, image identities when available, timestamps, duration, and artifact provenance. Never merge different runs or silently import historical passes.
2. Reuse .NET xUnit/TRX, Vitest structured results, existing TypeScript Playwright/custom-runner JSON, and acceptance packets. Normalize suite and individual-test results with counts, duration, failure details, and artifact links. Preserve raw files and exit codes. No migration to NUnit, Playwright .NET, ExtentReports, or another browser runner is required solely for reporting.
3. Enable scoped .NET coverage through the existing `coverlet.collector`; generate detailed HTML with a pinned repository-local ReportGenerator tool. Add compatible pinned Vitest coverage tooling for frontend coverage. Define measured projects, exclusions, and line/branch metrics explicitly; distinguish unit/integration measurements and report combined coverage only when correctly merged. Docker browser execution does not establish deployed-service code coverage without separate instrumentation. Missing coverage is unavailable/not collected, never a fabricated zero or PASS; agree numeric thresholds separately rather than inventing a gate.
4. Generate a static dashboard with summary counts; unit, integration, architecture, frontend, browser and safety-check sections; backend/frontend coverage; tenant/provider matrices; and build/seeding, identity, messaging/Functions, persistence, restoration, storage and available NFR/rollback evidence. Separate deterministic payments from real sandbox results and scenario coverage from code coverage. Preserve PASS, FAIL, SKIPPED, BLOCKED, DEFERRED, NOT-RUN, and interrupted/partial outcomes without weakening existing required gates or claiming DW-023/DW-024 are implemented.
5. Integrate generation into the existing Docker E2E hook's finalization path so failures and interrupted/incomplete runs still receive a truthful report when finalization can execute. Missing, duplicate, contradictory or unreadable required results, broken required artifact references, and report-generation failures must be visible and cannot turn the run green. A report-only command must render existing evidence without running tests, changing databases/settings, or starting provider charges.
6. Validate with controlled complete, failed, empty, stale, duplicate, malformed and interrupted evidence, including missing coverage, failed restoration, and HTML/path-injection fixtures. Escape report content, constrain artifact links to the run packet, and reuse artifact sanitization; never publish credentials, tokens, card/CVV values or raw sensitive payloads. Retain only policy-approved sanitized browser artifacts and avoid unnecessary large-file duplication on limited storage.
7. After separate scoped approval, run local/Docker acceptance and verify the generated dashboard against raw TRX/JSON totals and authoritative payment/provider/SQL evidence. Document exact run, report-only, open and package commands. Future GitHub Actions artifact publication/history is a separately scoped follow-up; Azure resources, workflows/deployment and directory writes remain excluded from this local implementation.

**Affected areas:** `scripts/run-phase10-foundation-tests.ps1`, `scripts/phase10-dotnet-inventory.ps1`, isolated integration runners, `scripts/run-phase10-docker-dev-e2e-hook.ps1`, automation report contracts/generation, frontend test/coverage configuration, repository-local tool configuration, focused report tests, and the existing Docker runbook. Preserve unrelated changes and existing runtime/payment behavior; no reset, pruning, database schema change, automatic commit or push is included.

**Inventory, payment, persistence and NFR reconciliation follow-up (20 November 2026):** report normalization includes all 36 checks emitted by the foundation runner, including ten operational/replay/report-support checks previously classified as unknown; a regression derives static, parameterized .NET and automation suite IDs from source declarations. Payment matrices require consistent active-tenant counts, explicit empty skipped-tenant inventory, unique matching nested run IDs, and terminal provider success (completed/captured/paid; authorization alone is not accepted). Supplemental Docker persistence now validates before/after tenant rows and file hashes, clean same-commit provenance, named SQL volume, native SQL listener, and all 13 unchanged service image IDs. Optional `--nfr-evidence <run-artifact-directory>` reports selected NFR operational/recovery evidence and rollback only when the selected categories reconcile to a fixed expected check inventory, metrics meet thresholds, source commit matches the Docker run, and image IDs match; the overall NFR profile remains PARTIAL when other categories were not selected, and replay remains separately NOT-RUN. The saved 19 November report-only projection shows the packet persistence step NOT-RUN while separately displaying supplemental persistence PASS; selected NFR operational/recovery PASS, rollback PASS, NFR overall PARTIAL; payment matrices deterministic 6/6, sandbox-positive 6/6 and sandbox-negative 6/6. The full report remains BLOCKED and does not certify the dirty/current candidate. Focused report tests and final validation results are recorded in the session handoff.

**Estimated engineering effort:** 1-2 working days for an initial dashboard from existing evidence; 4-6 working days total for structured aggregation, backend/frontend coverage, safety tests and local/Docker validation. These are estimates excluding unrelated test defects and external sandbox outages. CI publication/history would add an estimated 1-2 days if separately approved.

**Acceptance:** one existing automation invocation produces one HTML entry point with reconciled expected-suite/test counts, honest coverage scope, working sanitized detail links, and independently visible Docker gate/deferral results. Failed or incomplete required evidence cannot appear as overall PASS; report-only rendering has no runtime side effects. A saved historical run may be rendered but cannot certify newer code. Preserve the currently accepted bounded Docker baseline as historical evidence until a new same-candidate run passes.

### Pending Phase 10 TODO: Azure CI/CD Readiness And Rollout

**Status: pending; preparation and separately approved rollout only.** Docker acceptance does not certify Azure. Historical local/Azure passes do not certify the current candidate. This TODO records required work; it does not authorize workflow changes, deployment, directory writes, provider mutations, or resource creation now.

- [ ] Complete the applicable prerequisite corrections and regenerate required local L5/L6 evidence, including NFR/rollback requirements and L5-R reporting. Bind evidence to the reviewed commit and immutable image digests; do not reuse historical passes as current acceptance.
- [ ] Extend CI contract checks for bootstrap consistency, generic tenant discovery, non-overwriting seeds, OpenPay defaults, identity configuration, and provider capabilities. Preserve environment-specific settings; Docker's OpenPay default does not authorize changing existing Azure records.
- [ ] Correct Azure automation authentication: authenticated tenant discovery and browser/API sessions must support Entra rather than assuming Keycloak credentials or local-storage token conventions. Missing identity evidence must fail closed.
- [ ] Validate Entra SPA/API registrations, required delegated scope, explicit admin-role assignment, application-tenant claims, and exact redirect/logout origins. Directory changes require separate approval and appropriate permissions; never bypass MFA or tenant policy for automation.
- [ ] When the explicit generated-URL option is enabled, resolve dev origins from deployment outputs and register those exact origins. Do not hardcode ACA environment suffixes or fabricate custom domains. Preserve staging/prod URL policy.
- [ ] After Azure-dev approval, deploy additively through existing workflows: `00` only if foundation resources are missing, then `01` with cleanup disabled and immutable image references. Review workflow changes before execution; no reset/cleanup is implied.
- [ ] Run `02` runtime checks, `03` transport plus deployed Functions effects, then `04` assigned-provider sandbox acceptance. Keep required gates and their results independently visible.
- [ ] Require Key Vault/managed-identity access, SQL isolation, actual Service Bus/Functions processing, authoritative provider confirmation, and correlated Azure telemetry/SQL evidence. Reachable containers or a browser-only success cannot satisfy acceptance.
- [ ] Enable cross-provider Azure-dev mutation testing only through a separately selected and explicitly approved diagnostic/governed operation after snapshot, serialization, interrupted-recovery, and exact-restoration safeguards pass. Keep it outside standard assigned-provider Action `04`, disabled for staging/prod by default, and aligned with Phase 11 P11-W5 provider-reassignment policy. A restoration failure stops further mutations and blocks acceptance.

**Deployment readiness gate:** prerequisites, same-commit local gates, reviewed workflow changes, and explicit Azure-dev approval are complete. Optional Razorpay S2S and OpenPay visible-challenge capability gaps remain separately BLOCKED/unverified; they neither certify Azure nor prevent an otherwise fully evidenced, explicitly bounded assigned-provider baseline. Missing required evidence remains FAIL/NOT-RUN, not PASS. Existing production approval and promotion gates are unchanged.

#### Candidate-To-Azure Parity TODOs For The November 10 Changes

The identity/payment/Docker implementation in `6c467a5` and dropdown styling/Phase 11 plan in `b3f7ed5` are local implementation evidence, not Azure acceptance. Re-evaluate the final reviewed candidate SHA after any further changes. The following are pending implementation/verification items, not claims that the current workflows satisfy them:

- [ ] **Explicit local-to-cloud service/storage mapping:** reuse the repository application Dockerfiles for UI, gateway, Orders, Payments, Inventory and Notifications, but do not deploy local Compose unchanged. Map local SQL Server to Azure SQL, Service Bus emulator to Azure Service Bus, Azurite to Azure Storage, Keycloak to Entra, and local Redis to the approved Azure cache contract. Record the actual Functions deployment model: current IaC defines an Azure Function App, so validate its immutable executable package/deployment artifact and real invocation rather than assuming the local Functions container image is deployed there. Verify runtime endpoints and physical SQL identities resolve only to approved cloud resources; reject localhost, local emulator and Windows drive paths. The local `xy-phase10_phase10-sql-data` volume inside `G:\DockerStorage\DockerDesktopWSL\disk\docker_data.vhdx` remains local: application images contain neither that volume nor its databases. Initialize/validate cloud databases through governed migrations and approved non-overwriting bootstrap, not by uploading the VHDX or copying local trial data. Any local-to-Azure data transfer requires a separate reviewed and approved migration. The cloud rollout must leave local Docker data untouched.

- [x] **Runnable CI without mandatory PRs:** `.github/workflows/ci.yml` supports direct pushes to `dev`, `staging`, and `main`, manual dispatch, and PR validation. Mandatory PRs and auto-deployment are not required. Hosted results remain bound to their exact commit; see the dated Checkpoint A evidence above.
- [x] **Immutable build and deployment handoff — implementation and offline contract validation complete; Azure acceptance pending:** the release manifest pins six digest-qualified ACR references and the Functions package to one source SHA. Deployment now separates this immutable artifact source SHA from the deployment workflow SHA, requires the source revision to be an ancestor of the target branch revision, and verifies applicable hosted checks on both exact revisions. The preflight summary lists required and path-filtered not-applicable workflow checks with reasons; missing/failed/cancelled required exact-SHA runs block. Release branch policy allows dev→dev, dev/staging→staging, and dev/staging/main→prod. The target workflow checks out its own revision; it does not rebuild or relabel the artifact. Both source and target hosted CI evidence packets are downloaded and reconciled against their respective exact SHAs. The selected Functions design adds a dedicated environment-scoped StorageV2 account and user-assigned identity with account-scoped `Storage Blob Data Owner`, disables shared-key/public-blob access and includes a read-only `roleAssignments/write` preflight. Deploy, runtime, transport and payment acceptance workflows share a per-environment `queue: max`, non-cancelling Actions concurrency lease (up to 100 pending runs); overflow is cancelled before execution and cannot be accepted as evidence. Manual portal/CLI changes remain outside this Actions-level lock. No ACR publication, Azure provisioning, `what-if` or deployment has occurred. Effective permissions, quotas and SKU cost remain unverified. **Remaining release-policy gap:** staging deployment acceptance is not yet a machine-verified promotion input; require its independent review before production. Reject mixed-candidate services and never substitute local Docker images or Docker-only infrastructure images for Azure resources.

### Repository-only Checkpoint B follow-up — 12 November 2026

- Offline contract coverage was extended for arbitrary shared/dedicated tenant discovery through the authenticated runtime API and for repeat initialization preserving tenant/provider operator state. The CI workflow now runs the synthetic tenant-catalog suite. Existing tests cover environment mapping, generated/local endpoint rejection, Entra fail-closed validation, sandbox adapter enforcement, incomplete/contradictory evidence rejection, immutable image/package identity, release-run ownership and dry-run routing.
- Local verification on dirty `dev` `42513d666fbc84724e121c090c340c6b3fcd4a62`: 38 release/identity/static-preflight tests passed; tenant-catalog 4/4; Application.Tests 80/80 including InMemory bootstrap-preservation; Docker safety 45/45; environment-contract 185/185; hosted-CI contract 9/9; payment/evidence/report suites 43/43; Bicep compilation, AI customization validation, documentation-link validation and `git diff --check` passed. Release solution build succeeded with 174 warnings and no errors, including the existing OpenPay `NU1701` compatibility warning; warnings were not changed here.
- **Updated 12 November 2026:** the B2 offline implementation is complete and was committed on `0b9e97c56905f04e8234703a89d375a220af847d`; later documentation-only commits were synced across `dev`, `staging`, and `main`. The local contract/test totals above passed, and exact-SHA hosted CI, AI-customization and Drift Scanner passed on the subsequent branch tips. This establishes offline contract readiness only. No Docker lifecycle, SQL connection, provider transaction, ACR publication, Azure login/inspection, live `what-if`, provisioning, deployment or directory write occurred. Checkpoint C/D live Azure preflight and acceptance remain NOT-RUN and separately approval-gated.
- [ ] **Public runtime UI configuration and live identity parity:** validate the deployed UI's allowlisted runtime identity configuration, correct API proxy target and environment without exposing backend secrets. Prove the same UI image loads environment-specific settings, serves the new dropdown CSS, and supports direct SPA routes including `/payments/new`, `/auth/callback`, and `/signed-out`. Check actual Entra SPA/API registrations and role/claim assignments through authorized read-only verification: `prepare-entra-deployment.mjs` validates supplied settings/URI lists, not live directory state. Test admin switching, regular-user tenant filtering and forged-header denial, token expiry, same-browser logout/login and cross-tab logout in Azure; retain the production selector's disabled default.
- [ ] **Origin bootstrap and payment redirects:** define how a first generated ACA origin becomes known before identity-enabled UI activation. Discover it from resource outputs, obtain approval for exact registration/configuration changes, then activate and validate; never work around this ordering by disabling authentication or inventing a domain. Verify UI-to-gateway proxying, ingress/forwarded HTTPS handling, any required CORS allowlist, browser popup/return behavior, OpenPay redirect and Razorpay callback/signature paths against the deployed public origins. Reject localhost or stale callback values. Identity redirect URIs and provider redirect/webhook URLs are distinct contracts.
- [ ] **Cloud database and provider baseline:** keep `tenant-bootstrap.local.json` Docker-only until an explicitly reviewed cloud bootstrap contract is approved; do not feed local database names, passwords or test accounts into Azure. Use the existing governed migrator with a captured pre-change schema/data/provider snapshot, explicit shared/dedicated mappings and least-privilege migration/runtime access under the current architecture. Verify no startup DDL or silent dedicated-to-shared fallback. Existing IDs, routes, flags, credentials, inactive/additional tenants survive repeated initialization. If Azure-dev OpenPay 3DS-off is selected, apply a separately approved previewed/snapshotted change only to intended business-database flags; do not overwrite Azure settings through Docker seeds or the legacy switch script. Provider switching must first satisfy the P11-W5 legacy-tool safety correction or use an independently approved safe path.
- [ ] **Real sandbox and end-to-end evidence:** assert effective deployed adapter mode, sandbox account metadata, provider-specific currency and credential agreement without printing values. Reject deterministic adapters/IDs, local emulator endpoints and live payment credentials in Azure-dev acceptance. Exercise customer/order UI entry, authoritative provider retrieval, validated callback, one successful payment and Paid-order projection; test paid-order charge prevention and distinguish fulfillment from payment. Run a telemetry canary before charges and use bounded ingestion/confirmation waits; never resubmit an ambiguous charge. Assigned-provider Action `04` must not mutate tenant routes. Preserve optional capability and DW-023/DW-024 exclusions explicitly.
- [ ] **Release safety and rollback:** serialize deployments per environment and prevent migration/provider mutations from overlapping acceptance. Handle cancellation without abandoning owned temporary state; temporary SQL firewall access and diagnostic/replay settings require verified restoration. Verify correct subscription/tenant/environment, required scoped permissions, quotas and ACR pull/Key Vault/network access before mutation; do not elevate permissions or convert Phase 12 SQL identity/network deferrals implicitly. Add explicit startup/readiness/liveness behavior where appropriate, verify candidate revision health and actual served traffic, retain the previous known-good image/configuration references, and rehearse rollback. Code rollback must not imply destructive SQL rollback; schema compatibility and any data recovery require an explicit reviewed strategy.
- [ ] **Azure acceptance packet and operational handoff:** write sanitized results even on failure with independent deployment, identity, migration/seed preservation, payments, transport/Functions, telemetry, restoration and rollback outcomes. Publish the L5-R HTML entry point and raw evidence as controlled run artifacts once Azure reporting integration is separately approved; use the same result contract, not a second definition of PASS. Missing required artifacts or partial verification block promotion. Document exact workflow selections, approved environment settings, warning disposition, bounded retry limits, recovery steps and current cost/resource scope. No new billable monitoring/reporting service is required by this plan.

These checks extend the pending Azure TODOs; they do not move P11-W0 payment UX into Phase 10, waive architecture/NFR requirements, or authorize Azure implementation today. Follow the established local/CI-first rollout, then separately approved Azure dev, staging, and production gates. Platform-wide security/private networking and other formal Phase 12 deferrals retain their existing ownership.

Implementation references: [ACA health probes](https://learn.microsoft.com/en-us/azure/container-apps/health-probes) and [revision lifecycle](https://learn.microsoft.com/en-us/azure/container-apps/revisions). The selected revision mode determines when traffic shifts; do not claim a multi-revision rollback strategy unless it is actually configured and tested.

## Slice-Oriented File Map

Use these file groups when choosing the next concrete implementation slice.

| Slice | Likely file groups |
|---|---|
| L0 / L0.5 | `docs/internal/phase10-preazure-lld.md`, `docs/internal/phase10-architecture-exception-manifest.md`, `docs/internal/AZURE-PROGRESS-EVALUATION.md`, `ARCHITECTURE-EVOLUTION.md`, `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/` |
| L1.1 Orders | `XYDataLabs.OrderProcessingSystem.Orders.API/`, `XYDataLabs.OrderProcessingSystem.Orders.Features/`, `XYDataLabs.OrderProcessingSystem.Orders.Infrastructure/`, `tests/XYDataLabs.OrderProcessingSystem.Application.Tests/Handlers/`, `tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/` |
| L1.2 Payments | `XYDataLabs.OrderProcessingSystem.Payments.API/`, `XYDataLabs.OrderProcessingSystem.Payments.Features/`, `XYDataLabs.OrderProcessingSystem.Payments.Infrastructure/`, `XYDataLabs.OrderProcessingSystem.Orders.API/`, Gateway routes, payment automation/tests |
| L1.3 Inventory | `XYDataLabs.OrderProcessingSystem.Inventory.API/`, `XYDataLabs.OrderProcessingSystem.Inventory.Features/`, `XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure/`, inventory consumer tests |
| L1.4 Notifications | `XYDataLabs.OrderProcessingSystem.Notifications.API/`, `XYDataLabs.OrderProcessingSystem.Notifications.Features/`, `XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure/`, notification consumer tests |
| L1.5 Gateway + migrator | `XYDataLabs.OrderProcessingSystem.Gateway/`, migrator/startup/Compose scripts, host projects, route topology tests |
| L2 Messaging | Outbox publisher, envelope/contracts/mappers, transport adapters, consumer inbox/idempotency, integration tests |
| L3 DLQ + Functions | `XYDataLabs.OrderProcessingSystem.Functions/`, operations schema/state, replay approval endpoints, replay runbooks/tests |
| L4 Identity | UI auth client config, Gateway auth, service auth/policies, Keycloak assets/config, identity integration tests |
| L5 / L6 Proof | `scripts/`, `TestResults/Phase10/`, workflow/result-packet docs, Playwright/integration/NFR harnesses |

## Implementation Order From Here

Take the remaining work in this order unless a defect forces a narrower hotfix:

1. Clear any remaining L0.5 architecture leaks and temporary exceptions.
2. Finish L1 service ownership cutovers in service order:
   - Orders
   - Payments
   - Inventory
   - Notifications
   - Gateway/migrator
3. Finish L2 durable messaging with real consumers and exact inbox/idempotency rules.
4. Finish L3 DLQ, approval, replay, and Functions executable proof.
5. Finish L4 Keycloak-based local identity proof with the portable JWT/OIDC model.
6. Re-run L5 functional, performance, operational, security, and rollback evidence on the new architecture.
   - Complete L5-R unified HTML reporting and coverage collection; validate the dashboard against the raw results for that run before local reporting closeout.
7. Close L6 only after architecture conformance, manual local Docker acceptance, and all applicable hosted checks are verified on the same commit SHA. The local hook is the accepted Docker check; hosted workflow `99` is excluded under DW-028 Option A and must not be labeled hosted PASS.

Do not invert that order by using Azure deployment proof as a substitute for unfinished local architecture work.

## SharedContracts Decision

`SharedContracts` remains deferred.

Only introduce it if:

- the same integration-event DTO or transport contract is genuinely duplicated across multiple services, and
- service-local contracts can no longer remain versioned independently without drift.

Do not introduce `SharedContracts` as a convenience abstraction during L1-L4.

## Documentation And Governance Alignment

Keep these supporting docs aligned with the finalized L0-L6 plan:

| Document | Required alignment |
|---|---|
| `docs/internal/phase9-remaining-roadmap.md` | Point Phase 10 readers to this checklist and the pre-Azure LLD rather than duplicating the plan |
| `docs/internal/README.md` | Keep this checklist and the pre-Azure LLD discoverable from the internal index |
| `docs/internal/AZURE-PROGRESS-EVALUATION.md` | Track Azure proof as downstream of successful L0-L6 completion, not as a replacement for it |
| `docs/internal/DEFERRED-WORK-LOG.md` | Keep `SharedContracts`, SQL managed identity, private ingress/networking, and other rephased work explicitly deferred |
| `docs/runbooks/servicebus-dlq-replay.md` | Reflect the governed quarantine/approval/replay model |
| `docs/runbooks/phase10-azure-smoke.md` | Reflect Azure smoke as the post-L6 phase, not the primary implementation loop |

## Next Change-Set Deliverables

### 15 November tenant/provider parity repair — implementation and execution checkpoint

This repair changed automation, not tenant seeds or payment business rules. The preserving Docker run and six-case Azure-dev operator matrix passed on clean automation candidate `b434672aacff9284a4646f0a75fca2ce0374625f`, with matching client source-content identities. Azure deployed application/image identity is separately recorded; it is not implied by the automation revision. See the completion record below for exact scope and limitations.

- [x] Local implementation: shared positive scenario/currency/UI-entry contract; fail-closed versioned verifier/check inventory; explicit dry-run status and separate pointers; order/submission/provider/verification/restoration case ledger; source-bound Azure verification-only reconciliation; continuation only after confirmed journey, exact restoration and authenticated safety recheck; positive charge/Paid-order/terms/UI callback requirements.
- [x] Controlled tests: malformed/missing check inventory, interrupted submission intent, changed identity, failed restoration, cross-tenant/amount mismatch, read-only recovery without resubmission, and dry-run pointer preservation. Foundation runner/report inventories include the previously omitted Razorpay contact suite and the new verification/recovery suites; individual outcomes must reconcile.
- [x] Follow-up review: remove the physical verifier's 3DS-dependent callback waiver as well as its UI-derived fallback waiver; require positive callback flags in the shared report contract and tenant-scoped event matching in both verifiers. Candidate `9d18c41c` startup was stopped before E2E/charges; preserve its partial report, not PASS. New strict callback regressions cover this gap before a fresh run.
- [x] Hosted CI `43722972805` exposed a frontend test race: the mode label can render before OpenPay device setup. The test now waits for device readiness and the actual mocked SDK call; application behavior is unchanged. A new candidate must rerun hosted checks; the failed run remains failed.
- [x] Read-only environment checks: Docker seed/provider contract passes for A/B/C × both providers; G: storage/log rotation passes. Existing Azure TenantA Razorpay callback proof now requires/found one callback, and OpenPay passes Paid-order/unique charge/terms/callback verification. These are follow-up checks, not a fresh full matrix.
- [x] Freeze source-content identity; rebuild/start Docker without reset, preserve volumes/provider settings and capture actual images.
- [x] Complete fresh deterministic and sandbox Docker baseline cases for A/B/C × both providers and selected negative/identity/operational gates; preserve failures and prove restoration.
- [x] Complete six fresh Azure-dev UI/provider positives with one normal Entra login, source/deployment/settings identity, SQL/provider/UI evidence and restoration.
- [x] Produce/reconcile the Docker packet and HTML plus Azure matrix raw results; do not equate this bounded acceptance with full Phase 10 closure.
- [ ] Complete broader current-candidate Azure negative/identity/transport/Functions and NFR/rollback gates separately; missing evidence remains BLOCKED/NOT RUN. The replay proof must call `POST /api/v1/admin/dlq/{quarantineId}/approve` under the explicit `phase10-operator` application role; `platform-admin` payment access is not equivalent. Never synthesize approval by direct SQL updates/inserts. Workflow `03`'s malformed/poison quarantine is not replayable by design; use a separate unique valid transient fixture, correlate exact tenant/message/quarantine/request/correlation IDs, and prove zero duplicate downstream effects. Keep broker DLQ-forwarding and replay-gate evidence distinct.

No reset, pruning, production/staging operation or directory/RBAC change is included in this repair execution. The owner separately authorized committing and pushing the reviewed automation fixes to `dev` after checks pass, so Docker can test a clean candidate. Ambiguous charges are never retried. DW-023/DW-024 and other approved capability/product exclusions remain explicit—not PASS.

#### Completion record — 16 November

- Docker `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261115-194923198/`: run summary, acceptance packet, completion JSON and offline HTML PASS. Backend 374, frontend 61, automation 62 cases/12 suites and isolated integration 75 passed. Six deterministic positives, six sandbox positives and six Razorpay decline/dismissal cases passed across A/B/C and both providers. Identity, messaging/Functions, restart persistence and all 18 fixture restorations passed; run-owned integration databases cleaned, application metadata unchanged. Order continuation remains deferred.
- Azure parent `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-15T15-14-59-368Z/summary.json`: six fresh sandbox positives, 66/66 required checks, one normal Entra login/MFA and final sign-out. Provider confirmation, callback proof, matching SQL terms, unique successful charge and Paid projection PASS. Final read-only reconciliation confirmed unchanged deployment/settings and six verified/restored receipts. This is not unattended hosted workflow 04 acceptance.
- Docker packet SHA256: `324EA5B57F2EE6265208F5CDFCCA230D37FA79651AD817B5529545E92B331A87`. Azure parent summary SHA256: `2326C3879F27A170CD0C3CB03A67FD9086F752179A2E1E8D2E66286CF6FD93D2`. Preserve original failed/partial reports.
- Hosted build/contracts `43723705879` and AI/docs/prompts/drift checks passed on `b434672a`; ADR skipped by opt-in, not PASS. Final Docker storage: G: 437.5 GiB free, SQL allocation 0.28 GiB, all 13 containers at `10m × 3`, zero mismatches. Build/package warnings and coverage source-line branch limitation remain.
- Broader current-candidate Azure transport/Functions, regular-user isolation/expiry, negatives/recovery, NFR/rollback and unified reporting remain open. Historical `494ab4fd` NFR/rollback does not certify changed images. Six payment positives do not close Phase 10.
- Approved Azure testing window expired 15 November 22:30 IST. No new runtime mutations or cleanup are included. Separately approved cost-helper repair handles Windows JSON transport and actual CLI response shapes. Read-only snapshot `TestResults/AzureCost/phase10-dev-20261116-cost-snapshot.json` at 16 November 00:20 IST records approximately INR 586.07 subscription month-to-date (lagging, not per-run cost); three SQL size limits remain unknown. Later cost/documentation revisions do not inherit exact-revision payment acceptance.

#### NFR finalization hardening — 16 November

Post-foundation review found and corrected a parent-runner gap: failed child replay execution could proceed into rollback without proven restoration. The parent now requires fresh, typed successful restoration evidence; missing/malformed/failed evidence blocks later mutations. Focused tests execute the actual parent command block with a mocked child, including a failed replay with independently successful restoration. Fresh foundation `TestResults/Phase10/foundation-local-20261116-replayhardening004/summary.json` passed all 29 steps; its report-only preview remains BLOCKED. Secret-hygiene scan and 211 environment-contract checks passed. Commit/push and live runtime acceptance remain pending approval.

Latest local follow-up: `TestResults/Phase10/foundation-local-20261116-replayhardening003/summary.json` passed 29 steps; report-only `index.html` correctly remains BLOCKED. Eleven replay CLI/finalization tests, six local approval tests, 39 report tests and 44 combined static Azure/hosted-contract tests passed. Actual drill function tests mock process-tree termination success/failure, consumer restoration/readiness and the mutation-stop gate. These are not live process-tree, Docker, SQL or Azure proof. Final scoped diff review and clean-candidate hosted/runtime gates remain pending.

- The consumer-outage drill now records execution and restoration independently; it terminates the probe process tree, restarts both consumers, checks both readiness endpoints, verifies exact prior process-environment values, and saves sanitized final evidence. A failed restoration blocks later rollback and identity actions.
- Regression contract includes cancellation evidence and is registered in the foundation runner. `TestResults/Phase10/foundation-local-20261116-nfrdrillfix002/summary.json` passed all 27 steps. Report-only rendering produced offline `index.html` with **BLOCKED**, correctly refusing to infer acceptance from foundation tests alone.
- This is mock/foundation evidence only: live outage drill and current-image NFR/rollback have not run; historical NFR results remain bound to earlier images.

#### Current local P0 follow-up — 16 November

- Read-only hosted status on clean base `4302823e6d2495a30adf3289fbb3ef1ae2d300cc`: CI `43903804899`, docs `43903804795`, AI customization `43903804759`, drift `43903804779`, and prompts `43903804968` succeeded; ADR `43903804833` was skipped. These runs do not certify the dirty follow-up changes.

- Follow-up after the v5 checkpoint: latest evidence is `TestResults/Phase10/local-followup-20261116-p0close-v6/` using `TestResults/Phase10/foundation-local-followup-20261116-final03/summary.json` (32/32). The report suites passed 10/10 canonical and 6/6 supplemental; explicit failed evidence now remains FAIL. The report still returns INCOMPLETE: dirty candidate, required current NFR categories not run, Azure not run.

- Latest validated supplement is `TestResults/Phase10/local-followup-20261116-p0close-v5/`, based on fresh foundation `TestResults/Phase10/foundation-local-followup-20261116-final02/summary.json`. This supersedes the earlier v4 pointer below. The DW-023 failure-masking correction passed its regressions; 13/13 images match, but the report remains INCOMPLETE.

- Candidate basis: clean `4302823e6d2495a30adf3289fbb3ef1ae2d300cc` plus the currently uncommitted, scoped NFR/Functions changes. All following evidence is **dirty-worktree evidence**, not a clean-candidate or hosted-CI result.
- P0.1 Functions approval lifecycle: `tools/Phase10.NfrProbe/ReplayApprovalLifecycle.cs` now requires `not-started → submission-intended → approved → processing-confirmed`; contradictory terminal states cannot report success. The lifecycle tests passed 9/9. Fresh local proof `TestResults/Phase10/lifecycle-fresh-2f6b73ffd6034c72860a1ace059a17b8/functions-proof.json` passed with `approvalStatus=processing-confirmed`, `approvalOutcome=approved`, and `approvalReconciliationRequired=false`. Replay settings restoration passed.
- P0.2 operational proof: `TestResults/Phase10/operational-only-db230e2d59794a4ab6b91a87670ccf43/nfr/operational-100-message-burst.json` passed 100/100 messages, inbox entries and effects for both consumers; P95 3.89915 seconds. `consumer-outage-drill.json` passed 100/100 effects per consumer, zero loss/duplicates, P95 8.63285 seconds, recovery 29.175 seconds, readiness and environment restoration.
- P0.3 rollback: `rollback-evidence.json` passed. The verified previous Inventory image `sha256:519a4db9888d00b353e4be0b9b2420ad7b49e740e39876c2c22973dfda10adb9` was exercised; the exact current image `sha256:5575d9817a36829055999d7e7e364379c4c7d8f9f8b7d2b4d945196f60abde11` was restored and health-checked. No database rollback was performed.
- Read-only image audit `TestResults/Phase10/current-image-audit-p0-20261116-reportfinal01/docker-image-identities-after.json`: all 13 current service image IDs exactly match the November 15 Docker E2E after-manifest; mismatch count 0. This supports reuse of that E2E's payment evidence for the same binaries without rerunning charges, but does not bind dirty source/test changes to a clean candidate.
- The November 11 full NFR run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261111-234505649/` differs from current images on 8/13 services. Its all-category PASS is historical and cannot be combined as current-image NFR acceptance. Current operational-only proof closes operational/recovery only.
- The operational-only parent `nfr/summary.json` is correctly **incomplete**: operational and recovery passed; functional, performance, tenant, payments and security were intentionally `not-run`. Do not call this full NFR acceptance.
- Added `automation/src/report/phase10-local-followup.ts` and its CLI as a supplemental, hash-bound report; the strict single-clean-candidate acceptance verifier remains unchanged. It explicitly separates image-binary match from source-candidate identity and reports incomplete NFR categories instead of promoting them.
- Fresh foundation run `TestResults/Phase10/foundation-local-followup-20261116-final01/summary.json` passed 32/32 steps, including Domain, Application, API, Gateway and Architecture tests plus frontend/automation checks. The four report-specific tests and automation TypeScript check also passed. The existing Cobertura branch-total warning remains; XML is authoritative.
- Latest supplemental report `TestResults/Phase10/local-followup-20261116-p0close-v4/` uses that fresh foundation result and records each historical Docker packet step, current Functions/operational/rollback checks, evidence hashes and the 13/13 image match. It remains **INCOMPLETE**: current source is dirty, functional/performance/tenant/payment/security NFR categories are not run in the current NFR report, and Azure acceptance is outside this supplement. Preserve prior sealed acceptance/NFR files unchanged.
- P0.4 remains open: obtain a clean reviewed candidate and applicable exact-commit hosted checks, then complete any required current-image NFR categories and final acceptance reconciliation. No payment was repeated. No commit/push, reset, Azure action or cleanup was performed in this follow-up.
- Azure remains a separate open gate. The six Azure sandbox positives recorded on the November 15 run remain bound to that run/deployment; broader current-candidate identity, transport/Functions, NFR/rollback and evidence reconciliation are still open. The Azure mutation window expired November 15 at 22:30 IST; renew scoped approval before any Azure mutation.
- DW-023/DW-024 and the previously documented uncertain payment history remain protected. Do not infer fulfillment, installment or unresolved-payment recovery acceptance from these P0 runs.

The next useful Phase 10 change sets should produce:

- one completed architecture cleanup or service-ownership slice at a time
- updated architecture tests or integration tests that prove the slice
- updated evidence pointers and exception manifest entries where applicable
- no new undocumented temporary dependency or fallback path

### Supplemental non-Azure reconciliation — 18 November 2026

- Reconciler: `TestResults/Phase10/local-followup-20261118-022000/local-followup.json` (`INCOMPLETE`); offline summary: `TestResults/Phase10/local-followup-20261118-022000/index.html`. It binds base commit `9fa6160c18616003ad6d6aaa14753183d20c4c71` to a dirty-worktree content hash; it does not claim a clean candidate.
- Current no-payment Docker E2E: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261118-014011896/`. Selected foundations (36/36), isolated integration (75/75), smoke, identity/routing, all-active-tenant currency/order-entry, messaging/Functions, provider restoration and Docker Desktop restart persistence passed. Payment suite was explicitly `none`; no payment was submitted. The run is `partial` by design, not a full payment acceptance.
- Fresh sandbox payment baseline after commit `0e46047491e9e664e4d5a1b968ab59d7deda1581`: `TestResults/PaymentMatrix/phase10-postcommit-20261118/payment-acceptance-sandbox-1794975083135/`. All six required positives passed (TenantA/B/C × Razorpay/OpenPay); each used a fresh order, confirmed the provider result, correlated the payment to SQL and UI callback evidence, passed all 9 verification checks, and restored fixture state. Razorpay used hosted checkout (INR 200); OpenPay used direct card form (MXN 200). OpenPay was configured with 3DS off and did not present a challenge; Razorpay hosted checkout presented its sandbox test-bank challenge. The post-run read-only seed contract passed for all three tenants and both providers, confirming routes/settings and local credential-reference matches were restored. No decline/cancel cases, Razorpay S2S, visible OpenPay challenge, or order-continuation recovery were exercised.
- The payment runner's summary does not embed source revision or a per-run image manifest. During this session, the worktree was clean at `0e46047491e9e664e4d5a1b968ab59d7deda1581`; the 13 live image IDs were also compared after the run and matched the no-payment E2E image manifest 13/13. Preserve this as supplemental evidence, not as a substitute for the sealed same-run provenance required for final L5-R reconciliation.
- Current-source no-charge NFR run: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-100145315/nfr/summary.json`. On commit `0e46047491e9e664e4d5a1b968ab59d7deda1581` (worktree dirty only from the three documentation/handoff edits recorded above), functional (48 integration cases), tenant isolation (40), provider integration (6 non-transactional cases), API authorization (61 tests), and Keycloak browser identity passed; payment settings were verified unchanged. The run is correctly `incomplete`: dynamic payment matrix was explicitly skipped; performance was not selected; operational/recovery were not selected. Existing `NU1701` OpenPay package compatibility and `CA2000` test analyzer warnings were emitted; neither was suppressed or treated as a test failure.
- Current-source operational/recovery run: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-101125950/`. Operational-only profile passed the 100-message burst (100/100 inbox/effects; P95 2.226 s), consumer outage/recovery (100/100, zero lost/duplicate effects, P95 9.257 s, recovery 29.476 s), and provenance-checked Inventory rollback/restoration. All 13 before/after image IDs matched, the source content hash stayed stable, and the exact current Inventory image was restored. This report is also correctly `incomplete` because only operational/recovery were selected; functional/performance/tenant/payment/security are not claimed by it.
- Current-image operational/recovery proof: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-013113758/`; targeted no-charge functional/tenant/security/provider-integration proof: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-013233653/`. The operational run passed the 100-message burst and consumer outage/recovery (zero lost/duplicate effects; P95 4.834 s and recovery 29.936 s), Functions replay/restoration, and provenance-verified Inventory rollback followed by exact current-image restoration. The targeted no-charge run passed its selected functional, tenant, provider-integration and identity/security categories; dynamic payment matrix and unselected operational categories were not run in that profile.
- Historical full Docker payment evidence from `TestResults/Playwright/phase10-docker-http/phase10-preazure-20261117-full-baseline` remains bound to its clean base commit. The 18 November supplemental payment run now provides fresh positive sandbox evidence, but the earlier unified reconciliation remains `INCOMPLETE` and is not retroactively changed. DW-023/DW-024 order continuation/recovery remain DEFERRED; Azure acceptance is NOT-RUN.
- Current read-only storage manifest reports Docker on `G:\DockerStorage\DockerDesktopWSL`, 469,915,316,224 bytes free (about 437.7 GiB), application SQL allocation about 0.28 GiB, all 13 services at `10m × 3`, and zero rotation mismatches. No reset, prune, VHDX compaction or F: recovery was performed; the retained F: copy was previously deleted.
- Fresh focused follow-up tests after reporting changes: no-payment finalization, operational-only contract, local-followup report tests (10/10), TypeScript typecheck and NFR probe build passed. These are implementation checks, not a substitute for the report's blocked clean-candidate gate.
- Overall disposition: current-source functional/tenant/payment-integration/security and operational/recovery/rollback checks now have separate passing reports, and the six-case sandbox-positive matrix passed. Phase 10 is **not closed**: performance was not selected, reports remain separately scoped/incomplete, and no unified L5-R packet reconciles the current matrix and NFR evidence with a single sealed candidate/image set. DW-023/DW-024 remain deferred; Azure remains excluded. Do not repeat successful sandbox charges solely to refresh reporting; close the provenance/reporting gap and run only genuinely missing gates.

### Current local acceptance follow-up — 18 November 2026 (late run)

- Supplemental HTML/JSON reconciliation: `TestResults/Phase10/local-followup-20261118-e2e-payment-reconciliation003/`. Verdict **FAIL**, intentionally preserving the failed parent Docker run; it is not a Phase 10 PASS. The parent run `phase10-docker-http-20261118-101626474` passed foundations, smoke, integration, OpenPay baseline and settings restoration, but its customer-directory browser test timed out. The separate identity retry passed admin switching A/B/C, regular-user isolation (403 cross-tenant denials), and same-browser logout. The original failure packet/log remains unchanged.
- The reconciliation displays separate payment matrices without overriding the parent result: six deterministic positives PASS; six real sandbox positives PASS across TenantA/B/C × Razorpay/OpenPay; six Razorpay decline/cancellation cases PASS. Positives used fresh persisted orders, provider verification, SQL verification and fixture restoration. Do not repeat these charges just to refresh the report. OpenPay challenge-negative behavior remains BLOCKED; payment summaries do not carry per-run source/image manifests, so strict payment provenance is BLOCKED.
- Current no-charge NFR run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-233404151/` passed functional integration, performance, tenant isolation, non-transactional provider integration and security/identity. The 100-message performance burst had 100/100 inbox entries/effects and P95 2.168 s (<30 s). Overall `incomplete` is intentional because dynamic payments and operational/recovery were not selected.
- Current operational/recovery run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-232818927/` passed its 100-message burst, consumer outage/recovery (100/100 effects and inbox entries, zero loss/duplicates, P95 6.710 s, recovery 29.309 s), retained-image Inventory rollback and exact current-image restoration. Its profile remains `incomplete` because only operational/recovery was selected; its 13 service image binaries match the no-charge NFR run.
- Persistence survived Docker Desktop restart on G: with known tenant/order rows and unchanged SQL volume/image binaries. The supplemental reconciliation reports outcome PASS separately; same-source-candidate binding remains BLOCKED. All 13 project containers are currently running; no reset, global prune or VHDX compaction was performed.
- Targeted validation passed: local-followup report suite (13/13), TypeScript compile, NFR-selection tests, operational-only contract tests and `git diff --check`. Existing NU1701 OpenPay compatibility and CA2000 analyzer warnings remain unsuppressed.
- Remaining non-Azure work: reconcile the dirty worktree to one reviewed clean candidate; bind payment evidence to source/image identity without repeating successful/ambiguous charges unnecessarily; close the complete-run customer-directory timeout with a successful full run or reviewed gate disposition; and produce an accepted L5-R packet. DW-023/DW-024 remain deferred; Azure is NOT-RUN.

### Current local acceptance follow-up — 19 November 2026, payment and NFR reconciliation

- Fresh Docker E2E `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-021441154/`: deterministic 6/6 and real sandbox 6/6 positive journeys passed across TenantA/B/C × Razorpay/OpenPay; Razorpay failure/cancellation 6/6 passed. Provider confirmation, physical order/payment correlation, Paid projection and fixture restoration passed. Do not repeat successful charges to refresh reporting.
- No-charge current-image NFR `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-030557315/`: functional, performance, tenant, provider integration and security/identity checks passed. The 100-message burst passed with 100/100 inbox/effects and 2.379 s P95. Exact provider settings before/after were unchanged. Its overall profile is correctly incomplete because the dynamic payment matrix was explicitly skipped.
- Current-image operational-only NFR `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-031348421/`: 100-message burst passed (2.065 s P95); 100-message outage/backlog recovery passed (100/100 inbox/effects, 7.987 s P95, 28.597 s recovery, zero loss/duplicate effects, restoration verified); retained Inventory image rollback and exact current-image restore passed. Its profile is correctly incomplete because it selects only operational/recovery.
- Persistence after Docker Desktop restart on G: passed in `TestResults/DockerStorage/persistence-20261119-after-payment/`; known paid tenant orders, SQL volume and image identities persisted. Refreshed supplemental report: `TestResults/Phase10/local-followup-20261119-current-candidate005/`. Payment compatibility, current NFR, operations/outage, rollback, persistence, Functions/replay and evidence-integrity gates pass.
- The supplemental verdict remains **INCOMPLETE**, not full Phase 10 PASS: worktree is dirty; OpenPay challenge-negative capability is blocked/unverified; order continuation remains DW-023 deferred; Azure is NOT-RUN. The sealed E2E packet itself marks its persistence step NOT-RUN, while separate current persistence evidence passes and is candidate/image bound.
- The report records dirty content hash `0cb6fec98f808ac99374611cf7e531ec8731581f1582ec01f61c9de16be9c205`; the final checklist/handoff edits followed report generation, so that hash is not the current worktree identity. Evidence revision remains `UNKNOWN`; do not claim exact current-worktree binding.
- Validation after these runs: report tests 14/14 and `git diff --check` passed. All 13 project containers are running; no fixture locks remain. No reset, prune, VHDX compaction, Azure or native Windows SQL mutation occurred. OpenPay NU1701 compatibility warning remains.

### Current-candidate refresh — 19 November 2026 (supplemental)

- The full Docker payment matrix remains PASS in `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-021441154/`: deterministic 6/6, sandbox-positive 6/6 and Razorpay negative/cancellation 6/6 across TenantA/B/C × both providers. Case-level provider, callback, SQL/order and restoration evidence is reconciled; successful charges were not repeated.
- After reporting-code changes, current-source no-charge NFR `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-035944971/` passed functional, performance, tenant, payment-integration and security/identity checks. Its dynamic payment matrix was explicitly skipped, so that individual profile remains partial; the consolidated report uses the separately verified sandbox matrix and keeps that distinction.
- Current-source operational/recovery/rollback `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-040914029/` passed the 100-message burst and outage recovery (100/100 effects/inbox, zero loss/duplicates, 29.618 s recovery), plus retained-image Inventory rollback and exact restoration. Profile status is incomplete by selection design.
- Current-source persistence `TestResults/DockerStorage/persistence-20261119-041244001/` passed after Docker Desktop restart: known Paid-order rows, SQL volume `xy-phase10_phase10-sql-data`, G: backing path and all image binaries persisted. Current-source messaging/Functions proof `TestResults/DockerStorage/messaging-20261119-current-candidate/` passed 3-message consumer effects, DLQ intake/quarantine, one authenticated approved replay, downstream effects and replay-setting restoration. All 13 project services recovered.
- Reconciliation `TestResults/Phase10/local-followup-20261119-current-candidate013/` passed payment evidence, candidate/image binding, current NFR, operational/recovery, rollback, persistence and replay. It remains **INCOMPLETE** because the worktree is dirty, OpenPay challenge-negative is unverified, DW-023 order continuation is deferred, and Azure is not run. The E2E packet's own persistence step is NOT-RUN; the separate current-source persistence proof passed.
- Updating the handoff changes the source-content identity. Re-run source-bound no-charge/operational/persistence/replay checks and regenerate `candidate014` before treating the latest supplemental report as bound to the current worktree. Do not repeat successful sandbox payments solely for report refresh. No Git write, Azure action, data reset, prune or VHDX compaction is authorized by this entry.

### Current-candidate reconciliation refresh — 19 November 2026 (latest)

- The selected Docker E2E remains `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-211313195/` on clean HEAD `1fba2df2c634cd4786c0c8dfc24cb7b299dd34b7`: deterministic positives 6/6, real sandbox positives 6/6, and Razorpay failure/cancellation 6/6 passed across TenantA/B/C and both providers. Provider confirmation, callback/correlation, SQL Paid-order proof, and fixture restoration passed. No successful payment was repeated for reporting.
- The current-candidate no-charge NFR run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-225743031/` passed selected functional, 100-message performance, tenant, payment-integration, and security/identity checks; its own status is correctly incomplete/partial because dynamic payments were explicitly skipped and operations/recovery were not selected. Payment settings before/after matched.
- The separate operational-only NFR run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261119-230706558/` passed the 100-message burst and outage/recovery: 100/100 inbox/effects for both consumers, zero loss/duplicates, P95 9.87 s, recovery 32.259 s, consumers restored. Retained Inventory rollback and exact current-image restoration passed. The selected-profile summary remains incomplete by design.
- Docker Desktop restart persistence passed in the E2E run's `persistence/` directory: known tenant/order rows, named SQL volume and all service image identities persisted; readiness returned and the native Windows SQL listener was unchanged. All 13 `xy-phase10` services remained running.
- The first supplemental report exposed an evidence-writer defect: PowerShell emitted `changedPaths: null` for a clean image manifest, while the TypeScript verifier requires an array. The writer now explicitly emits `[]`; only legacy clean manifests normalize `null` to `[]`, while dirty malformed manifests remain blocked. The reconciler also accepts a dirty checkout only when its changed files are on the existing test/reporting/docs allowlist; application/runtime changes remain blocked. Regression tests cover both paths.
- After the fix, the separate report `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-tooling-fix/` proved image binary match and all selected local payment, NFR, operations, rollback, persistence, replay, restoration and evidence-integrity gates. The earlier `final002` report is historical; the refreshed report is `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-final003/`.
- Disposition remains **INCOMPLETE**, not Phase 10 PASS: OpenPay sandbox challenge-negative remains BLOCKED/unverified; order continuation/payment-history recovery remain deferred under DW-023/DW-024; Azure is NOT-RUN. The E2E packet's own persistence step is NOT-RUN; separate restart-persistence evidence passes. No Azure actions, data reset, Docker prune/compaction, F: recovery, commit or push occurred.
- Latest focused validation: local-follow-up tests 21/21, reporting tests 39/39, PowerShell image-evidence tests 8/8, TypeScript typecheck, AI customization validation, documentation links (197/197), and `git diff --check` passed. This evidence does not establish Git publication or hosted-check status; verify those against the exact current SHA. The OpenPay package's NU1701 compatibility warning remains.
- The reporting-evidence correction was committed/pushed as `1984f4917835cdab8be5c15d111ec2b4efdab11f`. Exact-SHA hosted checks passed: CI Build/Contract `44584778543`, AI Customization `44584778559`, Documentation Links `44584778510`, AI Prompts `44584778660`, and Drift Scanner `44584778590`; ADR Markdown `44584778544` was skipped by its opt-in condition. No Azure deployment workflow ran.
- Official Openpay sandbox documentation confirms a selective-authentication 3DS test fixture (`5454545454545454`); the Playwright runner already selects it for sandbox 3DS-on. The refreshed report now distinguishes documented 3DS support from the still-unverified visible challenge and challenge-negative behavior. No transaction was run for this clarification; DW-024 remains BLOCKED pending the required observed challenge/provider evidence.

### Local Docker checkpoint — 20 November 2026

- The no-payment Docker run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-202125004/` passed foundations, smoke, isolated integration, customer directory, currency/order entry, messaging/Functions and provider-settings restoration. It intentionally did not run payment or payment-dependent continuation steps; its `partial` result is not a payment failure or overall acceptance PASS.
- The prior full payment run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-211313195/` remains the payment evidence: deterministic 6/6, sandbox-positive 6/6, Razorpay decline/dismissal 6/6 across TenantA/B/C and both providers. No charge was repeated for reporting.
- `openpay-3ds-baseline.json` in that run records OpenPay `Use3DSecure=false` for every active tenant and verifies the approved settings. Thus the required local baseline is 3DS-off. The separately unverified visible 3DS-on challenge and provider challenge-negative behavior are extended capability work tracked for Phase 11, not a failure of those 3DS-off baseline journeys; retain their evidence as unresolved, never PASS.
- Separate Docker Desktop restart persistence passed with the named SQL volume, known tenant/order rows and service image identities unchanged. At the latest check all 13 project containers were running on G:; no reset, prune or native SQL mutation was performed.
- Reconciliation `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-final005/local-followup.json` remains **INCOMPLETE**. Its dirty-tree content fingerprint was reproduced from `a42ddd33`; `073d335b` is a later handoff-only commit. Hosted CI/contract, AI-customization and drift checks passed on both `a42ddd33` and `073d335b`; no deployment workflow ran. Verify the exact run records before relying on this navigation note.
- Remaining: Phase 10 is not globally closed; Azure acceptance is NOT-RUN. DW-023/DW-024 remain Phase 11 deferrals, and the OpenPay 3DS-on/challenge-negative capability is unresolved under its Phase 11 follow-up. Preserve the separate baseline PASS and extended-capability gap; do not repeat successful payments merely to refresh reports.

### Local persistence and reporting follow-up — 20 November 2026

- Authorized Docker Desktop restart verification passed on clean candidate `93ed259b686e2ce6308ad7751806c45151168e71`. Evidence: `TestResults/DockerStorage/persistence-authorized-20261120-004941005/summary.json`. The same TenantA/B/C Paid-order rows survived; the named SQL volume remained `xy-phase10_phase10-sql-data`; the configured backing path remained `G:\DockerStorage\DockerDesktopWSL`; public/readiness endpoints returned; all 13 project containers recovered; service image identities and the native Windows SQL listener were unchanged. No volume reset or delete occurred.
- L5-R reporting increment adds sanitized payment matrices plus supplemental persistence and selected-scope NFR/rollback reconciliation. Payment expectations derive from each nested seed contract; malformed, missing, duplicate or unbound evidence blocks. Supplemental persistence compares tenant/order snapshots, exact clean-candidate provenance, the named SQL volume and all 13 service image IDs. Supplemental NFR requires exact selected check inventories, threshold metrics, restoration evidence, rollback identity and matching image IDs. These projections do not promote historical evidence into current-candidate acceptance or overwrite the packet's own step verdicts.
- Validation: report suite 53/53 and TypeScript compile passed. The report-only projection at `TestResults/Phase10/ReportSmoke/phase10-report-reconcile-20261120-05/index.html` renders deterministic 6/6, sandbox-positive 6/6, sandbox-negative 6/6; supplemental persistence PASS; selected operational/recovery scope PASS and rollback PASS, with overall NFR PARTIAL and replay NOT-RUN. Overall report remains BLOCKED. The historical run directory was not modified and no charge was submitted.
- Fresh cold-build/no-payment run `phase10-docker-http-20261120-015424885` completed with `partial` status on dirty worktree fingerprint `6b3c3da42127fc64fed5040baa3317133d0bcac615d675f4fddb5ba23ae7a0f8` at HEAD `93ed259b`. All 36 foundation checks, smoke, isolated integration, OpenPay 3DS-off baseline, baseline validation, customer-directory, currency/order-entry, messaging effects, provider restoration and storage checks passed; integration databases were run-owned and marked completed-and-cleaned. Deterministic and sandbox payments, payment-derived TenantC routing, order continuation and in-run persistence were explicitly NOT-RUN. Finalization v4 generated `index.html`; `verify:phase10-completion` verified the hashes and recorded `partial`, while the report verdict remains BLOCKED. Cold-built image identities were stable within this run (13/13 before/after) but differ from the prior payment run's images, so its payment matrix is historical and cannot certify this rebuilt image set. No charge, reset or Azure operation occurred. Integration still emits the known OpenPay SDK NU1701 compatibility warning.
- A separately authorized Docker Desktop restart-and-persistence check passed at `TestResults/DockerStorage/persistence-20261120-023734890/summary.json`: TenantA/B/C Paid-order snapshots were byte-for-byte unchanged, the named SQL volume and G: backing path were unchanged, public/readiness endpoints returned, all 13 project containers recovered, image identities and the native Windows SQL listener were unchanged. No volume reset/deletion occurred. Evidence binds the restart to the dirty source identity captured at that run's start; report-test-only edits followed and require their own validation, not a claim that the restart tested those later edits.
- L5-R reporting follow-up now includes seed-derived tenant identity/isolation evidence in the offline report. The current run's existing `customer-directory/summary.json` reconciles PASS for 7/7 expected observations: platform-admin access for A/B/C, assigned-user access plus one cross-tenant 403 for each tenant, and the recorded same-browser/cross-tab logout scenario. This does not claim every user-by-tenant denial pair or every tenant-switch UX path. Account identifiers are not rendered. Unit contracts cover active-tenant completeness, failures, malformed/duplicate results and output redaction. Payment summaries must now explicitly report `primaryPassed=true`; missing/false primary status cannot be overridden by complete-looking case rows. The report CLI supports a separate, non-overwriting `--output-directory` projection. Report suite passed 59/59 and `npx tsc --noEmit` passed. Refreshed projection: `TestResults/Phase10/ReportSmoke/phase10-report-reconcile-20261120-07/index.html`; identity is PASS 7/7, overall remains BLOCKED and payment case evidence is NOT COLLECTED because payments were not run. The original run directory and its older `index.html` were left untouched; no charges were submitted.
- L5-R is still open: full Phase 10 suite inventory/outcome reconciliation, complete same-candidate packet reconciliation, remaining local NFR/acceptance dispositions and final closeout are not established by this increment. DW-023/DW-024 remain deferred; OpenPay challenge-negative remains unresolved; Azure remains NOT-RUN. Reporting source changes are currently uncommitted and invalidate no application image, but need focused review and current-candidate validation before any acceptance claim.

### Payment follow-up on cold-built Docker images — 20 November 2026

- On clean commit `b9d21165ab8c77e9108dbf7473b35febc13bda4`, the user-approved deterministic baseline passed 6/6 and the provider-sandbox positive baseline passed 6/6 for every active tenant × both providers. Evidence is under `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261120-030636948/payments/`; deterministic summary: `payment-acceptance-deterministic-1795124298136/summary.json`; sandbox summary: `payment-acceptance-sandbox-1795124628122/summary.json`.
- Each sandbox case entered through the UI using a fresh persisted order. Sanitized dependency evidence shows `Simulation=False` for create-charge and fetch-charge; provider confirmation is remote/completed with matching amount/currency; SQL proof shows one successful charge, no failed attempt, and `Paid` order state. All six fixture cleanups completed. This proves provider sandbox journeys, not live-money processing.
- Post-run seed/provider contract passed for all three tenants and six provider rows: baseline routes A/B Razorpay and C OpenPay; both providers present; merchant/public-key/config-key comparisons pass; all non-production; OpenPay 3DS-off. Exact baseline was not manually overwritten. Payment mode restored to sandbox and no fixture locks remained.
- Thirteen runtime image IDs/references/digests matched before/after the matrix and matched the prior cold-build image inventory. The cold-build manifest records base `93ed259b` plus a dirty worktree. Its changed paths and the subsequent `b9d21165` commit are limited to automation/reporting/tests and documentation; no application source path changed. The complete worktree-content hash differs because report-identity files and checkpoint docs were added or updated after the build; do not assert an exact whole-repository source fingerprint for the images.
- A separately approved Docker Desktop restart-persistence run passed at `TestResults/DockerStorage/persistence-20261120-023734890/summary.json`: TenantA/B/C known rows and named SQL volume persisted, G: backing path and service identities remained unchanged, and 13/13 Phase 10 services recovered. Hosted checks passed on exact `b9d21165`: CI/Contract `44619423534`, AI Customization `44619424121`, Documentation Links `44619423560`, Drift Scanner `44619423772`.
- The sealed cold-build E2E packet `phase10-docker-http-20261120-015424885/` remains `partial` because its payment, continuation and in-run persistence steps were NOT-RUN. The later payment evidence is a separate follow-up; it is not nested in or retroactively substituted into that packet. The current L5-R reporter requires full same-run packet provenance, so overall Phase 10/L5-R remains **BLOCKED/INCOMPLETE**. Do not repeat successful charges solely to obtain a green report.
- Remaining: determine a safe, explicit L5-R reconciliation for linked post-run payment evidence (without relaxing source/image/case-artifact checks); then close currently selected-scope versus full NFR/replay and suite-inventory gaps. Razorpay S2S remains blocked pending merchant entitlement; OpenPay 3DS-on visible challenge/negative outcomes remain unverified. DW-023/DW-024 remain Phase 11 deferrals. Azure remains NOT-RUN. No reset, prune, Azure or native SQL action occurred.

### L5-R supplemental reconciliation of current payment follow-up — 20 November 2026

- A non-overwriting report was generated at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v3/index.html` using the current cold-build no-payment packet, the current payment follow-up summaries, and the available supplemental NFR, operations, replay, and persistence artifacts. The previous v1 projection using the 19 Nov full E2E packet is preserved; it correctly returned FAIL because its 13 image binaries differ from the selected 20 Nov images.
- The v3 verdict is **INCOMPLETE** (not functional FAIL). The report independently shows current deterministic 6/6 and sandbox-positive 6/6 matrices PASS; the current cold-build E2E and payment follow-up have matching 13 image binaries; and Docker restart persistence outcome PASS. The sealed no-payment packet remains partial and its payment steps remain NOT-RUN.
- `payment-matrix-source-image-binding` is BLOCKED because the payment case ledgers, provider confirmation/dependency traces, SQL proofs, and verification reports are in a separate follow-up directory rather than inside a sealed full E2E run. Do not rewrite or reopen the sealed run to make it appear otherwise. Historical Razorpay decline/dismissal matrices are listed separately and are not current-image proof.
- `current-checkout-image-candidate-identity` and `clean-single-source-candidate` are BLOCKED: the 20 Nov image build manifest records base `93ed259b` plus a dirty worktree; later report/checkpoint changes make the complete source hash differ. The 13 binaries match, and the intervening source paths are automation/reporting/tests/docs, but this is not an exact clean-source build binding.
- Current-image operational/outage, rollback, persistence source-binding, replay, and full-NFR gates remain BLOCKED where their selected evidence does not match the selected image candidate. Supplemental persistence outcome itself passes. This is an evidence/candidate limitation, not evidence that those operations failed. Azure is explicitly NOT-RUN.
- No additional payments or runtime mutations were run to produce this projection. Next acceptance work requires an approved decision on a linked-follow-up provenance contract versus a new full single-run packet (which would require separate approval before repeating sandbox transactions), plus scoped current-image NFR/replay execution. Razorpay S2S remains blocked; OpenPay 3DS-on challenge behavior and DW-023/DW-024 remain uncertified/deferred.

### Linked payment follow-up evidence contract — 20 November 2026

- The reconciler now validates a payment follow-up as a distinct run segment without rewriting the sealed no-payment E2E packet. It checks each matrix's case ledgers, provider confirmations/dependency evidence, SQL proofs and verification reports, then hashes those artifacts into the supplemental report.
- These hashes are captured when reconciliation runs; they provide a stable integrity reference for the generated packet but are not a signed or tamper-proof attestation of the original execution time.
- The linked-payment gate requires the deterministic and sandbox-positive matrices to share a run root; requires clean before/deterministic-after/payment-after manifests from that run with one consistent candidate; and compares all 13 image IDs, references and digests with the sealed E2E image manifest. A separate historical negative matrix may be validated and hashed from its own run root; it cannot be mistaken for current positive evidence.
- Regression coverage rejects missing artifact integrity, dirty/mismatched payment candidates and image mismatch. The report keeps `payment-matrix-source-image-binding` BLOCKED when evidence is not nested in the sealed parent run, and separately reports `supplemental-payment-run-image-binding`.
- The CLI also restricts linked payment artifacts to the Phase 10 Docker Playwright run hierarchy under `TestResults`, rejects paths outside it, and accepts the independently rooted historical negative matrix only as its own linked evidence set.
- The new non-overwriting projection `TestResults/Phase10/local-followup-20261120-b9-current-payments-v6/index.html` reports **INCOMPLETE** overall, with the linked supplemental payment image-binding gate PASS. It explicitly calls this linked multi-run evidence—not a single-run packet or source-build attestation. The sealed E2E's payment steps remain NOT-RUN; no payment was repeated.
- Projection v7 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v7/index.html` is preserved but its new supplemental operational gate was inconclusive because the CLI looked for the before-manifest in the wrong folder. Projection v8 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v8/index.html` fixes that input path and verifies the actual boundary: the 19 Nov operational before/after manifests are stable, but their final image binaries differ from the 20 Nov sealed E2E in 8/13 services (`inventory`, `notifications`, `orders`, `payments`, `gateway`, `ui`, `azurite`, `functions`). The supplemental operational/recovery image-binding gate therefore remains **BLOCKED**; the old drill results cannot certify the 20 Nov runtime. Strict current-image gates also remain blocked. No operational drill or payment was rerun for reporting.
- Projection v9 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v9/index.html` adds the exact mismatch list to the blocked gate detail (`azurite`, `functions`, `gateway`, `inventory`, `notifications`, `orders`, `payments`, `ui`). It remains **INCOMPLETE/BLOCKED**, with no payment or operational mutation rerun. Use v9 as the latest projection; preserve v7 and v8 as audit history.
- Current-image operational/recovery drill passed in `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261120-094007964/nfr/`: the 100-message burst produced 100 inbox rows/effects per consumer with P95 3.137s; outage backlog recovery completed in 32.532s with 100/100 effects per consumer, P95 9.284s, zero lost messages and zero duplicate effects; consumer readiness and environment restoration passed. Rollback switched Inventory to the verified retained image, then restored the exact original image ID; `databaseRollback=false`.
- The wrapper's overall status is **incomplete** and exit code 1 because functional, performance, tenant, payments and security categories were intentionally `not-run` under `-OperationalOnly`; the selected operational and recovery categories both passed. It did not run payments or reset volumes.
- Projection v10 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v10/index.html` records the operational/recovery evidence and PASSes the supplemental linked-image gate: before/after images are stable and match all 13 sealed E2E runtime binaries. It remains **INCOMPLETE** overall. The strict same-candidate operational and rollback gates remain BLOCKED because the operational run's candidate identity is not the sealed E2E candidate; do not convert linked multi-run evidence into a single-run/source-build claim.
- Projection v11 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v11/index.html` adds a separate gate for the sealed E2E run's own Functions proof. It PASSes: DLQ forwarding, intake/quarantine, one approval submission without retry, replay visibility within 60 seconds and downstream effects are proven by the same run, with stable before/after manifests for all 13 images. The separate historical replay-run gate remains BLOCKED on source/image binding; v11 does not promote it or overall L5-R to PASS. Payment, operational/recovery and persistence supplemental gates also PASS. The full NFR-category gate and strict source-candidate gates remain BLOCKED. No payment was repeated.
- This closes the artifact-linking ambiguity for the already-run positive payment matrix and provides current-runtime-image operational/recovery evidence, but does not close L5-R or Phase 10. Full current-candidate NFR/source binding, replay, full suite inventory reconciliation, OpenPay challenge-negative, and Razorpay S2S remain open/blocked as recorded. Azure remains NOT-RUN.
- The separately approved performance-only NFR run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261120-100110956/nfr/` passed its probe build, one-message canary, and 100-message burst. The canary produced 1/1 inventory and notification inbox/effects with P95 1.161 s; the burst produced 100/100 inbox/effects for both consumers, P95 2.123 s, and completed in 3.577 s. Before/after image manifests were stable and matched all 13 sealed E2E runtime image binaries.
- The NFR wrapper remains **incomplete** (exit code 1) because this invocation selected only `performance`; functional, tenant, payments and security were not run, while operational/recovery were skipped. This expected aggregate status is not a performance failure and must not be presented as full NFR acceptance.
- Projection v12 at `TestResults/Phase10/local-followup-20261120-b9-current-payments-v12/index.html` records passing supplemental payment, Functions replay, operational/recovery, persistence and performance image-binding outcomes. Overall remains **INCOMPLETE**: linked multi-run evidence does not establish a clean single-source candidate or satisfy strict same-run/source-candidate gates. The report records a dirty worktree and image binaries built from a dirty base; no exact clean-source attestation is claimed.
- Post-run read-only check: all 13 `xy-phase10` containers are running, loopback SQL port 14330 is reachable, and G: has 438.4 GiB free. No Phase 10 acceptance/fixture lock was found; an ignored Buildx lock file under the rollback-baseline tree was left untouched. No payment, reset, or Azure operation occurred in the performance-only segment.
- Remaining non-Azure closure work is evidence/candidate reconciliation: establish a clean reviewed candidate and applicable exact-source/image binding; reconcile complete expected-suite identities and the required full NFR scope without conflating separate selected-category runs; then produce and review the final L5-R packet. OpenPay visible 3DS challenge/negative behavior and Razorpay S2S remain uncertified; DW-023/DW-024 remain Phase 11 deferrals. Azure remains NOT-RUN.
- Forward-only evidence hardening: new E2E finalizations with a passing messaging step hash the Functions proof in completion v5. New Docker NFR finalizations record a run-scoped evidence seal; the supplemental reconciler checks it against the bytes actually loaded, validates before/after run identity and matching binaries, and requires the three named performance checks. Existing packets and v12 remain unchanged; they cannot satisfy these new supplemental seal checks retroactively. These are integrity checks, not signed provenance, clean-candidate attestation, or approval to combine linked runs for strict L5-R/L6 acceptance.
- The strict local reconciler also requires the NFR seal for the wrapper, summary, before/after image manifests, performance probe, outage drill and replay proof. It hashes and evaluates the same loaded bytes. Unsealed historical evidence cannot pass a new strict verification; recorded historical verdicts are preserved. This does not authorize combining partial NFR runs or certify configuration equivalence.
- The full no-charge NFR path requires an existing expected image set and refuses reset or operational skips. It seals provider settings before/after and keeps the raw payment-category result partial; only the exact integration-pass/matrix-not-run state can be reconciled, and only alongside a required linked payment gate. The strict CLI accepts `--payments-e2e <sealed-both-run-dir>` for a baseline payment-capable E2E packet with completion v6. The payment gate checks the same clean SHA, 13 images, provider route/tier/database/3DS and non-production settings, local credential-agreement booleans, fixture restoration, and both positive and negative sandbox gate summaries. Boolean agreement does not prove historical credential identity, and the v6 seal does not cover every case ledger. No runtime acceptance or historical packet rewrite was performed.
- Forward-only standalone payment acceptance now offers an alternative carrier when no-charge E2E/NFR evidence is already sealed: run `scripts/run-phase10-sealed-payment-matrix.ps1` separately for deterministic, sandbox-positive and sandbox-negative matrices against the exact expected clean image manifest, then pass all three directories via `--payment-deterministic`, `--payment-sandbox-positive`, and `--payment-sandbox-negative` to `reconcile:phase10-acceptance`. Each run uses the standard acceptance lock, seals its JSON artifacts, and requires seed-derived coverage, per-case provider/SQL/callback evidence, exact settings restoration and matching clean source/13 images. Missing or tampered evidence remains BLOCKED; old packets and reports are not rewritten. Unit fixtures cover all three matrix forms and tampering. Implementation was validated locally only; no Docker, provider, Azure, or Git operation was performed, and live acceptance remains NOT-RUN.

### Latest local non-Azure acceptance — 22 November 2026

- This dated checkpoint supersedes older local-acceptance entries above for candidate `e73eb8c7dc3dba23b539e04c93821ff6818a8b94`; those earlier reports remain immutable historical evidence. The run began and ended on the clean candidate with matching identities for all 13 Docker images.
- The sealed E2E run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261122-123240561/` passed: deterministic 6/6, sandbox-positive 6/6, Razorpay negative/cancellation 6/6, integration 75/75, tenant/identity/order checks, messaging/Functions, settings restoration and Docker restart persistence. The acceptance reconciliation is `PASS (scope: non-azure-local)` at `phase10-acceptance-reconciliation.json` in that run directory.
- The sealed NFR wrapper run `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261122-131843713/` passed the selected local categories: 100/100 message/effect burst, P95 2.7232s, replay visibility 4.037s, outage recovery 28.793s with zero loss/duplicates, rollback and exact image restoration, and security/identity. Its dynamic payment matrix was deliberately skipped; the linked E2E sealed matrix supplies the payment baseline. This does not prove OpenPay visible 3DS challenge behavior or Razorpay S2S.
- Hosted CI on the same SHA passed CI/Contract, AI Customization and Drift Scanner; ADR Markdown was skipped by path scope. Workflow 99 remains manual local-only under DW-028 Option A.
- Result is non-Azure local acceptance only, not full Phase 10 closure. Azure deployment/runtime/transport/payment/replay acceptance must be completed and reconciled separately. DW-023/DW-024 remain approved Phase 11 deferrals. No Azure action occurred in these runs.
