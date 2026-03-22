---
applyTo: "**/XYDataLabs.OrderProcessingSystem.Domain/Entities/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Application/DTO/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Application/Features/Payments/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Infrastructure/**/*.cs,**/XYDataLabs.OrderProcessingSystem.API/Controllers/**/*.cs,**/XYDataLabs.OrderProcessingSystem.UI/**/*.cshtml,**/XYDataLabs.OrderProcessingSystem.UI/wwwroot/js/**/*.js,**/tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/**/*.cs,**/tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/**/*.cs"
---
# Multitenant Payment Schema Rules — XYDataLabs.OrderProcessingSystem

These rules are binding for all tenant, payment, DTO, migration, middleware, and related test changes.

## Authority
- Root standard: `ARCHITECTURE.md`
- If this file conflicts with older instructions or comments, follow `ARCHITECTURE.md` and the current codebase.

## Tenant model
- Use the three-key tenant pattern only:
  - `Tenant.Id` → internal FK only
  - `Tenant.ExternalId` → external API/webhook/integration key
  - `Tenant.Code` → `X-Tenant-Code`, ops tooling, logs
- `Tenant.Id` must never appear in external DTOs or UI surfaces.
- `Tenants` is a system table, not a tenant-owned table.

## Tenant resolution
- Request header is `X-Tenant-Code`, never `X-Tenant-Id`.
- Missing or unknown tenant code → HTTP 400.
- Resolved `Suspended` or `Decommissioned` tenant → HTTP 403.
- No null tenant context may flow downstream.
- `ITenantProvider` must expose `HasTenantContext`, `TenantId`, `TenantCode`, and `TenantExternalId`.
- The only approved headerless bootstrap path is `GET /api/v1/info/runtime-configuration`.
- UI/browser code must read the active tenant from API runtime configuration, not UI-local configuration.

## Tenant-owned entities
- Tenant-owned entities must inherit from `BaseAuditableEntity` or `BaseAuditableCreateEntity`.
- Do not redeclare `TenantId` on derived entities.
- `TenantId` is `int`, non-nullable, FK-backed.
- Tenant-owned entities must have:
  - FK to `Tenants(Id)`
  - global query filter on `TenantId`
  - explicit tenant-scoped indexes for lookup keys
- `Tenants` and any other non-tenant-owned system tables are excluded from tenant query filters and tenant stamping.

## Payment identifiers
- Use only these names:
  - `CustomerOrderId`
  - `AttemptOrderId`
  - `PaymentTraceId`
- Do not introduce new uses of these ambiguous or legacy names:
  - `OrderId` for payment attempt identity
  - `ReferenceNo`
  - `APINO1`
  - `APINO2`
- Customer-facing DTOs and UI may show `CustomerOrderId`.
- `AttemptOrderId` is provider/callback/technical only.
- `PaymentTraceId` is internal-only and must not appear in customer-facing DTOs or UI.

## EF and migrations
- Current baseline starts from `RebaselineMultitenantPaymentSchema`.
- `TenantA` and `TenantB` must be seeded in the baseline migration `Up()`.
- Every new tenant-owned table migration must include:
  - FK to `Tenants`
  - required tenant-scoped indexes
- After creating any migration, run a drift check with a second migration and confirm it is empty.
- Remove the temporary drift-check migration after verification.

## Non-request operations
- `DbInitializer`, background jobs, test fixtures, and any out-of-band creation flow must pass `TenantId` explicitly.
- Never rely on ambient middleware tenant context in non-request code paths.

## Required test coverage
- Architecture tests must cover:
  - migration drift
  - tenant-scoped index presence
  - tenant filter isolation
  - identifier surface compliance
- Middleware/integration tests must cover:
  - 400 for missing tenant code
  - 400 for unknown tenant code
  - 403 for blocked tenant status
  - per-class tenant isolation
  - no dependency on shared baseline tenant rows