# API

Thin ASP.NET Core Web API — controllers, composition root, Swagger, middleware wiring. No business logic.

## Controllers

| Controller | Routes | Purpose |
|------------|--------|---------|
| `OrderController` | `POST /api/orders`, `GET /api/orders/{id}` | Order creation and retrieval |
| `CustomersController` | `/api/customers` | Customer management |
| `ProductController` | `/api/products` | Product catalogue |
| `PaymentsController` | `POST /api/payments` | Initiate payment (dispatches `ProcessPaymentCommand`) |
| `PaymentCallbackController` | `POST /api/payments/callback` | Provider webhook/callback receiver (dispatches `ConfirmPaymentStatusCommand`) |
| `AuditController` | `/api/audit` | Audit log queries |
| `InfoController` | `/api/info` | Health, environment info |

## Composition root

`Program.cs` wires: Serilog, EF Core, `IDispatcher`, `IPaymentProviderGateway` (keyed DI by `PaymentProviderTypes`), tenant middleware, `DbInitializer`, health checks (`/health`, `/health/ready`).

## Health checks

- `/health` — liveness
- `/health/ready` — readiness + DB; degraded/unhealthy → HTTP 503

## Ports (local VS launch)

- HTTP: `5010`
- HTTPS: `5011`

## Rules

- Controllers dispatch via `IDispatcher` only — no direct service calls or EF access.
- Tenant context is resolved by `TenantMiddleware` before handlers run — `X-Tenant-Id` header.
- Swagger enabled in all environments (learning project convention).
