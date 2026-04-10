# ADR-016: Client-Rendered React SPA For UI Modernization

## Status
Accepted

## Context
The current UI is an ASP.NET Core MVC application in `XYDataLabs.OrderProcessingSystem.UI`.
It still owns user-facing Razor views plus two server-owned endpoints that are required for the
current payment journey:

- `GET /payment/callback` in `HomeController`
- `POST /payment/client-event` in `HomeController`

The architecture roadmap in `ARCHITECTURE-EVOLUTION.md` already freezes Phases 8-14 as backend
evolution work. Extending the MVC host while those phases proceed would deepen the eventual
replacement cost and couple new UX work to a host that is already planned for retirement.

The project also wants a mobile channel, but mobile delivery is not the same concern as removing
the MVC web host. Web replacement is the retirement path for MVC. Mobile is an additional client
that should consume the same API contract after the web contract is stable.

The current runtime model is also important:

- The API already exposes Swagger v1 at `/swagger/v1/swagger.json`
- Tenant context is resolved with `X-Tenant-Code`
- Runtime bootstrap comes from `GET /api/v1/Info/runtime-configuration`
- Entra ID / JWT is not yet part of the active runtime; that work remains a later track

## Decision
The system will adopt a separate client-rendered React frontend under a dedicated `frontend/`
root as part of a parallel UI Modernization Program (`Track U`).

The decision includes these binding rules:

1. React web replaces the current MVC presentation layer.
2. React Native / mobile follows the web contract and is not a gate for backend Phase 8.
3. The UI implementation lives outside `XYDataLabs.OrderProcessingSystem.UI`.
4. The first React cut uses a direct API integration model with no BFF.
5. The migration-window security model stays on the current runtime contract:
   `GET /api/v1/Info/runtime-configuration` for bootstrap plus `X-Tenant-Code` for tenant
   context. Entra ID / JWT remains later work and does not block Track U.
6. `GET /payment/callback` and `POST /payment/client-event` must move to API ownership before
   the MVC application is retired.
7. Phases 8-14 keep their current numbering. Track U does not renumber the backend roadmap.

## Rationale (optional — use for non-obvious choices)
| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| React + Vite SPA in `frontend/` with Track U before backend Phase 8 implementation | Clean separation from retiring MVC host; matches current API-first topology; enables typed client generation from Swagger; keeps payment callbacks on .NET where they belong; allows mobile to follow a stable contract later | Requires an explicit contract audit, temporary dual-run period, and rehoming of MVC-owned endpoints before shutdown | ✅ Selected |
| Next.js / hybrid SSR web stack | Strong routing and server capabilities; good for public SEO-heavy sites | Adds server/runtime complexity that overlaps with existing .NET ownership; no meaningful benefit for this authenticated tenant-scoped app; blurs ownership of payment callback responsibilities | ❌ Rejected |
| Continue evolving ASP.NET Core MVC / Razor | Lowest immediate disruption | Increases migration tax, makes mobile reuse worse, and keeps strategic UI work coupled to a host already targeted for removal | ❌ Rejected |

## Consequences

**Positive:**
- The UI gets a clean deployable boundary without disturbing Phases 8-14.
- React web and mobile can share a typed API SDK and tenant bootstrap model.
- The current API and Swagger surface become the explicit contract for frontend work.
- MVC retirement becomes a planned cutover with hard gates instead of an indefinite coexistence.

**Negative / Trade-offs:**
- The system must run MVC and React web in parallel during migration.
- API contract quality now matters more because frontend generation depends on it.
- The payment callback and browser telemetry paths require deliberate rehoming to API ownership.

**Future obligations:**
- Keep `X-Tenant-Code` as the tenant header until a later auth track formally replaces it.
- Keep Swagger valid enough for generated client consumption.
- Do not merge React implementation code into `XYDataLabs.OrderProcessingSystem.UI`.
- Do not treat mobile completion as a gate for backend Phase 8 or MVC retirement.

## Related
- ADR-007: Hybrid multitenant model
- ADR-011: Hand-rolled CQRS
- `docs/guides/development/api-contract-audit.md`
- `docs/guides/development/ui-modernization-plan.md`