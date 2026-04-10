# API Contract Audit For UI Modernization

Canonical contract audit for replacing the MVC web host with React web and later adding a mobile
client on the same API surface.

## Purpose

This document freezes the current frontend-facing contract before any React implementation begins.
It exists to stop speculative frontend structure work and force the migration to be based on the
real API and MVC surface that exists today.

## Frozen Decisions For Track U

1. React web replaces the current MVC presentation layer.
2. React Native / mobile follows the web contract and is not the gate for MVC retirement.
3. Backend Phase 8 starts after Track U Phase U2 is complete.
4. During Track U, the runtime security model stays on the current platform contract:
   `GET /api/v1/Info/runtime-configuration` plus `X-Tenant-Code`. Entra ID / JWT is not part of
   this migration window.
5. `GET /payment/callback` and `POST /payment/client-event` must move to API ownership before
   MVC can be retired.
6. The first React cut preserves the existing v1 API routes. Route normalization is a later,
   versioned API concern.

## Current API Inventory

### Bootstrap And Operational Endpoints

| Route | Consumer | Purpose | Track U decision |
|------|----------|---------|------------------|
| `GET /api/v1/Info/environment` | Diagnostics, local verification | Returns environment/runtime info | Keep as API-owned operational endpoint |
| `GET /api/v1/Info/runtime-configuration` | MVC today, React web later, mobile later | Returns active tenant bootstrap and runtime flags | Make this the canonical bootstrap contract for React web and mobile |
| `GET /health` | Ops | Liveness | No Track U change |
| `GET /health/live` | Ops | Liveness | No Track U change |
| `GET /health/ready` | Ops, deployment probes | Readiness | No Track U change |

### Customer And Order Endpoints

| Route | Current consumer | Purpose | React impact |
|------|------------------|---------|--------------|
| `GET /api/v1/Customer/GetAllCustomers` | MVC JavaScript / future React | Customer list | Keep for first cut; consider REST cleanup only in a later API version |
| `GET /api/v1/Customer/GetAllCustomersByName` | MVC JavaScript / future React | Search + pagination | Keep for first cut |
| `GET /api/v1/Customer/{id}` | MVC JavaScript / future React | Customer detail with orders | Keep for first cut |
| `POST /api/v1/Customer` | API consumers | Create customer | Keep |
| `PUT /api/v1/Customer/{id}` | API consumers | Update customer | Keep |
| `DELETE /api/v1/Customer/{id}` | API consumers | Delete customer | Keep |
| `POST /api/v1/Order` | MVC JavaScript / future React | Create order | Keep |
| `GET /api/v1/Order/{id}` | MVC JavaScript / future React | Order detail | Keep |

### Payment And Audit Endpoints

| Route | Current consumer | Purpose | React impact |
|------|------------------|---------|--------------|
| `POST /api/v1/Payments/ProcessPayment` | MVC payment UI / future React | Customer + card + charge in one request | Keep in first cut; strongly typed SDK required |
| `POST /api/v1/Payments/{paymentId}/confirm-status` | Payment callback handling path | Confirms payment status after callback data is received | Keep; React should not own this server responsibility |
| `GET /api/v1/Audit/{entityName}/{entityId}` | Admin / diagnostics | Audit history | Keep |

## Current MVC-Owned Surface

The MVC host still owns the following browser-facing responsibilities:

| Route / asset | Current owner | Role | Required outcome |
|--------------|---------------|------|------------------|
| `GET /` | `HomeController.Index()` | Home page and browser bootstrap | Replace with React web shell |
| `GET /payment/callback` | `HomeController.PaymentCallback()` | Browser redirect target for payment callback / 3DS flow | Rehome to API ownership before MVC shutdown |
| `POST /payment/client-event` | `HomeController.LogPaymentClientEvent()` | Browser-originated payment telemetry | Rehome to API ownership before MVC shutdown |
| `Views/Home/Index.cshtml` | MVC | Main UI surface | Replace with React web route tree |
| `Views/Home/PaymentCallback.cshtml` | MVC | Callback rendering surface | Replace with API-owned callback handling plus React-facing status UX |
| `Views/Home/_Layout.cshtml` | MVC | Shared web shell layout | Replace with React app shell |

## Contract Risks That Must Be Closed In Track U1

### 1. Generated client quality

The React clients should consume a generated TypeScript SDK produced from:

- `/swagger/v1/swagger.json`

Recommendation:

- Generate `frontend/packages/api-sdk` from the v1 Swagger spec
- Validate the generated output before scaffolding deeper frontend packages
- Keep the generated SDK versioned with the API contract

### 2. Envelope handling

The API uses `ApiResponse<T>` envelopes. The frontend plan must decide one of two approaches and
freeze it before implementation expands:

1. Generated SDK returns the raw envelope and React callers unwrap it explicitly.
2. A thin handwritten wrapper package unwraps successful responses and centralizes error handling.

The second approach is preferable if the envelope appears on most business endpoints.

### 3. Route style inconsistency

The current API mixes resource routes with verb-style action names:

- `/api/v1/Customer/GetAllCustomers`
- `/api/v1/Payments/ProcessPayment`

Track U will preserve these routes for the first React cut to avoid backend churn before Phase 8.
Route normalization is deferred to a later versioned API decision.

### 4. Callback and telemetry ownership

The MVC host still owns the payment callback and client telemetry routes. Those routes are not
frontend concerns. They are server concerns and must move to API ownership before MVC retirement.

### 5. Local development model

The React web dev server will introduce a new local runtime path. Before Track U2 starts, the
implementation plan must document:

- how the React dev server reaches the API locally
- how `X-Tenant-Code` is injected in browser requests
- how CORS is handled during local development

## Required Outcome For React Web

Before React web is considered a valid MVC replacement, it must be able to do all of the
following without any dependency on Razor views:

1. Bootstrap from `GET /api/v1/Info/runtime-configuration`
2. Resolve and send `X-Tenant-Code` on browser API requests
3. Read customers and orders through the current v1 endpoints
4. Initiate payment through `POST /api/v1/Payments/ProcessPayment`
5. Consume payment status outcomes without MVC-owned callback rendering

## Track U1 Exit Criteria

Track U1 is complete only when all of the following are true:

1. ADR-016 is accepted.
2. This audit is approved as the canonical frontend contract baseline.
3. The migration-window auth model is frozen as `runtime-configuration` + `X-Tenant-Code`.
4. The generated SDK approach for `/swagger/v1/swagger.json` is chosen.
5. The API ownership plan for payment callback and browser telemetry is frozen.
6. The React web scaffold has not started yet; this document is the gate for Track U2.