# ADR-025: Phase 10 Network And SKU Boundary

**Status:** Accepted  
**Date:** 2026-07-25

## Context

The broader Azure target includes APIM, private YARP ingress, VNet integration, private endpoints, Service Bus Private Link, Blob/Event Grid, SQL managed identity, and Front Door/WAF. Implementing isolated pieces in Phase 10 would create a topology that looks production-like but cannot enforce the intended private path.

APIM Consumption does not provide the required VNet integration for this design, and Service Bus Standard does not support private endpoints. Service extraction, real consumers, DLQ Functions, identity, delivery safety, and rollback already form a substantial Phase 10 completion boundary.

## Decision

Phase 10 uses:

- YARP as the ingress and policy-enforcement gateway;
- ACA/ACR for independently deployable application workloads;
- Service Bus Standard over its Azure endpoint with Entra ID, managed identity, and scoped RBAC;
- Key Vault for provider and SQL bootstrap secrets;
- existing Azure SQL and Redis connectivity suitable for lower-environment validation;
- Application Insights and Log Analytics for operational proof.

Phase 12 owns one coherent private-platform hardening slice:

- APIM Standard v2 or a then-approved VNet-capable tier;
- private YARP ingress;
- VNet integration, private DNS, and private endpoints;
- Service Bus Premium with Private Link;
- Blob attachments and Event Grid lifecycle processing;
- SQL runtime managed identity;
- Front Door/WAF where justified by the production edge design.

This is a formal rephase, not a removal of scope. The items remain open in the Deferred Work Log until their objective closure triggers pass.

## Alternatives

| Option | Result |
|---|---|
| Complete real services/transport in Phase 10, private platform in Phase 12 | Selected: preserves a coherent testable boundary |
| APIM Consumption in Phase 10 | Rejected: does not satisfy the intended private backend topology |
| Service Bus Standard plus a claimed private endpoint | Rejected: unsupported SKU capability |
| Move all identity/security to Phase 12 | Rejected: Entra JWT, Service Bus RBAC, and Key Vault are mandatory Phase 10 controls |
| Remove APIM/private network work | Rejected: capability remains an explicit roadmap obligation |

## Consequences

Positive:

- Phase 10 can finish real behavior without deploying misleading infrastructure.
- Phase 12 can test edge, network, DNS, broker SKU, and origin lockdown together.
- Current security obligations remain explicit even before private networking.

Trade-offs:

- Phase 10 lower environments use authenticated public Azure service endpoints.
- Production network hardening is incomplete until Phase 12.
- SKU and cost decisions must be revisited with measured workload data.

## Obligations

- Document the Phase 10 lower-environment threat boundary.
- Use Entra/RBAC and disable local/SAS transport auth after proof.
- Keep DW-019 through DW-022 open until Phase 12 evidence satisfies their closure triggers.
- Update this ADR if Azure SKU capabilities or the approved edge topology change.

## Related

- ADR-014: Azure Service Coverage Rationale
- ADR-017: Phase Plan Portability Extensions
- [Architecture Evolution](../../../ARCHITECTURE-EVOLUTION.md)
- [Deferred Work Log](../../internal/DEFERRED-WORK-LOG.md)
- [Phase 10 Implementation Checklist](../../internal/phase10-implementation-checklist.md)
