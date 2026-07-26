# ADR-022: ACA Service Host Model

**Status:** Accepted  
**Date:** 2026-07-25

## Context

Phase 9 established module boundaries before service extraction. Phase 10 must now replace compatibility stubs with real independently deployable workloads without adopting an orchestration platform whose operational cost exceeds the current needs.

The repository already targets Azure Container Apps (ACA), ACR, YARP, Bicep, and GitHub Actions. Kubernetes-level control is not currently required, but a gateway veneer over hardcoded or health-only service hosts would not constitute service extraction.

## Decision

Phase 10 uses ACA as the workload hosting platform and keeps AKS out of scope.

Orders, Payments, Inventory, Notifications, Gateway, and UI are independently runnable and independently versioned service hosts. Background workers may run with their owning service when lifecycle and scaling requirements match; otherwise they receive a separate ACA workload. Azure Functions owns only serverless trigger workloads explicitly assigned to it.

Each workload must:

- execute its module-owned handlers and persistence rather than return hardcoded compatibility data;
- expose liveness and dependency-aware readiness endpoints;
- publish an immutable commit-SHA image;
- have explicit configuration, identity, scaling, logs, and rollback ownership;
- remain reachable through the governed YARP route rather than through accidental public endpoints.

Payments must have an executable host. Inventory and Notifications must have real consumer behavior and observable effects. Database-per-service remains a Phase 11 concern; Phase 10 preserves the current shared/dedicated tenant database model while enforcing module ownership.

## Alternatives

| Option | Result |
|---|---|
| ACA with independently deployable hosts | Selected: sufficient isolation and scaling with lower operational overhead |
| AKS | Rejected for Phase 10: no current requirement justifies cluster operations, ingress, node, and policy complexity |
| One API host behind YARP | Rejected: does not prove deployment or runtime boundaries |
| Stub service containers | Rejected: proves image routing only, not business extraction |

## Consequences

Positive:

- Service extraction is measured by real behavior and deployment independence.
- ACA revisions and immutable images provide a practical rollback model.
- The platform can add AKS later only if a concrete capability requires it.

Trade-offs:

- Phase 10 must migrate real handlers and data wiring before it can close.
- Shared database infrastructure remains temporarily coupled until Phase 11.
- Service-specific pipelines and operational ownership must be maintained.

## Obligations

- Complete Phase 10.2 characterization and service migration.
- Include Payments in Compose, ACR, ACA, YARP, health checks, and acceptance tests.
- Retain previous healthy ACA revisions and record rollback evidence.
- Create a new ADR before introducing AKS.

## Related

- ADR-021: Phase 9 Module Isolation Before Service Extraction
- ADR-023: Service Bus Delivery Semantics
- [Phase 10 Implementation Checklist](../../internal/phase10-implementation-checklist.md)

