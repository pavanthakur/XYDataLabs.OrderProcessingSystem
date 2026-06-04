# Application

Hand-rolled CQRS — no MediatR. No infrastructure imports. No EF Core.

## CQRS abstractions (`Abstractions/CQRS/`)

`ICommand<TResult>`, `IQuery<TResult>`, `ICommandHandler<,>`, `IQueryHandler<,>`, `IDispatcher`

## Pipeline behaviours

Located in `Behaviors/` — validation, logging, and transaction wrapping applied cross-cutting to all handlers.

## Features

| Feature | Commands | Queries |
|---------|----------|---------|
| **Orders** | `CreateOrderCommand` | `GetOrderDetailsQuery` |
| **Customers** | (create/manage) | (list/get) |
| **Payments** | `ProcessPaymentCommand`, `ConfirmPaymentStatusCommand` | payment status queries |

### Payment command flow

1. `ProcessPaymentCommand` → handler resolves provider via `Tenant.PaymentProviderCode` → delegates to keyed `IPaymentProviderGateway`
2. `PaymentProviderCustomerActionException` → maps to `PaymentAttemptStatus.Failed` (terminal, no retry)
3. All other unhandled exceptions → `UnknownNeedsReconciliation`
4. `ConfirmPaymentStatusCommand` → webhook/callback reconciliation; caps persisted text to column limits

## DTOs

`Application/DTO/` — all API-facing contracts. Mapped in `Mappings/` (manual mapping, no AutoMapper).

## Rules

- No `IConfiguration` injection — use `IOptions<T>` strongly typed settings.
- No direct `DbContext` access — all data access through repository/service interfaces defined here, implemented in Infrastructure.
- All payment identifier fields must use canonical names: `CustomerOrderId`, `AttemptOrderId`, `PaymentTraceId` (see ARCHITECTURE.md §4 for banned aliases).
