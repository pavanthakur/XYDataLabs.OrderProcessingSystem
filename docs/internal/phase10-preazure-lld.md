# Finalized Phase 10 Pre-Azure LLD

## Purpose

This document is the authoritative pre-Azure architecture baseline for the remainder of Phase 10.

Establish independently executable, locally validated Order Processing services before Azure deployment.

The pre-Azure implementation must prove:

- Clear service, route, schema, and event ownership.
- Dynamic shared-versus-dedicated tenant routing.
- Dynamic payment-provider assignment.
- Durable, idempotent messaging.
- Governed DLQ quarantine and replay.
- Local Keycloak authentication using portable OIDC/JWT.
- Measurable resilience, observability, and rollback.
- Repeatable Docker Compose and clean-runner validation.

Completion of this plan authorizes Azure validation. It does not complete Phase 10 by itself. Completion remains subject to successful execution of the L0-L6 gates and their evidence requirements.

## Assumptions

- Docker Compose remains the canonical local runtime.
- Visual Studio and VS Code remain supported debugging environments.
- Existing public API behavior remains backward compatible.
- Existing databases and the hybrid tenant model remain in Phase 10.
- The Tenant Registry remains the runtime source of truth.
- Keycloak is local-only; Entra ID remains the Azure production identity provider.
- The current NFR harness is retained but rerun after architectural changes.
- Physical per-service databases and independent migration histories remain Phase 11.

## Out Of Scope

Pre-Azure execution excludes:

- Azure deployment and runtime testing.
- ACA revision validation.
- Real Azure Service Bus validation.
- Key Vault and managed identity runtime proof.
- APIM and private ingress.
- VNet integration and private endpoints.
- Geo-replication and AKS.
- Physical database-per-service separation.
- Independent per-service EF migration histories.
- Blob/Event Grid and Front Door/WAF.

Managed Identity, Key Vault, Azure Service Bus, and ACA remain part of the final Azure portion of Phase 10. Phase 12 deferrals remain governed by ADR-025.

## Target Topology

```text
                         React UI
                            |
                          YARP
                            |
        +-------------------+--------------------+
        |                   |                    |
      Orders             Payments           Inventory
        |                   |                    |
        +-------------------+--------------------+
                            |
                       Notifications

Orders Outbox
     |
order-events topic
     |
     +------ Inventory subscription
     |
     +------ Notifications subscription
     |
     +------ Orders payment-state subscription

Consumer failure
     |
order-events-dlq / dlq-intake
     |
DLQ Intake Function
     |
operations.DlqQuarantineRecords
     |
Operator Approval HTTP Function
     |
Replay Request Outbox
     |
dlq-replay-requests queue
     |
Replay Function
     |
Original topic

Database Migrator
     |
     +------ Tenant Registry
     +------ Shared tenant database
     +------ Discovered dedicated databases
```

## Dependency Model

`A -> B` means A references B:

```text
Host -> API
Host -> Infrastructure
Host -> ServiceDefaults

API -> Features
API -> Contracts, when separately required

Infrastructure -> Features abstractions
Infrastructure -> Domain

Features -> Domain
Features -> Contracts, when required

Domain -> SharedKernel primitives only
Contracts -> no application layer
ServiceDefaults -> platform libraries only
```

Rules:

- Host is the composition root.
- API contains controllers and transport mapping.
- API and Infrastructure must not reference each other.
- Infrastructure implements inward-facing abstractions.
- Domain remains technology-independent.
- Module Infrastructure projects cannot reference each other.
- Cross-context communication uses published APIs or integration events.
- A separate Contracts project is introduced only when independent distribution or versioning justifies it.

## Ownership Model

### Service And Route Ownership

| Capability | Owner |
|---|---|
| Info, Customer, Order, Audit | Orders |
| Tenant bootstrap/read operations | Orders using Tenant Registry abstraction |
| Payments and reconciliation | Payments |
| Provider callbacks and webhooks | Payments |
| Inventory and Product | Inventory |
| Notifications | Notifications |
| DLQ intake and replay | Functions/Operations |
| DLQ approval endpoint | Operations HTTP Function |
| Browser application | UI |
| Ingress and route policy | Gateway |

Every published route must resolve to exactly one owner.

### Tenant Registry Ownership

The Tenant Registry is owned by the Platform/Operations control plane.

Services may:

- Query tenant identity, status, tier, and provider assignment.
- Resolve the correct shared or dedicated database.

Services must not:

- Modify tenant topology directly.
- Hardcode tier or provider fallback values.
- Treat TenantA/B/C arrangements as architectural constants.

Registry changes occur only through:

- Approved migrator operations.
- Controlled administrative tooling.
- Audited operational workflows.

### Schema Ownership

| Schema | Owner |
|---|---|
| `orders` | Orders |
| `payments` | Payments |
| `inventory` | Inventory |
| `notifications` | Notifications |
| `operations` | DLQ quarantine, approval, and replay |
| Tenant Registry database/schema | Platform/Operations |

No new cross-schema runtime access is permitted.

Existing runtime cross-schema dependencies must be recorded as temporary exceptions and eliminated before L6.

## ServiceDefaults Boundary

`ServiceDefaults` is a domain-agnostic platform library.

It may provide:

- OpenTelemetry.
- Logging enrichment.
- Health checks.
- Problem details.
- Service discovery.
- HTTP resilience defaults.
- Authentication configuration helpers.
- Configuration validation.

It must not contain:

- Business policies.
- Controllers.
- Module routing.
- DbContexts or repositories.
- Tenant routing decisions.
- Payment-provider resolution.
- Event handlers.
- Module-specific feature flags.

## Architecture Invariants

Maintain a governed catalog containing rule, rationale, enforcement, exceptions, and removal milestone.

| ID | Invariant | Rationale | Enforcement | Exceptions | Removal milestone |
|---|---|---|---|---|---|
| A-001 | Hosts do not reference the monolithic API | Prevents hidden coupling during service extraction | Architecture test | Temporary allowlist only while a host is being cut over | L1.5 |
| A-002 | Module Infrastructure projects do not reference each other | Preserves service autonomy | Architecture test | Temporary allowlist only for proven transitional wiring | L1.1-L1.5 |
| A-003 | ServiceDefaults remains domain-agnostic | Keeps shared platform code from becoming a back door for business logic | Dependency and content test | None after cross-cutting L1 controls are in place | L1.5 |
| A-004 | Application startup performs zero DDL | Keeps deployment-time and runtime responsibilities separate | Startup SQL observation | Temporary exception only until the migrator is in place | L1.5 |
| A-005 | Runtime code performs no cross-context table access | Prevents accidental shared-schema dependence | Architecture and integration tests | Temporary exception manifest only for known legacy dependencies | L6 |
| A-006 | Tenant Registry is the only tier/provider authority | Avoids hardcoded tenant routing and drift | Architecture and behavior tests | None for new code | L1.5 |
| A-007 | Events have one owner and governed versions | Preserves event compatibility and schema evolution | Contract tests | Additive-only changes on known versions | L2 |
| A-008 | Every route has exactly one service owner | Prevents ambiguous routing and shadowing | Gateway topology test | None after route ownership matrix is approved | L1.5 |
| A-009 | Gateway and downstream services enforce authorization | Keeps auth boundaries explicit | Security integration tests | None for production paths | L4 |
| A-010 | Trace and correlation context crosses every boundary | Makes distributed diagnosis possible | Distributed trace test | None for production paths | L5 |
| A-011 | Logs and evidence contain no secrets or raw tokens | Prevents credential leakage in proof artifacts | Artifact scan | None for evidence packets | L5-L6 |

Existing violations use a temporary allowlist containing:

- Owner.
- Reason.
- Location.
- Replacement design.
- Removal milestone.

New violations fail immediately. Relevant allowlists must be empty by L6.

## Implementation Milestones

### L0: Baseline Stabilization

- Commit current validated Phase 10 changes.
- Exclude generated test output.
- Capture commit SHA and image digests.
- Export current dependency and route graphs.
- Characterize existing public APIs and events.
- Preserve current working Docker image tags.
- Record existing architectural violations.

Done when:

- Repository builds and tests pass.
- Current behavior is protected by characterization tests.
- Rollback baseline is recorded.

Effort: 0.5-1 day.

### L0.5: Architecture Baseline Gate

Produce and approve:

- Context map.
- Project dependency graph.
- Route ownership matrix.
- Schema ownership matrix.
- Event ownership matrix.
- Deployment topology.
- Architecture invariant catalog.
- Temporary exception manifest.
- Rollback plan.
- ADR amendments.

ADR handling:

| Decision | Governance |
|---|---|
| Tenant Registry authority | ADR-019 |
| Module isolation | ADR-021 amendment |
| Service-host model | ADR-022 amendment |
| Delivery and versioning semantics | ADR-023 amendment |
| DLQ approval and replay | ADR-024 amendment |
| Network/SKU deferrals | ADR-025 |
| Deployment-time migration ownership | New ADR-026 |

Effort: 0.5-1 day.

### L1.1: Orders Real Service

- Replace compatibility-owned Orders behavior with real module handlers, repositories, and SQL persistence.
- Keep Orders authoritative for order amount, currency, status, and payment context.
- Keep tenant bootstrap and registry-backed tenant resolution behind the Orders-owned abstraction rather than controller filtering.
- Make Orders executable and buildable without hidden dependence on unrelated service outputs.
- Preserve external route compatibility while moving business ownership into the Orders module.

Done when:

- Orders runs independently and passes `/health/alive` and `/health/ready`.
- No hardcoded order, customer, tenant, or success-path responses remain in the validated Orders path.
- Persisted order state is authoritative for amount, currency, and lifecycle status.
- Shared-versus-dedicated tenant routing is registry-driven rather than hardcoded.

### L1.2: Payments Real Host

- Run Payments as an executable ASP.NET Core host on its owned port and route surface.
- Own payment initiation, callbacks, client events, reconciliation entry points, and provider webhooks.
- Obtain payment context from Orders using an internal contract rather than trusting browser-provided commercial values.
- Resolve provider assignment from the Tenant Registry at execution time and persist payment attempts with authoritative order/provider references.
- Publish payment result events that Orders can consume without direct cross-context table access.

Authoritative payment flow:

```text
UI creates order
 -> Orders persists authoritative amount/currency
 -> UI requests payment using OrderReferenceId
 -> Payments obtains Orders payment context
 -> Payments resolves provider from registry
 -> Payments persists attempt
 -> provider
 -> callback/webhook
 -> Payments publishes payment result
 -> Orders updates order state
```

Recommended internal contract:

```http
GET /internal/v1/orders/{orderReferenceId}/payment-context
```

It returns:

- Tenant identity.
- Authoritative amount and currency.
- Current order state.
- Order version/concurrency token.

The browser must not be authoritative for amount, currency, tenant tier, or provider.

Done when:

- Payments runs independently and passes readiness.
- Persisted amount, currency, and provider requests match Orders-owned payment context.
- Provider assignment is discovered dynamically from the registry.
- Callback and webhook processing are idempotent.
- Payment success and failure reach Orders through published events.

### L1.3: Inventory Real Service

- Replace compatibility-owned Inventory behavior with real API handlers and persistence behavior.
- Keep reservation creation module-owned rather than hidden inside generic shared infrastructure writes.
- Ensure Inventory resolves tenant context before tenant database access and persists through its owned schema objects.
- Make Inventory independently buildable and runnable without the monolithic API host.

Done when:

- Inventory runs independently and passes readiness.
- Inventory reservations are produced only through Inventory-owned handlers.
- Duplicate downstream delivery remains idempotent.
- Shared-versus-dedicated tenant routing resolves correctly from the registry.

### L1.4: Notifications Real Service

- Replace compatibility-owned Notifications behavior with real API handlers and persistence behavior.
- Keep notification-delivery creation module-owned rather than hidden inside generic shared infrastructure writes.
- Ensure Notifications resolves tenant context before tenant database access and persists through its owned schema objects.
- Make Notifications independently buildable and runnable without the monolithic API host.

Done when:

- Notifications runs independently and passes readiness.
- Notification deliveries are produced only through Notifications-owned handlers.
- Duplicate downstream delivery remains idempotent.
- Shared-versus-dedicated tenant routing resolves correctly from the registry.

### L1.5: Gateway And Route Ownership Cutover

- Add explicit service routes before fallback routes.
- Remove compatibility routes as each service passes its cutover proof.
- Prove direct-host and gateway contracts for Orders, Payments, Inventory, and Notifications.
- Enforce that every published route resolves to one service owner only.
- Remove host references to `XYDataLabs.OrderProcessingSystem.API` so ownership is no longer enforced through shared controller filtering.

Done when:

- Every route resolves to exactly one service owner.
- No compatibility endpoint is invoked in the validated path.
- Fallback routes cannot shadow service-specific routes.
- Zero service hosts depend on the monolithic API for route ownership.
- Clean image builds do not require unrelated service outputs.

#### Cross-Cutting L1 Controls

Finalize these controls during L1.1-L1.5 rather than treating them as optional later work:

- Finalize `ServiceDefaults` as a domain-agnostic platform library.
- Move shared telemetry, health, configuration validation, and resilience registration into common technical defaults only.
- Standardize `/health/alive` and `/health/ready` across service hosts.
- Create and integrate the one-shot migrator:

```text
Registry migration
 -> discover active tenants
 -> migrate shared database once
 -> migrate each dedicated database once
 -> apply idempotent local seed
```

Rollout order:

1. Implement and test migrator behavior.
2. Integrate it with Docker Compose.
3. Integrate it with Visual Studio and VS Code startup.
4. Integrate it with CI.
5. Disable application startup migrations.
6. Enforce invariant A-004.

Done when:

- Every host uses common technical defaults without domain or persistence leakage through `ServiceDefaults`.
- Services start only after migrator success.
- Application startup performs zero DDL.
- Repeated migration execution is safe.
- Schema failure blocks readiness and promotion.

Combined L1 effort: 5-8 days.

### L2: Durable Messaging

#### Event Ownership

Orders owns `OrderCreatedV1`.

Payments owns:

- `PaymentAttemptSucceededV1`.
- `PaymentAttemptFailedV1`.

Versioning rules:

- V1 changes are additive only.
- Existing fields cannot change meaning or units.
- Optional fields cannot become required.
- Consumers ignore unknown fields.
- Fields cannot be reused for different semantics.
- Breaking changes require a new event version.
- Representative payloads remain under version control.
- Old versions require an explicit retirement process.

#### Consumer Model

```text
Inventory.Host
 -> inventory subscription
 -> inventory.ConsumerInboxMessages
 -> inventory.InventoryReservations

Notifications.Host
 -> notifications subscription
 -> notifications.ConsumerInboxMessages
 -> notifications.NotificationDeliveries

Orders.Host
 -> payment-state subscription
 -> orders.ConsumerInboxMessages
 -> order payment-state transition
```

Exact inbox uniqueness:

```text
(TenantId, ConsumerName, MessageId)
```

Processing sequence:

1. Validate envelope and event version.
2. Validate tenant metadata.
3. Resolve tenant through the registry.
4. Open the selected tenant database.
5. Insert/check module-owned inbox.
6. Apply the business effect.
7. Commit SQL transaction.
8. Complete broker message.

Failure policy:

- Transient dependency failure: abandon/retry.
- Malformed contract: dead-letter.
- Unsupported event/version: dead-letter.
- Unknown or unauthorized tenant: dead-letter.
- Business-policy rejection: dead-letter with classified reason.

Done when:

- One order produces one Inventory and one Notification effect.
- Payment result produces one Orders transition.
- Duplicates produce no duplicate business effect.
- Restart resumes pending processing.
- Shared/dedicated tenant routing is correct.
- Permanent failure reaches DLQ intake.
- Correlation links order, outbox, broker, inbox, and effect.

Effort: 3-4 days.

### L3: DLQ And Functions

#### Entities

```text
order-events-dlq / dlq-intake
dlq-replay-requests queue
```

#### Workflow

```text
Consumer dead-letter
 -> Intake Function
 -> quarantine record

Operator approval
 -> POST /api/v1/admin/dlq/{id}/approve
 -> approval + replay outbox atomically
 -> replay queue
 -> Replay Function
 -> original topic
```

State model:

```text
Quarantined -> Approved -> ReplayPending -> Replayed
Quarantined -> Rejected
ReplayPending -> ReplayFailed -> Quarantined
```

Controls:

- Application-controlled settlement.
- `AutoCompleteMessages = false`.
- Unique active replay request by `QuarantineId`.
- Replay disabled by default.
- Maximum five replay attempts.
- Repeated approval returns existing approval.
- Poison, malformed, expired, and invalid-tenant messages remain quarantined.
- Disabled replay does not lose approval.
- Original message content and identifiers are preserved.

Audit fields:

- Actor.
- Timestamp.
- Previous/new state.
- Reason.
- Replay attempt.
- Message, tenant, trace, and correlation identifiers.

Done when:

- Intake and replay triggers are independently discoverable.
- Quarantine is idempotent.
- Repeated approval creates one replay command.
- Approved transient failure produces one downstream effect.
- Kill switch and replay ceiling pass.
- Logs connect Function invocation through downstream effect.

Effort: 3-4 days.

### L4: Portable Identity

#### Local Flow

```text
React Authorization Code + PKCE
 -> Keycloak
 -> JWT
 -> Gateway JwtBearer validation
 -> tenant consistency
 -> downstream JwtBearer validation
 -> authorization policy
```

Policies:

| Policy | Requirement |
|---|---|
| Authenticated user | Valid issuer, audience, lifetime, and signature |
| Tenant access | Token tenant claim matches requested tenant |
| Operator | `phase10-operator` |
| Internal service | Approved client identity and audience |
| Webhook | Anonymous authentication plus valid provider signature |

Security requirements:

- Automatic JWKS key rollover.
- Small bounded clock skew.
- No raw tokens or secrets in logs.
- Stable OIDC subject used instead of email.
- Downstream services cannot be bypassed through direct access.
- Entra and managed identity branches remain compile/configuration-tested before Azure.

Done when:

- UI PKCE authentication passes.
- Missing token returns `401`.
- Invalid audience, expiry, or tenant returns `403`.
- Normal users cannot approve replay.
- Operators can approve replay.
- Webhooks remain signature-protected.
- Direct service calls enforce the same policies.

Effort: 3-5 days.

## Resilience Policy

| Dependency | Required policy |
|---|---|
| SQL | Bounded transient retry through EF execution strategy |
| Redis | Short timeout; cache failure cannot corrupt authoritative state |
| Internal HTTP GET | Timeout plus bounded exponential retry with jitter |
| Internal mutation | Retry only with idempotency key |
| Payment provider | Timeout and circuit breaker; no blind POST retries |
| Service Bus consumer | Broker redelivery; complete only after SQL commit |
| Outbox | Exponential retry and observable next-attempt time |
| Replay | Kill switch and maximum five attempts |

Required transport limits:

- Message payload: maximum 256 KB.
- TTL: 7 days.
- Broker delivery count: maximum 10.
- Replay attempts: maximum 5.
- No global ordering assumption.

## Observability Contract

Every applicable request, message, and background operation carries:

```text
TraceId
SpanId
CorrelationId
CausationId
TenantId
TenantCode
MessageId
OrderReferenceId
PaymentReferenceId
UserSubject
OperationName
ServiceName
ServiceVersion
Environment
```

These values are added through shared telemetry enrichment and logging scopes.

Required distributed traces:

- UI -> Gateway -> Orders -> SQL/outbox.
- Outbox -> Service Bus -> Inventory.
- Outbox -> Service Bus -> Notifications.
- Payments -> provider -> callback/webhook -> Orders.
- DLQ -> Intake -> Approval -> Replay -> Consumer.

## L5: Operational Readiness

Run independent evidence categories.

| Category | Proof |
|---|---|
| Functional | Duplicate, restart, outage, quarantine, approval, and replay |
| Performance | 100-message burst and latency targets |
| Operational | Kill switches, heartbeat, diagnostics, and artifact quality |
| Recovery | Previous image rollback without database loss |
| Tenant | Dynamic shared/dedicated routing |
| Payments | Dynamic provider reassignment and restoration |
| Security | Authentication, authorization, and webhook boundaries |

Targets:

- Zero lost committed messages.
- Zero duplicate business effects.
- Consumer P95 below 30 seconds.
- Approved replay visible within 60 seconds.
- Operational recovery within 30 minutes.
- No failed category hidden by aggregate status.

The existing passing NFR proof is harness validation. Final evidence must be regenerated after L1-L4.

Effort: 1-2 days plus remediation.

## L6: Final Pre-Azure Acceptance

### Gate A: Architecture Conformance

- Actual dependency graph matches the target.
- Route and schema ownership matrices match implementation.
- Temporary exception lists are empty for pre-Azure invariants.
- No compatibility endpoint is invoked.
- No startup DDL occurs.
- No runtime cross-context database access occurs.
- ServiceDefaults remains domain-agnostic.

### Gate B: Operational Readiness

- Functional proof passes.
- NFR targets pass.
- DLQ/replay passes.
- Identity passes.
- Rollback passes.
- Required traces are present.
- Logs identify service, tenant, provider, message, and stage.

### Gate C: Deployment Readiness

- Clean restore/build/test passes.
- Compose configuration passes.
- Migrator succeeds from a clean database.
- Every image builds independently.
- Full Docker stack passes.
- Playwright smoke passes.
- Dynamic payment matrix passes.
- Workflow `99` passes on a clean runner.
- Commit SHA and image digests match evidence.

All three gates are mandatory and cannot compensate for one another.

## Payment Matrix

- Discover active tenants from the registry.
- Discover current tier and provider before every journey.
- Exercise every discovered tenant against every enabled provider through controlled reassignment.
- Restore the original provider in `finally`.
- Use deterministic providers in automated local and CI runs.
- Keep OpenPay/Razorpay sandbox proof as a separate manual local gate.

Current expected seed coverage:

```text
3 tenants × 2 providers = 6 journeys
```

Each journey proves:

- Correct shared/dedicated database.
- Registry-driven provider.
- Authoritative amount and currency.
- Durable order and payment records.
- Idempotent callback/webhook.
- Expected order state.
- Inventory reservation.
- Notification acceptance.
- End-to-end correlation.
- Provider restoration.

Limits:

- Five minutes per journey.
- Thirty minutes for the matrix.

## Rollout And Rollback

Use one reviewable commit or PR boundary per sub-slice:

1. L0 baseline.
2. L0.5 architecture artifacts and ADR updates.
3. L1.1 Orders real service.
4. L1.2 Payments real host.
5. L1.3 Inventory real service.
6. L1.4 Notifications real service.
7. L1.5 gateway and route ownership cutover.
8. L2 messaging.
9. L3 Functions/DLQ.
10. L4 identity.
11. L5 proof.
12. L6 acceptance.

Controls:

- Keep the previous image tag until L6 passes.
- Use route fallback only during the affected L1 migration.
- Final L6 permits no compatibility fallback.
- Use expand/contract database changes.
- Never delete the last known-good image or database volume after failure.
- Keep publication, each consumer, and replay independently disableable.
- Capture the exact rollback command and result.

## Evidence

Each milestone creates immediately:

```text
run-plan.txt
progress.log
current-step.txt
summary.json
latest-run pointer
failure pointer
```

Final evidence includes:

- Commit SHA.
- Docker image digests.
- Dependency and route reports.
- Architecture invariant results.
- TRX/JUnit reports.
- SQL state.
- Broker, quarantine, and replay identifiers.
- Function invocation identifiers.
- NFR summary.
- Playwright failure traces.
- Rollback command and result.
- Known exceptions and approved waivers.

## Effort And Azure Entry

Estimated hands-on effort:

```text
14-23 engineering days
```

Expected elapsed duration with review and remediation:

```text
3-5 calendar weeks
```

Rebaseline after L0.5 if dependency or data-access discovery materially changes the scope.

Azure validation may begin only when:

- L0-L6 have passed.
- Architecture, operational, and deployment gates are independently green.
- Workflow `99` reproduces the result on a clean runner.
- Evidence references one commit SHA and matching image digests.
- No critical risk, compatibility fallback, or undocumented exception remains.

This LLD provides the architectural baseline for pre-Azure Phase 10 implementation. Completion remains subject to successful execution of the L0-L6 gates and their evidence requirements.
