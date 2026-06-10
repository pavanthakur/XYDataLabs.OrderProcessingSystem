# Phase 9 Architect 2.0 - Module Boundary Blueprint

Zoo model: `deepseek-r1-14b-32k:latest` or the Zoo architecture/reasoning model.

Mode: read-only architecture blueprint. Do not write production code. Do not emit patches.

Input:

- Accepted output from `phase9_architect1.1.md`
- `repomix-output.xml`
- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md`

Task:

Produce the concrete Phase 9 module boundary blueprint for developer execution.

Required output:

1. Project map using repository naming style:
   - `XYDataLabs.OrderProcessingSystem.Orders.PublicApi`
   - `XYDataLabs.OrderProcessingSystem.Orders.Domain`
   - `XYDataLabs.OrderProcessingSystem.Orders.Application`
   - `XYDataLabs.OrderProcessingSystem.Orders.Infrastructure`
   - `XYDataLabs.OrderProcessingSystem.Payments.PublicApi`
   - `XYDataLabs.OrderProcessingSystem.Payments.Domain`
   - `XYDataLabs.OrderProcessingSystem.Payments.Application`
   - `XYDataLabs.OrderProcessingSystem.Payments.Infrastructure`
   - `XYDataLabs.OrderProcessingSystem.Tenants.PublicApi`
   - `XYDataLabs.OrderProcessingSystem.Tenants.Domain`
   - `XYDataLabs.OrderProcessingSystem.Tenants.Application`
   - `XYDataLabs.OrderProcessingSystem.Tenants.Infrastructure`
2. Allowed project references.
3. PublicApi interface names and DTO names.
4. Module registration pattern, including `AddOrdersModule()`, `AddPaymentsModule()`, and `AddTenantsModule()`.
5. Owned schema strategy: `orders`, `payments`, `tenants`, and inventory only if represented by current domain evidence.
6. YARP role for current module isolation and later hosted-service routing.
7. Architecture tests to add early.
8. Slice-by-slice implementation sequence with validation command per slice.
9. Risks requiring stakeholder validation before Payments extraction.

Stop after the blueprint. Do not generate code.
