# ADR-021: Phase 9 Module Isolation Before Service Extraction

**Status:** Accepted

## Context

Phase 9 begins the transition from the current Clean Architecture monolith toward a local YARP-backed microservices architecture. The system now has mature cross-cutting concerns from Phases 7 through 8.7: tenant enforcement, central tenant registry, payment provider routing, outbox/inbox persistence, webhook handling, and operational validation across local, Docker, and Azure paths.

Moving directly from the current solution into separately deployed services would make too many boundaries change at once: project references, runtime hosting, database ownership, gateway routing, observability, and test topology. The riskiest part is not creating another ASP.NET Core host; it is proving that business modules can stop depending on each other's internals while the system still behaves exactly as before.

## Decision

Phase 9 starts with **module isolation before service extraction**.

Orders, Inventory, Notifications, and Payments become first-class modules inside the repository before they become independently deployable services. Each module gets explicit project boundaries and a narrow public contract surface:

- `*.Domain` — module-owned entities, value objects, domain events, and invariants
- `*.Features` — module CQRS commands, queries, handlers, validators, DTOs, and mapping owned by the module
- `*.Infrastructure` — module persistence, adapters, workers, migrations, and registration
- `*.API` — interfaces and contract DTOs that other modules may reference

Modules may reference another module's `*.API` project only. They must not reference another module's `*.Domain`, `*.Features`, or `*.Infrastructure` project.

The first implementation wave keeps one API composition root and one supported local runtime path while enforcing the module boundaries with architecture tests. YARP gateway routing, Aspire-Lite orchestration, and Docker Compose parity are layered on after the module references are clean.

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Module isolation before service extraction | Reduces blast radius, keeps existing validation paths usable, exposes hidden coupling before runtime distribution, lets architecture tests enforce boundaries early | Requires temporary modular-monolith discipline before full service autonomy | ✅ Selected |
| Directly split into multiple API services first | Produces visible microservices quickly and exercises YARP routing early | Mixes code-boundary refactor with runtime, database, deployment, and tracing changes; increases rollback complexity | ❌ Rejected |
| Keep current project structure and only add YARP routes | Low immediate change | Creates a gateway veneer over a coupled monolith; does not prove service-ready boundaries | ❌ Rejected |
| Extract Payments first only | Focuses on the most integration-heavy module | Leaves Orders, Inventory, and Notifications coupling untested and risks payment-specific structure becoming the default pattern | ❌ Rejected |

## Consequences

**Positive:**
- The pre-Phase 9 snapshot remains a reliable recovery point before irreversible project movement.
- Module boundaries can be tested while the current API, database, and payment flows remain available.
- `API` contracts make allowed inter-module communication explicit before distributed calls are introduced.
- Existing tenant, webhook, outbox, and payment semantics carry forward without being rewritten during the first split.

**Negative / Trade-offs:**
- The solution will temporarily contain more projects while still running mostly as a modular monolith.
- Some existing namespaces and test fixtures will move before any user-visible runtime behavior changes.
- EF Core migrations and seed data must be handled carefully while schemas are introduced incrementally.

**Future obligations:**
- Add NetArchTest rules that block cross-module references except through `*.API`.
- Introduce module registration methods such as `AddOrdersModule()`, `AddInventoryModule()`, `AddNotificationsModule()`, and `AddPaymentsModule()`.
- Preserve Docker Compose support while adding Aspire-Lite service discovery and dashboarding.
- Keep YARP as the single local ingress once downstream service discovery is wired.
- Define the next ADR if Phase 9 changes the database ownership model beyond per-module schemas.

## Related

- ADR-008: Architecture Test Guardrails
- ADR-011: Hand-Rolled CQRS
- ADR-018: Blueprint and Snapshot Strategy
- ADR-019: Central Tenant Registry
- ADR-020: Webhook Inbox Idempotency
- [Phase 9 curriculum checklist](../../learning/curriculum/1_MASTER_CURRICULUM.md#day-74-migrate-orders-api-to-aspire)
- [Branch + Blueprint Strategy](../../internal/branch-and-blueprint-strategy.md)
