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

Adopt this as the governing Phase 10 lifecycle. Use a graduated validation model: small local changes get fast checks, platform changes get full Docker and CI parity, and Azure is used only after local evidence is clean. Each stage may begin only after the previous required stage passes, unless an explicit exception is documented.

### Validation Stages

| Stage | Name | Required proof |
|---:|---|---|
| 0 | Environment Readiness | Tooling is installed and usable: .NET 8 SDK, PowerShell 7, Node/npm, Docker Compose, Azure CLI, Bicep, Functions Core Tools, GitHub CLI; `global.json` pins the approved .NET 8 SDK; `Resources/Docker/.env.local` exists when Docker profiles require it. |
| 1 | Repository Validation | Restore, build, and unit tests pass before Docker starts: `dotnet restore XYDataLabs.OrderProcessingSystem.sln`, `dotnet build XYDataLabs.OrderProcessingSystem.sln --no-restore`, and `dotnet test XYDataLabs.OrderProcessingSystem.sln --no-build`. |
| 2 | Local Infrastructure Validation | Backing services start and pass health checks in Docker: SQL Server, Redis, Keycloak, Azurite, and Service Bus emulator when selected. No application debugging or browser E2E belongs in this stage. |
| 3 | Local Application Debug | Docker runs backing services while Visual Studio, VS Code, or command-line hosts run the gateway, APIs, UI, workers, and Functions worker for breakpoints and fast defect fixes. |
| 4 | Local Integration Validation | Integration tests prove SQL, Redis, Blob abstractions, messaging abstractions, startup wiring, idempotency, and tenant/provider behavior before browser E2E. |
| 5 | Local Docker Compose End-to-End | Full local Docker validation proves profile startup, gateway routing, Playwright/browser smoke, integration suite, payment matrix, logs, and artifacts. The payment matrix evidence must include the persisted order id, order reference, amount, and currency for each tenant/provider journey. Required before Azure for gateway, auth, Docker, messaging, infrastructure, image, or deployment changes. |
| 6 | CI Pre-Deployment Parity Gate | GitHub-hosted clean-room verification proves the solution succeeds on a fresh runner before Azure deployment. Use `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` as the CI mirror of the Docker Dev HTTP local path for Compose, gateway, service image, workflow, Bicep, transport, or payment-matrix changes. |
| 7 | Azure Deployment | `00 Azure Platform Foundation` runs only when provider registration, ACR, or pull identity must be created or refreshed. `01 Phase 10 Azure Deploy Orchestrator` deploys the selected environment. Use cleanup mode only when intentionally removing or resetting an environment. Use dry run first for infrastructure changes. |
| 8 | Azure Infrastructure And Configuration Verification | Provisioned resources are healthy; managed identities are assigned; required environment variables are present; secrets resolve from Key Vault; Container Apps revisions are healthy; Function App host runs; Storage, Service Bus, SQL, and Redis are reachable. |
| 9 | Azure Runtime Smoke | `02 Phase 10 Azure Runtime Smoke` proves gateway health, routed API JSON, UI route, and UI API proxy/bootstrap. |
| 10 | Azure Messaging Smoke | `03 Phase 10 Azure Transport Smoke` proves Service Bus publish, fan-out consume, DLQ forwarding, replay receive, and replay publish/consume. |
| 11 | Azure Business Validation | `04 Phase 10 Azure Payment Matrix` proves all-tenant business/browser/payment flows against live Azure Container Apps URLs after runtime and messaging pass. |
| 12 | Evidence And Documentation | Capture run summaries, test results, logs, screenshots/traces when applicable, workflow links, deployment outputs, and known issues. Update Phase 10 status docs only after evidence exists. |

### Post-L6 Promotion Sequence

After local pre-Azure L6 passes on a target commit SHA, promote in this exact order:

1. Run `99 Phase 10 Docker Dev HTTP End-to-End (local-Optional)` as the CI clean-room parity gate.
2. Run `00 Azure Platform Foundation` only if provider registration, persistent ACR, or pull identity must be created or refreshed.
3. Run `01 Phase 10 Azure Deploy Orchestrator` with `dryRun=true` first for infrastructure-affecting changes, then with `dryRun=false` for the real deployment.
4. Run `02 Phase 10 Azure Runtime Smoke`.
5. Run `03 Phase 10 Azure Transport Smoke`.
6. Run `04 Phase 10 Azure Payment Matrix`.

Do not treat workflow numbering as execution order. `99` is the required pre-deployment parity gate, while `00` remains a conditional platform-foundation workflow.

Environment note:

- Use workflow inputs `dev`, `staging`, and `prod`.
- Expect some Azure resource names to shorten `staging` to `stg` in resource-group and app names.
- Treat `Resources/Azure-Deployment/branch-policy.json` as the single source of truth for branch, GitHub environment, resource suffix, and Azure SQL suffix mapping.
- Run `Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` whenever Azure workflow, parameter, or naming changes are introduced. CI PR validation now runs this contract automatically.
- Use the environment-specific checklist in [phase10-azure-smoke.md](../runbooks/phase10-azure-smoke.md) for the exact operator inputs and capture rules for `dev`, `staging`, and `prod`.

### August 11, 2026 Dev Azure Evidence Snapshot

The current `dev` candidate has completed the full Azure execution lane successfully:

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

## Tracker Status

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
| Azure Functions worker implementation | Local replay path implemented | `XYDataLabs.OrderProcessingSystem.Functions` now includes the .NET 8 isolated startup validation, DLQ intake trigger, and guarded DLQ replay Function; Azure deployment proof and portal Function App smoke remain pending before the Function App is treated as complete behavior. |
| SQL / Redis baseline wiring | Automatic baseline | The wrapper and child deploy workflows include SQL and Redis as part of the default Phase 10 path; no manual parity toggle is required in the normal operator form. |
| Cleanup policy closeout | Covered for Phase 10 | Historical GHCR retention, ACR stale-tag cleanup, and stale artifact cleanup are scheduled by `phase10-retention-cleanup.yml`, Phase 10 smoke artifacts use `retention-days: 14`, Azure teardown remains manual through `cleanupInfra=true`, and Log Analytics defaults to `30` days in the workspace module. |
| ACR image cleanup policy | Implemented with ACR cutover | The retention workflow cleans dev/staging/prod ACR tags while preserving images referenced by active Container App revisions. |

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
| ACR package cleanup | Covered by `phase10-retention-cleanup.yml`; weekly schedule keeps latest `10` tags per service, deletes stale tags after `30` days, and skips active Container App revision images | No |
| GitHub artifact retention | Covered by `retention-days: 14` on Phase 10 uploads plus scheduled stale-artifact cleanup after `30` days | No |
| Azure Log Analytics retention | Covered by `infra/modules/loganalytics.phase10.bicep` default `30` day workspace retention | No blocker |
| Azure resource-group scheduled deletion | Intentionally not automated | No; keep destructive cleanup manual |

### ACR Cleanup Implementation Plan

ACR is the enterprise target for Phase 10 runtime images. The ACR cutover is not complete unless image cleanup is implemented alongside image publishing and runtime pull changes.

| Step | Implementation requirement | Done when |
|---|---|---|
| 1 | Provision the persistent platform ACR and runtime pull identity from `00 Azure Platform Foundation` | The platform resource group contains the registry and pull identity; `AcrPull` is granted only when the privileged platform path is allowed to manage RBAC |
| 2 | Build and push gateway, Orders, Inventory, Notifications, and UI images to ACR | The Phase 10 build workflow publishes service-specific ACR image refs |
| 3 | Point the app deployment at the platform ACR and pull identity | Container Apps pull ACR images without `GHCR_READ_TOKEN` and without the app deployment itself creating RG-level role assignments |
| 4 | Keep SQL and Redis in the automatic deploy baseline | The wrapper and child workflow provision SQL and Redis as part of the default Phase 10 path so the operator does not need to toggle them on |
| 5 | Add ACR image cleanup automation | `phase10-retention-cleanup.yml` keeps the latest approved image versions and deletes stale tags/manifests |
| 6 | Retire GHCR runtime dependency | `GHCR_READ_TOKEN` is no longer required by the active Azure deployment path |
| 7 | Update summaries and runbooks | Deploy summary identifies ACR image refs, parity flags, and the cleanup policy owner |

ACR retention default for dev:
- Keep the latest `10` image versions per service.
- Delete untagged or stale image manifests older than `30` days.
- Keep cleanup in dry-run mode for the first manual validation, then enable the schedule after one successful ACR-backed deploy.

ACR retention posture for staging/prod:
- Use a longer retention window than dev.
- Keep release tags that map to deployed revisions.
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

### Pause/Resume Checkpoint — 10 November 2026

The owner paused Phase 10 work for today. The accepted bounded Docker baseline is preserved in `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261110-030929435/acceptance-packet.json`; it is not full Phase 10 completion, current-candidate NFR/rollback certification, or Azure acceptance. Do not reset Docker merely to resume.

Remaining Phase 10 work, in resume order:

1. Implement **L5-R unified HTML automation reporting**, including backend/frontend coverage and honest aggregation of existing test/Docker evidence.
2. Complete or regenerate **current-candidate L5/L6 evidence** for architecture, performance, security, required failure drills and executed rollback; bind it to the reviewed commit and image digests. Existing bounded Docker PASS does not fill missing gates.
3. Provide an approved **CI validation path without mandatory PRs**, with same-candidate contract and test results.
4. Implement/review the **Azure CI/CD readiness corrections** recorded below: immutable images, Entra-aware automation, runtime configuration, non-overwriting migrations/seeds, deployed origins/callbacks, release health and rollback safeguards.
5. Only after separate approval, perform **Azure deployment and E2E acceptance** through the documented workflow sequence, including actual Service Bus/Functions effects, tenant isolation, provider confirmation and correlated telemetry/SQL evidence.
6. **Close out Phase 10:** reconcile historical tracker statuses with current evidence, assemble the same-candidate acceptance/promotion packet, and verify every existing Phase 10 exit gate. Do not mark absent, partial or deferred evidence PASS.

The detailed implementation/acceptance requirements are in the L5-R and Azure TODO sections below. This checkpoint does not include or start Phase 11 work and does not authorize Azure deployment, reset, commit or push. Resume with L5-R analysis/implementation planning under the repository approval rules.

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
| L6 | Final pre-Azure acceptance | Architecture conformance gate, local Docker validation, CI workflow `99`, evidence packet docs | Architecture, operational, and deployment gates all green on one commit SHA |

### Remaining Phase 10 Work: Unified HTML Automation Report (L5-R)

**Status: planned, not implemented.** Deliver local/Docker reporting before Phase 10 local reporting closeout; do not defer it to the Phase 11 payment UX workstream. This is an evidence/presentation addition, not a replacement for the independent L5/L6 gates or an Azure deployment authorization.

**Deliverable:** one automatically generated `index.html` in the existing per-run `TestResults` directory on Q:, with a supporting artifact folder that can be shared as a ZIP. The summary must open locally without a reporting service or external CDN; detailed coverage, logs, screenshots, and other approved artifacts remain linked rather than embedded into one oversized file.

Implementation plan:

1. Define a versioned result contract and expected-suite inventory. Record run ID, commit SHA, dirty-worktree state, environment, selected suites/profile, image identities when available, timestamps, duration, and artifact provenance. Never merge different runs or silently import historical passes.
2. Reuse .NET xUnit/TRX, Vitest structured results, existing TypeScript Playwright/custom-runner JSON, and acceptance packets. Normalize suite and individual-test results with counts, duration, failure details, and artifact links. Preserve raw files and exit codes. No migration to NUnit, Playwright .NET, ExtentReports, or another browser runner is required solely for reporting.
3. Enable scoped .NET coverage through the existing `coverlet.collector`; generate detailed HTML with a pinned repository-local ReportGenerator tool. Add compatible pinned Vitest coverage tooling for frontend coverage. Define measured projects, exclusions, and line/branch metrics explicitly; distinguish unit/integration measurements and report combined coverage only when correctly merged. Docker browser execution does not establish deployed-service code coverage without separate instrumentation. Missing coverage is unavailable/not collected, never a fabricated zero or PASS; agree numeric thresholds separately rather than inventing a gate.
4. Generate a static dashboard with summary counts; unit, integration, architecture, frontend, browser and safety-check sections; backend/frontend coverage; tenant/provider matrices; and build/seeding, identity, messaging/Functions, persistence, restoration, storage and available NFR/rollback evidence. Separate deterministic payments from real sandbox results and scenario coverage from code coverage. Preserve PASS, FAIL, SKIPPED, BLOCKED, DEFERRED, NOT-RUN, and interrupted/partial outcomes without weakening existing required gates or claiming DW-023/DW-024 are implemented.
5. Integrate generation into the existing Docker E2E hook's finalization path so failures and interrupted/incomplete runs still receive a truthful report when finalization can execute. Missing, duplicate, contradictory or unreadable required results, broken required artifact references, and report-generation failures must be visible and cannot turn the run green. A report-only command must render existing evidence without running tests, changing databases/settings, or starting provider charges.
6. Validate with controlled complete, failed, empty, stale, duplicate, malformed and interrupted evidence, including missing coverage, failed restoration, and HTML/path-injection fixtures. Escape report content, constrain artifact links to the run packet, and reuse artifact sanitization; never publish credentials, tokens, card/CVV values or raw sensitive payloads. Retain only policy-approved sanitized browser artifacts and avoid unnecessary large-file duplication on limited storage.
7. Run the normal local/Docker acceptance and verify the generated dashboard against raw TRX/JSON totals and authoritative payment/provider/SQL evidence. Document exact run, report-only, open and package commands. Future GitHub Actions artifact publication/history is a separately scoped follow-up; Azure resources, workflows/deployment and directory writes remain excluded from this local implementation.

**Affected areas:** `scripts/run-phase10-foundation-tests.ps1`, isolated integration runners, `scripts/run-phase10-docker-dev-e2e-hook.ps1`, automation report contracts/generation, frontend test/coverage configuration, repository-local tool configuration, focused report tests, and the existing Docker runbook. Preserve unrelated changes and existing runtime/payment behavior; no reset, pruning, database schema change, automatic commit or push is included.

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

- [ ] **Runnable CI without mandatory PRs:** `.github/workflows/ci.yml` currently triggers only on pull requests. Provide an approved manual or branch-push validation path for the owner's no-PR workflow, including the same contract/test gates, before calling a direct `dev` commit CI-validated. Bind downstream approval to the successful run and exact candidate SHA, not just the latest branch tip. Do not silently introduce mandatory PRs or auto-deployment.
- [ ] **Immutable build and deployment handoff:** the current deploy orchestrator supplies `imageTag: phase10`; replace reliance on that mutable tag with recorded service image digests. Pin the candidate checkout and record build inputs/toolchain/lockfiles, all required service images, the Functions artifact/hash appropriate to its selected deployment model, deployment parameters and artifact hashes. Verify running revision image identities and the deployed Functions artifact against the approved manifest. Reuse the same immutable artifacts across promotion; reject mixed-commit services and never substitute locally cached Docker images or Docker-only infrastructure images for Azure resources.
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
7. Close L6 only after architecture conformance, local Docker validation, and CI parity all match the same commit SHA.

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

The next useful Phase 10 change sets should produce:

- one completed architecture cleanup or service-ownership slice at a time
- updated architecture tests or integration tests that prove the slice
- updated evidence pointers and exception manifest entries where applicable
- no new undocumented temporary dependency or fallback path
