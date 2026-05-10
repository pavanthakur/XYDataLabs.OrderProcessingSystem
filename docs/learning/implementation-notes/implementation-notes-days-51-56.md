# Implementation Notes - Azure Curriculum Days 51-56

Purpose: Detailed execution evidence for the completed Phase 8 event-foundation slices.
These notes supplement the checklist-level summaries in `../curriculum/1_MASTER_CURRICULUM.md`.

Created: 05/10/2026 | Covers: Day 51, Day 55, Day 56

---

## Scope

This note covers the in-monolith event foundation closeout only:

- event contracts and mapper rules frozen above Infrastructure
- transactional outbox and inbox persistence verified
- deterministic `PaymentAttempt` recovery lifecycle verified
- tenant-scoped background worker execution verified
- explicit Phase 8 closeout tests added for replay, reconciliation, and parallel dispatch

The Azure Functions and Service Bus preparation slices in Days 44-50 remain separate curriculum work and were not pulled into the Phase 8 runtime path.

---

## Day 51: Event Contracts, Envelope, And Mapping

Verified implementation shape:

- `IDomainEvent`, `IIntegrationEvent`, `EventEnvelope`, `IEventHandler<T>`, `IEventPublisher`, and `IIdempotencyGuard` live in Application.
- `DeliveryFailureCategory` remains frozen above Infrastructure.
- The mapper rule remains: Domain raises events, Application maps them, Infrastructure persists mapped integration envelopes.
- The registration strategy stays assembly-scanned through the CQRS registration path so the contract remains above Infrastructure.

Result: the event contract layer is frozen in the intended Clean Architecture boundary and remained stable through Phase 8 closeout.

---

## Day 55: Separate Background Workers

Implemented and verified runtime shape:

- `OutboxPublisherWorker` and `PaymentReconciliationWorker` remain separate hosted services.
- Both workers now establish tenant-scoped context explicitly for non-request execution.
- The runtime continues to honor the Phase 8 rule that transport remains in-process; no Service Bus publisher or receiver was introduced into production code.

Important design note:

- Phase 8 did not require a separate worker executable. The workers were kept as hosted services in the existing runtime, which matches the in-monolith constraint while preserving operational separation.

---

## Day 56: Outbox, Inbox, And Payment Recovery Closeout

Closeout evidence now in place:

- `PaymentAttempt` is persisted before provider execution.
- `AttemptOrderId` is deterministic and derived from the customer order plus attempt number.
- The five-state lifecycle is exercised: `PendingProviderCall`, `ProviderAccepted`, `Succeeded`, `Failed`, and `UnknownNeedsReconciliation`.
- Callback reconciliation updates persisted payment attempts instead of leaving the recovery model as schema-only scaffolding.
- Outbox publishing and inbox deduplication execute under tenant-aware persistence.

Additional targeted evidence added during closeout:

- explicit parallel-dispatch integration test proving handlers run independently
- explicit outbox replay integration test proving pending rows replay after restart
- strengthened reconciliation integration test proving `UnknownNeedsReconciliation` resolves to a final domain state

---

## Verification Commands

The following commands were rerun successfully during Phase 8 closeout verification:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~ParallelEventDispatchIntegrationTests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~OutboxPublisherWorkerIntegrationTests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~PaymentReconciliationWorkerIntegrationTests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests
node scripts/validate-doc-links.js
```

Observed result:

- Integration suite: 41 passed
- Architecture suite: 39 passed
- Docs link validation: passed

Result: Phase 8 closeout is now backed by the explicit test bar defined in `ARCHITECTURE-EVOLUTION.md`, and backend Phase 8.5 is the next active engineering phase.

## Docker Integration And UI Matrix Validation

To prove Docker compatibility across all supported targets locally:

```powershell
.\scripts\generate-docker-validation-bundle.ps1 -Environment all -Profile all
```

Observed result:

- Integration suite: 41 passed
- Automation UI matrix: passed across `docker-dev-http`, `docker-dev-https`, `docker-stg-http`, `docker-stg-https`, `docker-prod-http`, and `docker-prod-https`
- Overall outcome: passed

This satisfies the mandatory Phase 8 closeout quality gate from `ARCHITECTURE-EVOLUTION.md`.

## May 10, 2026: Roadmap Extension And Blueprint Alignment

Today's closeout work did not add runtime code; it tightened the architecture plan that follows the verified Phase 8 baseline.

**1. Strategic roadmap extensions adopted**

- Added **Phase 8.7** for a Stripe webhook receiver with signature validation, Inbox-backed idempotency, tenant resolution from provider metadata, and Outbox-driven downstream events
- Added **Phase 9.5** for a local Keycloak portability showcase proving the JWT/auth pipeline can swap authorities without disturbing the Entra ID production path
- Added **Phase 11.5** for a Notifications-only PostgreSQL pilot, preserving Azure SQL as the production baseline for revenue-critical paths while demonstrating RDBMS portability

**2. Blueprint review outcome**

Reviewed Julio Casal's `.NET 10 backend blueprint` reference template and adopted the following as planned modernization work inside existing phases:

- Phase 9: introduce a shared `ServiceDefaults` project for OpenTelemetry, health checks, service discovery, and resilient `HttpClient` defaults
- Phase 9: standardize `MapDefaultEndpoints()` for `/health/ready` and `/health/alive`
- Phase 9 / 9.5: move JWT scheme wiring behind `IConfigureNamedOptions<JwtBearerOptions>` to support multi-scheme authority selection cleanly
- Phase 9 or later cleanup: confirm the .NET 8+ `IExceptionHandler` + `AddProblemDetails` path is the single exception contract
- Phase 11.5: use EF Core `UseAsyncSeeding` where reference-data seeding remains necessary across provider changes

**3. Deliberate non-adoptions**

- Do not replace Clean Architecture with the blueprint's single-project vertical-slice layout
- Do not replace Entra ID with Keycloak in production
- Do not replace Azure SQL platform-wide with PostgreSQL
- Do not collapse the split GitHub Actions workflow model into the blueprint's simpler single-workflow delivery path

**4. What this enables next**

The next engineering phase is still **Phase 8.5**. The practical benefit of today's planning work is that Stripe adapter work can now start against a stable target sequence: adapter integration first, webhook receiver second, module extraction third, then identity and persistence portability proofs in isolated follow-on phases.
