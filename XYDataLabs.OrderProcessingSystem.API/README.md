# API

Thin transitional ASP.NET Core host for Phase 10 cutover. It keeps shared middleware and composition in one place while importing module-owned controllers from the standalone API projects. No business logic belongs here.

## Controllers

| Controller | Routes | Purpose |
|------------|--------|---------|
| `DlqAdminController` | `POST /api/v1/admin/dlq/{quarantineId}/approve` | Transitional HTTP surface for replay approval until the dedicated operations Function surface fully owns the path |

Module-owned controllers are imported from:

- `XYDataLabs.OrderProcessingSystem.Orders.API`
- `XYDataLabs.OrderProcessingSystem.Inventory.API`
- `XYDataLabs.OrderProcessingSystem.Notifications.API`
- `XYDataLabs.OrderProcessingSystem.Payments.API`

## Composition root

`Program.cs` wires: Serilog, EF Core, `IDispatcher`, tenant resolution, payment provider wiring, module migrators, imported module controller assemblies, and health checks.

## Health checks

- `/health` — liveness
- `/health/ready` — readiness + DB; degraded/unhealthy → HTTP 503

## Ports (local VS launch)

- HTTP: `5010`
- HTTPS: `5011`

## Rules

- Controllers dispatch via `IDispatcher` only — no direct service calls or EF access.
- Tenant context is resolved before handlers run from the tenant header contract used by the active runtime profile.
- Standalone module API projects own their routes; this host imports them during the Phase 10 transition and must not regain duplicate controller implementations.
- Swagger enabled in all environments (learning project convention).
