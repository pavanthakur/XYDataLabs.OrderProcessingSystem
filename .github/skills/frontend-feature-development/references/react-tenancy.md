# React Tenancy Reference

Use this reference for tenant-aware React and TypeScript changes in `frontend/`.

## Source Of Truth

- The backend runtime configuration endpoint and approved tenant-session flow provide the active tenant context.
- The browser must not invent tenant IDs, resolve provider routing, or replace the backend tenant registry.
- Keep tenant context handling in the existing `frontend/packages/tenant-session` package and reuse the API SDK.

## Change Rules

- Preserve the `X-Tenant-Code` contract and approved headerless endpoint list.
- Do not add tenant identifiers to arbitrary request DTOs or URL parameters when the backend resolves them from context.
- Do not place tenant connection strings, provider credentials, or Key Vault values in frontend code or build-time public configuration.
- Ensure tenant changes clear or reload tenant-scoped data so information from a previous tenant cannot remain visible.
- Treat payment provider and payment status values received from the API as server-owned data.

## Test Expectations

For tenant-aware UI changes, cover the relevant combination of:

- Runtime configuration loading.
- Tenant session selection or restoration.
- API request tenant header behavior.
- Loading, unknown-tenant, unauthorized, and failure states.
- Clearing tenant-scoped state when the active tenant changes.
- Payment callback or status rendering without exposing internal tenant identifiers.
