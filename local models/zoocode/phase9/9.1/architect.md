# Phase 9.1 Architect

Scope: smallest possible proof slice for Phase 9.

Task:
- Define the first tiny Phase 9 change set.
- Keep the model at `qwen2.5-coder:7b`.
- Keep context at `4096`.
- Do not request the whole repo.

Output:
- One concise plan.
- One implementation slice.
- One stop condition.

This slice should prefer boundary enforcement and architecture-test proof only.

## Initial Module Candidates

1. **Orders**
   - Responsibility: Handle order-related operations.
   - Owned Entities/Data: `Order`, `OrderProduct`.
   - Public API Contracts: `IOrdersService` (Create, Update, Get).
   - Internal APIs: None.
   - Commands/Queries: `CreateOrderCommand`, `UpdateOrderQuery`.
   - Events Published: `OrderCreatedEvent`, `OrderUpdatedEvent`.
   - Dependencies Allowed: `Orders.PublicApi`.

2. **Payments**
   - Responsibility: Handle payment-related operations.
   - Owned Entities/Data: `PaymentAttempt`, `CardTransaction`.
   - Public API Contracts: `IPaymentsService` (ProcessPayment, GetStatus).
   - Internal APIs: None.
   - Commands/Queries: `ProcessPaymentCommand`, `GetPaymentStatusQuery`.
   - Events Published: `PaymentAttemptSucceededEvent`, `PaymentAttemptFailedEvent`.
   - Dependencies Allowed: `Payments.PublicApi`.

3. **Tenants**
   - Responsibility: Handle tenant-related operations.
   - Owned Entities/Data: `Tenant`.
   - Public API Contracts: `ITenantsService` (Get, Update).
   - Internal APIs: None.
   - Commands/Queries: `GetTenantQuery`, `UpdateTenantCommand`.
   - Events Published: `TenantUpdatedEvent`.
   - Dependencies Allowed: `Tenants.PublicApi`.

## Initial Module Boundaries

- **Orders**: Owns order-related entities and services. Communicates with `Payments` via public API contracts.
- **Payments**: Owns payment-related entities and services. Communicates with `Orders` via public API contracts.
- **Tenants**: Owns tenant-related entities and services. No external communication required.

## Stop Condition

The initial phase will stop once the following is achieved:
1. The `Orders`, `Payments`, and `Tenants` modules are defined with their respective bounded contexts, owned entities, and public API contracts.
2. Architecture tests are added to ensure that the module boundaries are enforced correctly.
3. The first implementation slice for the `Orders` module is completed.

This initial phase will focus on boundary enforcement and architecture-test proof only, ensuring a solid foundation for future microservices extraction.
