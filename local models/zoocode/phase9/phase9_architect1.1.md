# Phase 9 Architect 1.1 - Architecture Correction Gate

Zoo model: `qwen2.5-coder:7b` by default; escalate to `deepseek-r1:8b` only if Qwen output is insufficient for architecture trade-offs.

Mode: read-only architecture review. Do not write production code. Do not emit patches.

Input:

- Output from `phase9_architect1.0.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/local-model-phase-handoff-guide.md`
- `ARCHITECTURE.md`

Task:

Review and correct the Architect 1.0 output against repository constraints.

Review gates:

- Clean Architecture boundaries remain intact.
- CQRS remains hand-rolled; no MediatR package is introduced.
- `Tenant.PaymentProviderCode` remains the only payment-provider routing authority.
- `TenantRegistryDbContext` remains the tenant resolution source.
- ADR-020 webhook inbox/idempotency behavior remains intact.
- Orders own order amount/currency during the target module boundary.
- Payments own payment attempts, provider references, webhook inbox behavior, and payment status transitions.
- Tenants own tenant registry and provider routing authority.
- YARP routes host boundaries, not class-library modules.
- Module isolation comes before service extraction.
- No RabbitMQ, Redis, MassTransit, or broad infrastructure changes are introduced without ADR approval.

Required output:

1. Corrected architecture decision summary.
2. ADR-021-ready decision points.
3. Accepted first development slice.
4. Files the first development slice may touch.
5. Narrow validation command for the first development slice.
6. Rejected ideas and why they are unsafe for this repository.

Stop after the correction gate. Development may start only after Copilot/repo-owner acceptance.
