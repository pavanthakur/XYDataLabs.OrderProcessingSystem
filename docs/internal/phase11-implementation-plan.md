# Phase 11 Implementation Plan

## Purpose

Phase 11 turns tenant topology changes and service data ownership into governed operations. It prevents registry state from advertising a dedicated database or payment provider before the corresponding infrastructure, secret, migration, identity, and runtime contracts are ready.

This document is the execution companion to the Phase 11 roadmap in `ARCHITECTURE-EVOLUTION.md`.

## Phase 10 Carry-Forward And Phase 11 Target

Phase 10 proves that runtime discovery, validation, smoke, and payment execution can follow registry topology without treating `TenantA`, `TenantB`, or `TenantC` as invariants. It intentionally fails closed when a newly configured dedicated tenant has no provisioned database contract.

Phase 11 removes that remaining operational gap. Its target is:

- adding an arbitrary shared tenant requires no application, script, workflow, or Bicep edit;
- adding an arbitrary dedicated tenant provisions every required service-owned store from governed topology inputs;
- moving a tenant between shared and dedicated storage is a resumable, reconciled operation;
- assigning any already-supported payment provider requires no execution-path edit;
- adding a new provider type requires an explicit provider capability implementation, but no tenant-specific branching;
- Azure workflows `01` through `04` consume the same immutable topology-operation evidence and cannot disagree about tenant tier, database binding, or provider assignment.

Phase 11 does not make arbitrary unknown provider implementations data-driven. OpenPay and Razorpay remain supported provider capabilities until another provider adapter, credential schema, callback contract, deterministic test adapter, and operational runbook are approved.

## Architecture Invariants

1. The tenant registry is the only source of truth for active status, tenant tier, and assigned payment provider.
2. Discovery reads registry state. Validation checks whether infrastructure, secrets, databases, identities, and runtime behavior satisfy that state.
3. Secrets and database names never determine tenant tier or provider assignment.
4. A topology operation prepares and validates the target contract before changing authoritative registry state.
5. New tenants remain inactive until their complete target contract passes validation.
6. Existing tenants remain on their current working topology until target preparation succeeds.
7. No runtime, workflow, or operator script may infer topology from tenant codes such as `TenantA`, `TenantB`, or `TenantC`.
8. APIs never run schema migrations at startup. A governed migrator owns forward-only migration execution.
9. Evidence contains secret identifiers and contract status only, never secret values, credentials, or private-key material.
10. Every operation is idempotent, concurrency-controlled, auditable, resumable, and reversible within its declared rollback window.
11. Discovery determines desired topology; provisioning prepares it; validation proves it; activation changes registry truth. These stages cannot be collapsed.
12. An execution filter or debug provider override never truncates discovery, weakens validation, or mutates registry-derived topology.
13. A tenant-level dedicated tier expands to the complete governed set of service-owned dedicated stores; a partially provisioned dedicated tenant cannot be activated.
14. Environment and branch mapping is validated before any mutation: `dev -> dev`, `staging -> staging`, and `main -> prod`.

## Logical Component Design

Phase 11 introduces an operations control plane around the existing tenant registry and service runtimes.

```text
Operator / GitHub workflow
          |
          v
Topology Operation API / Orchestrator
          |
          +--> Registry Snapshot Reader (discovery only)
          +--> Expected Contract Builder
          +--> Service Store Provisioners
          +--> Provider Contract Validator
          +--> Migration Coordinator
          +--> Identity Grant Coordinator
          +--> Runtime Contract Verifier
          +--> Evidence Writer
          +--> Registry Activator (optimistic concurrency)
          +--> Reconciler / Rollback Coordinator
```

Component responsibilities:

| Component | Responsibility | Must not do |
|---|---|---|
| Registry Snapshot Reader | Read active and pending tenant identity, tier, provider, and registry version | Infer topology from secrets, database names, or tenant code |
| Expected Contract Builder | Expand tenant topology through governed service and provider catalogs | Provision resources or mutate registry state |
| Store Provisioner | Create or validate shared-pool and dedicated service stores from typed inputs | Decide whether the tenant is shared or dedicated |
| Migration Coordinator | Run service-owned, forward-only migrations and report schema versions | Run migrations inside API startup |
| Identity Grant Coordinator | Grant the correct runtime identity access to each prepared store | Store credentials in evidence |
| Provider Contract Validator | Validate provider capability, alias, callback, currency, and deterministic adapter contracts | Select the authoritative provider assignment |
| Runtime Contract Verifier | Verify deployed routing, registry view, store reachability, and provider configuration | Repair drift silently |
| Registry Activator | Apply one concurrency-checked authoritative topology update | Activate before aggregate validation passes |
| Evidence Writer | Persist immutable, non-secret operation and validation evidence | Record secret values, tokens, passwords, or private keys |
| Reconciler | Detect registry/infra/runtime drift and create repair proposals | Perform unapproved destructive repair |

The initial control plane may be implemented as a workflow-driven application service. Durable Functions should be used only when the operation needs durable waits, retries, or compensation; business rules and validation remain in application services so they are testable without the Functions host.

## Required Control-Plane Model

Add an operations-owned topology-change record. The exact storage implementation may vary, but the logical contract must include:

```text
operationId
tenantCode
changeType
currentActive
currentTier
currentProviderCode
targetActive
targetTier
targetProviderCode
state
requestedBy
approvedBy
createdAtUtc
updatedAtUtc
registryVersion
idempotencyKey
expectedContractHash
sourceEvidenceVersion
failureCode
failureStage
rollbackDeadlineUtc
evidenceLocation
```

Supported change types:

- onboard tenant
- activate or deactivate tenant
- move shared to dedicated
- move dedicated to shared
- change payment provider
- repair topology drift
- roll back an incomplete or recently activated change

State machine:

```text
Requested
  -> Approved
  -> Provisioning
  -> Migrating
  -> Validating
  -> ReadyForActivation
  -> Activating
  -> Verifying
  -> Completed

Any pre-activation state -> Failed or Cancelled
Any post-activation verification failure -> RollingBack -> RolledBack or ManualInterventionRequired
```

The combination of `operationId` and tenant-scoped operation lock must prevent concurrent conflicting changes. Registry updates must use optimistic concurrency through `registryVersion`.

Required persistence constraints:

- unique `operationId`;
- unique `idempotencyKey` within an environment;
- at most one non-terminal topology operation per tenant;
- immutable operation transitions and evidence references;
- registry update conditioned on the captured `registryVersion`;
- deterministic retry returns the existing operation instead of creating another mutation.

### Operator Interface

Expose one operator-protected application contract; workflows and any future UI must call this contract rather than reimplementing topology rules.

```http
POST /api/v1/admin/tenant-topology/operations/plan
POST /api/v1/admin/tenant-topology/operations
GET  /api/v1/admin/tenant-topology/operations/{operationId}
POST /api/v1/admin/tenant-topology/operations/{operationId}/approve
POST /api/v1/admin/tenant-topology/operations/{operationId}/resume
POST /api/v1/admin/tenant-topology/operations/{operationId}/rollback
```

Interface rules:

- mutation requests require an idempotency key and expected registry version;
- plan is read-only and returns expected resources, aliases, checks, and caller capabilities;
- approval and rollback require a dedicated topology-operator role and actor audit data;
- responses return operation state and evidence references, never secret values;
- stale registry versions return a conflict and require a new plan;
- workflow cancellation stops future stages but does not imply rollback or cleanup;
- operator APIs dispatch application commands; orchestration logic does not live in controllers or workflow YAML.

## Expected Topology Contract

The orchestrator builds one immutable expected contract before provisioning. At minimum it contains:

```text
environment
registryVersion
tenantCode
targetActive
targetTier
targetProviderCode
serviceStores[]:
  serviceCode
  storageMode
  databaseResourceName
  connectionSecretAlias
  requiredSchemaVersion
  runtimeIdentity
providerContract:
  capabilityCode
  privateKeyAlias
  webhookSecretAlias
  callbackContract
contractHash
```

The contract records identifiers and expected states only. Secret values and connection credentials are never serialized. Database resource names are generated by the governed naming module or returned by provisioning and then recorded; runtime code must not reconstruct them from tenant code.

Two governed catalogs feed contract construction:

1. **Service storage catalog**: identifies stateful services, their shared-pool binding, dedicated-store template, migrator, required schema version, and runtime identity.
2. **Provider capability catalog**: identifies supported provider codes, required secret aliases, callback/webhook requirements, currencies, deterministic test adapter, and runtime health check.

Tenant registry data selects tier and assigned provider. Catalogs define how an already-selected topology is provisioned and validated; they are not additional topology sources of truth.

## Dynamic Infrastructure Contract

Replace the Phase 10 `TenantC`-shaped dedicated database deployment with a parameterized topology input. The IaC boundary accepts a collection of prepared dedicated-store specifications rather than one named tenant parameter.

```text
dedicatedStores[]:
  tenantCode
  serviceCode
  databaseResourceName
  runtimeIdentityResourceId
  requiredSchemaVersion
```

Rules:

- Bicep modules iterate the typed collection and return resource IDs and actual database names keyed by tenant and service.
- Secret synchronization consumes those outputs; it does not infer resource names.
- Shared tenants bind to each service's shared pool and never require a dedicated secret.
- Dedicated tenants require every mandatory service-store result before activation.
- IaC dry-run/what-if and capability preflight run before mutation.
- Resource deletion is excluded from onboarding and tier activation. Retirement is a later approved cleanup after the rollback window.
- Environment-specific names and tags come from the existing governed environment mapping, not branch string concatenation inside individual scripts.

During migration from Phase 10, the current Orders/shared database may be represented as a time-bounded service-catalog exception. The exception must identify its owner and removal workstream; it cannot become the permanent target design.

## Azure Workflow Contract (`01` Through `04`)

All four workflows operate on the same environment, commit SHA, registry version, and topology evidence version.

### `01 Phase 10/11 Azure Deploy Orchestrator`

- validates branch/environment mapping and deployment identity capabilities;
- resolves the current registry snapshot and requested topology operation;
- builds and hashes the expected contract;
- provisions generic shared/dedicated service stores, migrations, identities, and provider aliases;
- refreshes affected workloads only after contracts are synchronized;
- verifies prepared topology and activates registry state last;
- publishes `topology-operation.json` and `topology-contract.json` as non-secret artifacts.

### `02 Azure Runtime Smoke`

- requires the successful `01` evidence version for topology-changing deployments;
- rediscovers runtime topology and compares it with the activated contract hash;
- verifies each active tenant's tier, service-store reachability, gateway route, and assigned provider configuration;
- fails before business smoke on missing, stale, inactive, or conflicting topology.

### `03 Azure Transport Smoke`

- consumes the same validated active tenant catalog;
- selects representative shared and dedicated tenants by tier, never by tenant code;
- proves tenant, correlation, outbox, broker, inbox, and service-store routing across the current topology;
- emits transport evidence linked to the topology contract hash.

### `04 Azure Payment Matrix`

- discovers and validates all active topology before applying tenant filters;
- executes the registry-assigned provider by default;
- may test every validated supported provider through a bounded debug/test override without changing registry truth;
- restores the original provider assignment in a guaranteed cleanup path when reassignment is part of the test;
- verifies authoritative amount/currency, callback/webhook idempotency, order state, inventory effect, notification effect, and correlation evidence;
- emits journey results linked to the topology contract hash.

Promotion is rejected when workflow evidence references different environment, commit SHA, registry version, or contract hash. A workflow rerun after topology mutation must rediscover and revalidate rather than reuse stale evidence.

## Local-First Delivery And Promotion Sequence

Every workstream follows the same graduated path. Azure is not used as an application debugger.

1. **Architecture and contract gate**
   - approve storage and topology-operation ADRs where a durable decision is introduced;
   - add architecture tests before removing temporary exceptions;
   - prove no tenant-code or provider-assignment discriminator exists in active paths.
2. **Repository gate**
   - restore, build, unit tests, architecture tests, and focused integration tests;
   - validate Bicep, workflow YAML, PowerShell parsing, environment mapping, and secret scanning.
3. **Local Docker gate**
   - use Docker Compose as the canonical runtime;
   - run SQL, Redis, Keycloak, Azurite, Service Bus emulator where supported, Functions, services, gateway, and UI;
   - execute topology scenarios against disposable databases and deterministic provider adapters;
   - prove resume and rollback by injected failure, not documentation alone.
4. **CI clean-room gate**
   - rebuild on a clean runner;
   - execute contract, integration, topology, messaging, and deterministic payment tests;
   - reject generated or stale topology evidence.
5. **Azure dev gate**
   - run dry-run/what-if, capability preflight, operation execution, runtime smoke, transport smoke, and the dynamic payment matrix;
   - retain workflow URLs, commit SHA, resource outputs, contract hash, and rollback evidence.
6. **Azure staging gate**
   - repeat the complete operation using staging identities and secrets;
   - require explicit approval and prove the promotion packet references one consistent contract.
7. **Production gate**
   - use bounded, non-destructive validation by default;
   - require staging evidence, change approval, declared rollback window, and post-activation verification;
   - run destructive migration scenarios only for an explicitly approved real tenant operation.

A gate cannot be promoted when a prior required gate is failed, skipped without an approved exception, or references a different contract hash.

## Phase 11 Execution Workstreams

Workstream identifiers deliberately avoid `11.5`; the architecture roadmap reserves Phase 11.5 for the isolated PostgreSQL portability proof.

### P11-W1 Topology Contract Foundation

- Define typed registry, expected-contract, validation-result, and evidence schemas.
- Define a governed service catalog for Orders, Payments, Inventory, and Notifications. The catalog, not tenant codes or scripts, determines which service-owned stores must exist.
- Record an ADR for the Phase 11 storage contract and secret naming before splitting data. The target model is one shared-tenant pool per stateful service plus service-owned dedicated stores for dedicated tenants; any temporary exception requires an owner and removal milestone.
- Expand a tenant-level `Dedicated` tier into the complete expected set of service-owned dedicated stores. Activation must wait for the aggregate contract, not only the Orders database.
- Implement one topology resolver shared by local, Docker, CI, and Azure operator paths.
- Validate duplicate tenant codes, conflicting records, unsupported tiers/providers, inactive catalog leakage, malformed dedicated connections, missing provider aliases, and missing dedicated contracts.
- Reconcile every existing active tenant into a clean baseline before enabling topology mutations. Existing drift must be repaired or recorded as a time-bounded exception; it must not be silently imported as valid state.
- Extend the generic IaC contract so a topology operation can provision any approved tenant code without editing Bicep or workflow logic.
- Keep existing sample tenants as seed data only.
- Add architecture tests that reject tenant-code discrimination and non-dry-run static catalogs.

**Exit gate:** arbitrary tenant codes and multiple dedicated tenants can be represented, validated, and evidenced without script changes.

### P11-W2 Service-Owned Persistence Foundation

- Split Orders, Payments, Inventory, and Notifications persistence and migrations by service ownership.
- Preserve tenant topology semantics independently for each service-owned store.
- Give each stateful service one shared-tenant pool and a parameterized dedicated-store contract.
- Prohibit cross-service direct database access and cross-service joins.
- Use integration events and local projections for cross-service consistency.
- Register each store, migrator, schema version, and runtime identity in the governed service storage catalog.
- Keep transitional compatibility behind explicit, tested adapters with an owner and removal milestone.

**Exit gate:** each stateful service owns its schema and migration path, and the topology contract can expand one dedicated tenant into every required store.

### P11-W3 Governed Tenant Provisioning

Implement the topology operation state machine and use this ordering for a new dedicated tenant:

1. Create an inactive registry record or separate pending operation; do not expose it to execution catalogs.
2. Preflight the operator/workflow identity capabilities needed to provision databases, write/read secret contracts, run migrations, and grant runtime identities. Classify authorization failure separately from missing configuration.
3. Provision all mandatory service-owned dedicated databases from generic IaC inputs.
4. Run each service's approved migration bundle.
5. Seed only tenant-owned baseline/reference data.
6. Create the service-scoped dedicated connection aliases defined by the approved storage-contract ADR. Preserve `DedicatedTenantConnectionStrings--{TenantCode}` only as a documented transition alias while Phase 10 compatibility remains active.
7. Grant required service managed identities access to the database.
8. Provision and validate `PaymentProviders--{TenantCode}--{ProviderCode}--PrivateKey` and webhook contracts.
9. Run database, secret, identity, provider, and runtime preflight checks.
10. Write a non-secret topology evidence packet.
11. Activate the tenant in one concurrency-checked registry update.
12. Run post-activation smoke and business verification.

Shared-tenant onboarding follows the same flow but validates the shared database contract and must not create or require a dedicated connection secret.

For the service-owned target model, database preparation through identity grant executes for every stateful service in the governed service catalog. Each service reports an independent result, and activation requires all mandatory results to pass.

**Exit gate:** adding a shared or dedicated tenant requires configuration and an approved operation, not code or workflow edits.

### P11-W4 Tier Migration Workflows

#### Shared to dedicated

1. Keep the registry tier as shared while preparing the target database.
2. Provision, migrate, seed, and grant identities on the dedicated database.
3. Copy tenant-scoped data with reconciliation counts and integrity checks.
4. Quiesce or dual-write only through an explicitly approved cutover design.
5. Validate the dedicated target and create evidence.
6. Change the registry tier to dedicated last.
7. Verify runtime routing and no writes to the old location.
8. Retain the shared source data for the rollback window; remove it only through a separately approved cleanup.

#### Dedicated to shared

1. Keep the registry tier as dedicated while preparing shared storage.
2. Validate shared capacity, schema, indexes, quotas, and tenant isolation.
3. Copy and reconcile tenant-scoped data.
4. Change the registry tier to shared only after target validation.
5. Verify routing and isolation.
6. Retain the dedicated database through the rollback window before decommissioning.

**Exit gate:** both tier moves are repeatable, idempotent, audited, and proven with rollback tests.

### P11-W5 Provider Reassignment

1. Keep the existing registry assignment active.
2. Provision the target provider key and webhook contracts.
3. Validate provider support, credentials, callback URLs, currency, and deterministic adapter behavior.
4. Run a targeted preflight without changing topology truth.
5. Update the registry provider assignment last using optimistic concurrency.
6. Run provider-specific smoke and idempotency verification.
7. Retain the old provider secret during an approved overlap/rollback window.
8. Remove the old contract only after reconciliation confirms no pending attempts depend on it.

Debug overrides may execute another validated provider path, but must not modify registry truth or bypass contract validation.

Adding a new provider capability is a code-and-contract change, not a tenant operation. It requires:

- provider adapter and typed configuration;
- secret and webhook/callback schema;
- deterministic success, decline, timeout, retry, idempotency, and reconciliation tests;
- provider health/preflight implementation;
- provider capability catalog registration;
- local Docker, CI, and Azure validation before tenant assignment is permitted.

**Exit gate:** provider reassignment requires no script edit and can be rolled back without losing payment correlation or reconciliation state.

### P11-W6 Drift Detection And Repair

Implement a scheduled and on-demand reconciler that compares:

- authoritative registry topology
- expected database topology
- Key Vault secret identifiers
- managed-identity database grants
- migration versions
- provider contracts
- runtime topology endpoint
- recent topology evidence

Detection is read-only by default. Repairs require an approved topology operation; the reconciler must not silently change registry truth, create credentials, move data, or activate tenants.

Classify drift at minimum as:

- missing dedicated database
- missing or malformed dedicated connection contract
- missing provider contract
- missing identity grant
- schema version mismatch
- runtime/registry mismatch
- orphaned dedicated database or secret
- inactive tenant present in an execution catalog

**Exit gate:** drift produces actionable, non-secret evidence and an approved repair path.

### P11-W7 Acceptance And Operational Handover

Run these scenarios in local Docker, CI, Azure dev, and staging before Phase 11 closes:

- onboard one arbitrary shared tenant
- onboard one arbitrary dedicated tenant
- onboard two dedicated tenants in the same environment
- fail provisioning before registry activation and prove no runtime impact
- resume the failed operation with the same `operationId`
- move shared to dedicated and roll back
- move dedicated to shared and roll back
- reassign both supported payment providers and restore the original assignment
- deactivate and reactivate a tenant
- detect and repair missing-secret, missing-grant, schema-drift, and runtime-drift cases
- prove missing-secret failures classify as configuration-contract failures while denied Key Vault access classifies as authorization failure
- prove dry-run/what-if identifies expected resource and secret identifiers and checks caller capabilities without reading or printing secret values
- reject concurrent conflicting operations
- prove no topology operation logs secret values

Production promotion requires staging evidence plus an explicit approval. Production testing must use bounded, non-destructive verification unless a separately approved tenant migration is being executed.

## Workstream Dependency Order

```text
P11-W1 Topology contract foundation
        |
        +--> P11-W2 Service-owned persistence foundation
        |         |
        |         +--> P11-W3 Governed tenant provisioning
        |                    |
        |                    +--> P11-W4 Tier migration
        |
        +--> P11-W5 Provider reassignment

P11-W3 + P11-W4 + P11-W5
        |
        +--> P11-W6 Drift detection and repair
                    |
                    +--> P11-W7 Acceptance and handover
```

- P11-W1 is the mandatory first slice and includes removal of the Phase 10 `TenantC`-specific active provisioning contract.
- P11-W2 must establish service storage ownership before P11-W3 claims full dedicated-tenant provisioning.
- P11-W5 may proceed after P11-W1 because provider capability is independent of database splitting, but final acceptance still requires the service-owned model.
- P11-W4 cannot start until onboarding, migration, reconciliation, and rollback primitives are proven by P11-W3.
- P11-W6 detects against the final expected contract and therefore follows the mutation workflows.
- P11-W7 is evidence and operational acceptance, not a development catch-all.

Each workstream must deliver code, tests, Docker evidence, runbook updates, and architecture-conformance checks together. Documentation-only completion is not accepted for an executable workstream.

## Detailed Test Matrix

### Contract and architecture tests

- reject tenant-code comparisons used to determine tier, database, provider, or workflow behavior;
- reject direct cross-service database references and shared migration ownership;
- reject API startup migration calls;
- reject topology mutation without idempotency key and expected registry version;
- reject evidence serializers that include configured secret values;
- validate service and provider catalog uniqueness and supported-version rules;
- validate workflow `01` through `04` environment, commit, registry-version, and contract-hash handoff.

### Provisioning scenarios

| Scenario | Expected result |
|---|---|
| Add arbitrary shared tenant `Customer-X` | Registry activates only after every shared service-store and assigned-provider contract passes; no dedicated secret is required |
| Add arbitrary dedicated tenant `Customer-Y` | Generic IaC provisions every mandatory service-owned dedicated store; registry activates last |
| Add second and third dedicated tenants | No Bicep, workflow, script, or application edit; independently keyed stores and aliases are produced |
| Deactivate active tenant | Tenant disappears from execution catalogs without deleting its data or contracts |
| Reactivate tenant | Current contract is fully revalidated before activation |
| Missing dedicated store/alias | Operation fails before activation and current tenants remain unaffected |
| Denied deployment identity | Operation reports authorization failure and does not misclassify it as missing configuration |
| Retry with same idempotency key | Existing operation resumes or returns its terminal result; no duplicate resources or activation |

### Tier-transition scenarios

- shared to dedicated with count, key, checksum, and business-invariant reconciliation;
- dedicated to shared with capacity and tenant-isolation validation;
- failure before cutover leaves registry and traffic on source topology;
- failure after activation invokes bounded rollback and retains source data;
- stale registry version prevents cutover;
- concurrent provider and tier operations for the same tenant are rejected or serialized;
- cleanup cannot execute before the rollback deadline and explicit approval.

### Provider scenarios

- assign OpenPay or Razorpay to any active tenant without editing a workflow or script;
- switch each supported provider in both directions and restore the original assignment;
- missing key/webhook contract fails before assignment;
- unsupported provider code fails discovery/contract construction;
- debug override validates the alternate capability but leaves registry assignment unchanged;
- callback, webhook, idempotency, timeout, retry, and reconciliation behavior remains provider-specific but contract-consistent;
- a newly implemented provider cannot enter the registry until its complete capability catalog and validation suite pass.

### Isolation and consistency scenarios

- shared tenants always carry tenant predicates and cannot read or modify another tenant's rows;
- dedicated tenants never fall back to a shared store when their contract is unavailable;
- each service resolves its own store from the same tenant topology snapshot;
- outbox/inbox and integration events preserve tenant, trace, correlation, and causation identifiers;
- no cross-service distributed transaction is introduced;
- reconciliation detects missing, duplicated, or divergent records after data movement.

### Workflow and environment scenarios

- local Docker runs all mutation and rollback cases using disposable data and deterministic providers;
- CI clean-room recreates the expected contract and rejects checked-in/generated stale evidence;
- Azure dev executes `01 -> 02 -> 03 -> 04` with one contract hash;
- Azure staging repeats the complete promotion path with staging identities and secret aliases;
- branch/environment mismatch fails before Azure mutation;
- workflow cancellation and rerun resumes safely from durable operation state;
- production uses approved bounded verification and never depends on sample tenant names.

## Measurable Phase 11 Completion Gates

Phase 11 is complete only when all gates pass independently:

### Architecture conformance

- zero active topology discriminators based on sample tenant code;
- zero cross-service direct database access paths;
- zero API startup migrations;
- all stateful services own a migration bundle, shared-pool contract, and dedicated-store template;
- architecture tests enforce these rules with no undocumented permanent exception.

### Functional acceptance

- a new shared tenant and at least two arbitrary dedicated tenants are onboarded without source or workflow edits;
- both supported providers can be assigned to every test tenant through governed operations;
- both tier transitions and provider rollback pass;
- duplicate/retried operations produce one authoritative result;
- workflows `01` through `04` complete against the same topology contract and all active tenants.

### Data and isolation acceptance

- migration reconciliation reports zero unexplained count, key, checksum, or business-invariant differences;
- shared-tenant isolation and dedicated no-fallback tests pass;
- service-owned persistence and event-driven consistency tests pass;
- source data remains recoverable through the declared rollback window.

### Operational acceptance

- plan, approve, status, resume, rollback, and cleanup procedures are documented and executed;
- drift detection produces actionable non-secret findings and approved repair operations;
- failure injection proves missing configuration, authorization denial, transient failure, stale version, and post-activation rollback classifications;
- each operation emits the required evidence packet with environment, commit, contract hash, registry version, workflow URL, and timestamps;
- no secret value appears in logs or artifacts.

### Deployment readiness

- local Docker and CI are green before Azure;
- Azure dev and staging are green with independent identities and configuration;
- staging evidence and explicit approval exist before production;
- rollback has been executed successfully for the release candidate, not only described.

## Failure And Rollback Rules

- A failure before `ReadyForActivation` must leave current registry topology unchanged.
- A missing secret is a configuration-contract failure, not permission failure, unless Azure returns `Forbidden` or `AuthorizationFailed`.
- A permission failure must not be retried as if it were transient.
- Retry only transient network, throttling, or service-availability failures with a bounded retry budget.
- Never delete the current database, current provider contract, or last known-good evidence during target preparation.
- Post-activation verification failure must automatically stop promotion and invoke the declared rollback or mark the operation for manual intervention.
- Cleanup is a separate approved operation and cannot be an implicit consequence of successful activation.

## Evidence Contract

Every operation writes an immutable packet containing:

```text
operationId
tenantCode
changeType
sourceTopology
targetTopology
databaseContractStatus
serviceContractResults
migrationStatus
identityGrantStatus
providerContractStatus
runtimeValidationStatus
activationVersion
rollbackDeadline
commitSha
workflowRunUrl
timestamps
finalStatus
```

Secret names may be recorded. Secret values, passwords, connection-string credentials, access tokens, and private keys must never be recorded.

## Phase Boundary

Phase 11 owns tenant lifecycle automation, topology reconciliation, service-owned persistence, and workflow-level rollback. Phase 12 owns platform-wide dashboards, alerting, rotation schedules, quotas, noisy-neighbor controls, disaster recovery, private networking, and broader security hardening.
