# Phase 9 Architect 1.0 - Repository Intake

Zoo model: `deepseek-r1-14b-32k:latest` or the Zoo architecture/reasoning model.

Mode: read-only architecture. Do not write production code. Do not emit patches.

Use these inputs:

- `repomix-output.xml`
- `ARCHITECTURE.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/local-model-phase-handoff-guide.md`
- Current active-work summary: Phase 9 is YARP Microservices Architecture (Local); module isolation first; service extraction second.

Task:

Produce a repository-aware Phase 9 architecture intake for YARP module isolation.

Hard constraints:

- Do not introduce MediatR. CQRS remains hand-rolled.
- Do not introduce RabbitMQ, MassTransit, Redis, or new infrastructure packages.
- Domain and Application must not reference EF Core, Azure SDKs, HTTP clients, or Infrastructure.
- `Tenant.PaymentProviderCode` remains the only payment-provider routing authority.
- `TenantRegistryDbContext` remains the tenant resolution source.
- Preserve ADR-020 webhook inbox/idempotency behavior.
- Preserve provider behavior: Razorpay `Use3DSecure=false`; OpenPay `Use3DSecure=true`.
- YARP routes host boundaries, not class-library modules.
- Phase 9 starts with module isolation before independent services.

Required output:

1. Bounded contexts and module candidates.
2. Initial module boundary table for Orders, Payments, Tenants, Inventory if present, and SharedKernel/platform concerns.
3. Current coupling risks discovered from the repository context.
4. ADR-021 outline only, not a full ADR yet.
5. First safe implementation slice candidate.
6. Explicit assumptions that need Copilot/repo-owner review.

Stop after architecture output. Do not propose code edits.
