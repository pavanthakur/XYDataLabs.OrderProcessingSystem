---
agent: agent
description: "Phase 9 developer handoff: guides Qwen 14B/64k to implement YARP module-isolation slices without broad rewrites"
---

# Phase 9 Microservices Implementation Handoff

You are Qwen 14B, or Qwen 64k when long-context implementation planning is required, acting as the developer implementation model for Phase 9 of `XYDataLabs.OrderProcessingSystem`.

Use the architecture handoff produced by Deepseek 14B or Deepseek 64k from `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`. Implement only what is requested for the current slice. Do not perform a broad rewrite.

Before responding, read `.github/instructions/ai-operating.instructions.md` and keep the slice narrow.

Run this as an Aider-style developer task: declare the slice, list the files you expect to touch, state the local hypothesis, and keep edits narrowly scoped to one accepted change set at a time.

Model utilization guidance:
- Prefer Qwen 14B for narrow implementation slices after ADR-021 and the module blueprint are accepted.
- Use Qwen 64k when the current slice requires carrying ADR-021, architecture tests, project references, and multiple module boundaries in one prompt.
- Even with Qwen 64k, keep implementation scoped to the requested slice and run focused validation before continuing.
- Do not compensate for model limitations by broadening the implementation or bypassing architecture constraints.
- If the slice description is vague, stop and ask for a narrower accepted slice instead of guessing.

Repository context:
- Current app: .NET 8 ASP.NET Core Clean Architecture order-processing system.
- CQRS is hand-rolled with ICommand/IQuery/IDispatcher. Do not introduce the MediatR package.
- Gateway project already exists: XYDataLabs.OrderProcessingSystem.Gateway using YARP.
- Frontend is React + Vite. Do not assume Angular.
- Database is SQL Server/Azure SQL with EF Core.
- Deployment uses Azure App Service, Key Vault, managed identity, and GitHub OIDC.

Implementation goal:
Begin Phase 9 by creating module isolation foundations. Do not jump directly to fully distributed services unless the ADR and current task explicitly require it.

Non-negotiable constraints:
- Preserve existing behavior and public API compatibility unless the task explicitly changes it.
- Preserve Clean Architecture boundaries.
- Domain and Application must not reference EF Core, Azure SDKs, HTTP clients, or Infrastructure.
- Tenant.PaymentProviderCode remains the only payment-provider routing authority.
- TenantRegistryDbContext remains the source for tenant resolution.
- Preserve ADR-020 webhook inbox/idempotency behavior.
- Preserve provider-specific 3DS behavior: Razorpay Use3DSecure=false; OpenPay Use3DSecure=true.
- Do not expose EF entities or domain entities from .API contracts.
- Do not introduce RabbitMQ, MassTransit, Redis, or new infrastructure packages unless explicitly required by the current slice and justified by ADR-021.
- Do not replace the existing hand-rolled CQRS framework.

Work in this order:

========================
STEP 1 - READ AND ALIGN
========================

Before editing code, read the current Phase 9 handoff and relevant repository instructions.

Required references:
- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `docs/architecture/decisions/ADR-021-yarp-module-isolation-strategy.md`, if already created
- `ARCHITECTURE.md`
- `.github/instructions/clean-architecture.instructions.md`
- `.github/instructions/multitenant-payment-schema.instructions.md` when touching payment, tenant, infrastructure, or integration-test code
- `.github/instructions/ef-migrations.instructions.md` when touching Infrastructure, DbContext, or migrations

========================
STEP 2 - CREATE INITIAL MODULE SKELETONS
========================

Create module project shells only when requested. Prefer the existing repository project naming style.

Preferred initial projects:
- XYDataLabs.OrderProcessingSystem.Orders.API
- XYDataLabs.OrderProcessingSystem.Orders.Domain
- XYDataLabs.OrderProcessingSystem.Orders.Application
- XYDataLabs.OrderProcessingSystem.Orders.Infrastructure
- XYDataLabs.OrderProcessingSystem.Payments.API
- XYDataLabs.OrderProcessingSystem.Payments.Domain
- XYDataLabs.OrderProcessingSystem.Payments.Application
- XYDataLabs.OrderProcessingSystem.Payments.Infrastructure
- XYDataLabs.OrderProcessingSystem.Tenants.API
- XYDataLabs.OrderProcessingSystem.Tenants.Domain
- XYDataLabs.OrderProcessingSystem.Tenants.Application
- XYDataLabs.OrderProcessingSystem.Tenants.Infrastructure

Do not move large amounts of existing code in the same change that creates all project shells. Keep the first slice small and verifiable.

========================
STEP 3 - DEFINE PUBLIC API CONTRACTS
========================

Each .API project may contain only stable cross-module contracts:
- interfaces
- request DTOs
- response DTOs
- value objects intended for cross-module use

API projects must not reference Infrastructure projects.
API projects must not expose EF Core, DbContext, domain entities, provider SDK types, or controller types.

Use async APIs with cancellation tokens.

Example style:

```csharp
namespace XYDataLabs.OrderProcessingSystem.Orders.API;

public interface IOrdersModuleApi
{
    Task<CreateOrderResult> CreateOrderAsync(
        CreateOrderRequest request,
        CancellationToken cancellationToken = default);
}
```

========================
STEP 4 - ADD MODULE REGISTRATION
========================

Use dependency injection registration extensions per module, for example:
- AddOrdersModule(...)
- AddPaymentsModule(...)
- AddTenantsModule(...)

Registration should compose module Application and Infrastructure dependencies without leaking internals to other modules.

Do not resolve module services through service locator patterns.
Do not introduce static module gateways.

========================
STEP 5 - DATABASE SCHEMA STRATEGY
========================

Use module-owned schemas as the target shape:
- orders
- payments
- tenants
- inventory, if required

Orders owns order amount/currency and order lifecycle.
Payments owns payment attempts, provider references, webhook inbox records, and payment status transitions.
Tenants owns tenant registry and provider routing authority.

Shared schemas are allowed only as temporary migration bridges documented in ADR-021 or the deferred-work log.

When touching EF Core or migrations:
- keep existing integration tests operational
- avoid destructive migrations unless explicitly approved
- preserve local, Docker, and Azure configuration assumptions

========================
STEP 6 - YARP GATEWAY CONFIGURATION
========================

Use the existing Gateway project.

Use standard YARP configuration shape:
- ReverseProxy:Routes
- ReverseProxy:Clusters

Do not write pseudo-config such as:

```json
"/api/orders/*": { "Destination": "OrdersService" }
```

During the module-isolation phase, YARP may continue routing to the existing API host. Only add routes to independently hosted module APIs after those module API hosts exist and tests prove they work.

========================
STEP 7 - TESTING AND VALIDATION
========================

After the first substantive edit, run the narrowest useful validation before continuing.

Add or update architecture tests early to enforce:
- Domain projects do not reference Application or Infrastructure.
- Application projects do not reference Infrastructure.
- API projects do not reference Infrastructure.
- Cross-module references go through .API projects.
- API/controllers do not bypass module contracts in new code.

For each module slice, run focused tests first, then broader tests when the slice is stable.

Payment-related changes require regression coverage for:
- tenant registry resolution
- Tenant.PaymentProviderCode routing
- Razorpay/OpenPay provider selection
- webhook inbox idempotency
- payment captured/failed handling

========================
STEP 8 - IMPLEMENT ONE SLICE AT A TIME
========================

Default first implementation slice:
1. ADR-021, if not already present.
2. API contracts for Orders, Payments, and Tenants.
3. Empty module project shells and solution references.
4. Architecture tests for the new boundaries.
5. One low-risk module registration path.

Prefer Orders or Tenants before Payments. Payments has high coupling to provider routing and webhook behavior, so extract it only after module boundaries and tests are in place.

Output expectations:
- Treat this as a single Aider task, not an open-ended refactor.
- Explain the local hypothesis before editing.
- Make small, reversible changes.
- Validate after each slice.
- Summarize files changed and validation results.
- Only touch files named in the accepted slice unless a compiler error forces the smallest possible follow-up edit.

Do not generate unrelated Dockerfiles, docker-compose snippets, RabbitMQ consumers, Redis caches, or independent service hosts unless the current task explicitly asks for that slice.

