# UI Modernization Plan

Canonical implementation-prep plan for complete retirement of the ASP.NET Core MVC web host and
its replacement with React web first, followed by a mobile client on the same contract.

## Objective

Replace the current MVC presentation layer with React web, remove MVC from the deployment and
runtime path before backend Phase 8 begins, and then add React Native / mobile on top of the
stabilized API contract as a later workstream.

This plan does **not** renumber backend Phases 8-14. It creates a parallel UI Modernization
Program (`Track U`) that runs before backend Phase 8 implementation begins.

## Scope Boundaries

### In scope

- React web replacement for the current MVC UI
- API contract freeze for browser and mobile consumers
- Rehoming MVC-owned server endpoints to the API
- MVC shutdown and deployment removal
- React Native / mobile enablement after the web cutover is complete

### Out of scope

- Entra ID / JWT rollout during the migration window
- A BFF in the first implementation cut
- Backend Phase 8 event-foundation implementation work until React web replacement and MVC retirement are complete
- Route normalization of the existing v1 API surface

## Initial Code Layout

The new UI implementation lives under a dedicated root:

```text
frontend/
  apps/
    web/
    mobile/
  packages/
    api-sdk/
    tenant-session/
```

Only these packages are justified at scaffold time. The following are explicitly deferred until
there is implementation evidence that they are needed:

- `design-system`
- `forms-validation`
- `observability`
- `config`

## Phase Plan

### Phase U1 — Contract Freeze And Migration Rules

**Goal:** Freeze the architecture and contract assumptions before any frontend scaffold begins.

**Deliverables:**

- ADR-016 accepted
- `api-contract-audit.md` approved
- migration-window auth model frozen as `runtime-configuration` + `X-Tenant-Code`
- payment callback and browser telemetry ownership frozen as API responsibilities

**Exit criteria:**

1. The React migration is based on the audited contract, not assumptions.
2. The team agrees that mobile is not the gate for MVC retirement.
3. Backend Phase 8 remains untouched until U5 is complete.

### Phase U2 — React Web Foundation

**Goal:** Stand up the new frontend platform without changing the current production UI.

**Deliverables:**

- `frontend/` workspace scaffolded
- `apps/web` created with React + TypeScript
- `packages/api-sdk` generated from `/swagger/v1/swagger.json`
- `packages/tenant-session` created to own runtime bootstrap and `X-Tenant-Code` handling
- local development flow documented for browser -> API connectivity
- React web shell can bootstrap from `GET /api/v1/Info/runtime-configuration`

**Exit criteria:**

1. React web can load its shell and call the API successfully.
2. Tenant bootstrap and header injection work without MVC.
3. The team can proceed to U3 feature migration without changing backend Phase 8 scope.

**Gate opened by U2:**

- U3 feature-slice replacement may begin once the React web foundation is proven.

### Phase U3 — React Web Feature Replacement

**Goal:** Replace the existing MVC user journeys one slice at a time.

**Recommended slice order:**

1. Runtime bootstrap and home/dashboard shell
2. Customer list and search
3. Customer detail and order visibility
4. Order creation and order detail
5. Payment initiation UX

**Rules:**

- Replace by feature slice, not by shared-component gold-plating
- Keep the current v1 API routes for the first cut
- Do not build mobile in parallel with unresolved web contracts

**Exit criteria:**

1. All currently supported MVC user journeys have React web equivalents.
2. No active browser journey still depends on a Razor view.
3. The only remaining MVC responsibility is server-owned callback/telemetry behavior awaiting cutover.

### Phase U4 — Rehome MVC-Owned Server Endpoints

**Goal:** Remove the last server responsibilities from the MVC host.

**Required rehoming work:**

1. Move `GET /payment/callback` to API ownership.
2. Move `POST /payment/client-event` to API ownership.
3. Preserve payment-provider callback compatibility during cutover.
4. Update frontend behavior so payment status UX no longer depends on MVC callback views.

**Hard rule:**

Neither payment callback handling nor browser payment telemetry may move into React. They remain
server-owned responsibilities and must be owned by the API.

**Exit criteria:**

1. Payment provider callback points to an API-owned endpoint.
2. Browser telemetry posts to an API-owned endpoint.
3. No production request path requires `HomeController`.

### Phase U5 — MVC Cutover And Removal

**Goal:** Remove MVC from the active runtime and deployment path.

**Deliverables:**

- React web becomes the primary user-facing web application
- MVC deployment is disabled
- MVC routes and Razor views are removed from the active system design
- deployment, validation, and operational docs stop referring to MVC as the current UI

**Operational rule:**

The current `XYDataLabs.OrderProcessingSystem.UI` deployment remains alive until U4 is complete.
After cutover, the MVC host is removed from the active deployment model. The existing UI hosting
resource may be repurposed for the React web deployment, but React code must not be merged back
into the MVC project.

**Exit criteria:**

1. No user traffic depends on MVC.
2. No deployment workflow treats the MVC app as the active frontend.
3. The solution no longer treats Razor views as the presentation layer.

### Phase U6 — React Native / Mobile Enablement

**Goal:** Add mobile on the stable contract created by U1-U5 after the web cutover is complete.

**Deliverables:**

- `apps/mobile` scaffolded
- mobile reuses `packages/api-sdk` and `packages/tenant-session`
- mobile consumes the same runtime bootstrap and tenant model as web
- mobile implements only flows proven stable on the web contract first

**Rules:**

- Mobile is not a prerequisite for MVC retirement.
- Mobile is not part of the pre-Phase-8 gate.
- Mobile does not get its own contract fork without an explicit ADR.
- If mobile needs materially different API payloads, the change is owned as a backend contract
  decision, not a frontend shortcut.

**Exit criteria:**

1. Mobile consumes the same canonical API contract as web.
2. No backend contract drift exists between web and mobile clients.

## Complete MVC Removal Checklist

MVC is not considered retired until every item below is true:

1. React web owns all end-user browser routes previously served by Razor views.
2. `HomeController.Index()` is no longer required.
3. `HomeController.PaymentCallback()` has an API-owned replacement in service.
4. `HomeController.LogPaymentClientEvent()` has an API-owned replacement in service.
5. No deployment workflow treats `XYDataLabs.OrderProcessingSystem.UI` as the active frontend.
6. Documentation status surfaces no longer describe MVC as the active UI.
7. Mobile, if present, is treated as an additional client and not as a hidden dependency for web cutover.
8. Backend Phase 8 does not begin until U5 is complete.

## Dependency And Gate Summary

| Gate | Requirement | Opens |
|------|-------------|-------|
| G1 | U1 complete | U2 frontend scaffold |
| G2 | U2 complete | U3 feature replacement |
| G3 | U3 and U4 complete | U5 MVC cutover |
| G4 | U5 complete | Backend Phase 8 implementation |
| G5 | U5 complete | Mobile enablement on stable contract |

## Canonical References

- `docs/architecture/decisions/ADR-016-client-rendered-react-spa.md`
- `docs/guides/development/api-contract-audit.md`
- `ARCHITECTURE-EVOLUTION.md`