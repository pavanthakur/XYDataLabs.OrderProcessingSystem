---
applyTo: "frontend/**/*.ts,frontend/**/*.tsx,frontend/**/*.js,frontend/**/*.jsx,frontend/**/*.json"
---
# Frontend Rules — XYDataLabs.OrderProcessingSystem

Use this instruction set for the React workspace under `frontend/`.

## Workspace Boundaries

- Treat `frontend/apps/web` as the web application and `frontend/packages/` as shared client packages.
- Inspect the owning package's `package.json`, TypeScript configuration, Vite configuration, and existing tests before editing.
- Keep API contracts in the API SDK package and reuse the existing client rather than duplicating HTTP calls in pages.
- Do not place backend, database, Azure SDK, or provider-secret logic in the browser.

## Tenant And Runtime Safety

- Resolve the active tenant from API runtime configuration and the approved tenant-session package.
- Do not introduce tenant IDs, provider credentials, or connection strings into UI-local configuration.
- Do not accept `TenantId`, `TenantCode`, or `TenantExternalId` as arbitrary user-controlled API parameters.
- Preserve the backend `X-Tenant-Code` contract and approved headerless endpoints.
- Treat payment-provider selection and payment state as server-owned data; the UI may display state but must not become the routing authority.

## Payment UI Safety

- Never log or persist raw card numbers or CVV, include them in telemetry/reports, or echo them outside approved card-entry controls. Keep screenshots and diagnostic artifacts sanitized.
- Preserve transient card entry in the existing approved payment flow; this rule does not prohibit its input controls or authorize a new collection path. Never store card values in local/session storage. Private keys and payment secrets must never reach the browser.
- Preserve sandbox/live indicators and existing payment callback handling.
- Keep provider-specific behavior behind existing payment-flow or API abstractions.
- Display technical identifiers only when the existing contract marks them as customer-safe.

## Implementation And Validation

- Follow existing React and TypeScript conventions before introducing a new abstraction.
- Add or update focused component tests for changed behavior.
- Run the affected frontend test and typecheck/build commands from the owning package before broader validation.
- Keep API contract changes synchronized with the backend DTO and endpoint change; do not silently widen the client contract.
