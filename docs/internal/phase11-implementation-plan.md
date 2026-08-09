# Phase 11 Implementation Plan

## Purpose

Phase 11 turns tenant topology changes and service data ownership into governed operations. It prevents registry state from advertising a dedicated database or payment provider before the corresponding infrastructure, secret, migration, identity, and runtime contracts are ready.

This document is the execution companion to the Phase 11 roadmap in `ARCHITECTURE-EVOLUTION.md`.

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

## Phase 11 Execution Slices

### 11.1 Topology Contract Foundation

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

### 11.2 Governed Tenant Provisioning

Implement the topology operation state machine and use this ordering for a new dedicated tenant:

1. Create an inactive registry record or separate pending operation; do not expose it to execution catalogs.
2. Preflight the operator/workflow identity capabilities needed to provision databases, write/read secret contracts, run migrations, and grant runtime identities. Classify authorization failure separately from missing configuration.
3. Provision the dedicated database from generic IaC inputs.
4. Run the approved migration bundle.
5. Seed only tenant-owned baseline/reference data.
6. Create `DedicatedTenantConnectionStrings--{TenantCode}` in Key Vault or the environment-equivalent secret store.
7. Grant required service managed identities access to the database.
8. Provision and validate `PaymentProviders--{TenantCode}--{ProviderCode}--PrivateKey` and webhook contracts.
9. Run database, secret, identity, provider, and runtime preflight checks.
10. Write a non-secret topology evidence packet.
11. Activate the tenant in one concurrency-checked registry update.
12. Run post-activation smoke and business verification.

Shared-tenant onboarding follows the same flow but validates the shared database contract and must not create or require a dedicated connection secret.

For the service-owned target model, database preparation through identity grant executes for every stateful service in the governed service catalog. Each service reports an independent result, and activation requires all mandatory results to pass.

**Exit gate:** adding a shared or dedicated tenant requires configuration and an approved operation, not code or workflow edits.

### 11.3 Tier Migration Workflows

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

### 11.4 Provider Reassignment

1. Keep the existing registry assignment active.
2. Provision the target provider key and webhook contracts.
3. Validate provider support, credentials, callback URLs, currency, and deterministic adapter behavior.
4. Run a targeted preflight without changing topology truth.
5. Update the registry provider assignment last using optimistic concurrency.
6. Run provider-specific smoke and idempotency verification.
7. Retain the old provider secret during an approved overlap/rollback window.
8. Remove the old contract only after reconciliation confirms no pending attempts depend on it.

Debug overrides may execute another validated provider path, but must not modify registry truth or bypass contract validation.

**Exit gate:** provider reassignment requires no script edit and can be rolled back without losing payment correlation or reconciliation state.

### 11.5 Drift Detection And Repair

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

### 11.6 Service-Owned Persistence

- Split Orders, Payments, Inventory, and Notifications persistence and migrations by service ownership.
- Preserve tenant topology semantics independently for each service-owned store.
- Give each stateful service one shared-tenant pool and a parameterized dedicated-store contract for dedicated tenants.
- Drive required store creation from the governed service catalog so adding a service or dedicated tenant cannot silently omit a persistence contract.
- Prohibit cross-service direct database access and cross-service joins.
- Use integration events and local projections for cross-service consistency.
- Make provisioning and tier migration fan out through service-specific database contracts without weakening the tenant-level activation gate.

**Exit gate:** each service can migrate, deploy, and recover its data independently while the tenant operation reports one aggregate contract status.

### 11.7 Acceptance And Operational Handover

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
