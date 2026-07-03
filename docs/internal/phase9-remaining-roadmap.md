# Phase 9 Remaining Roadmap

This roadmap captures the remaining concrete Phase 9 closure work and the verified Phase 9.5 identity-portability lane. Aspire-specific consolidation items are split out where they belong.

## Current Readout

- Phase 9 module extraction, split-module boundaries, and Docker/local task wiring are in place.
- Local Keycloak portability wiring for Phase 9.5 is implemented in the repo and runtime-verified in local HTTP and Docker Dev HTTP.
- The remaining Phase 9 items are only the deferred `SharedContracts` decision and any cleanup that stays within the existing split-module proof.
- Phase 9.5 has no active implementation work left beyond keeping it local-only and not promoting Keycloak into Azure production.

### Label Rules

- **Complete** means the item is already verified and should not be treated as a blocker.
- **Planned** means the item is still intended work for a later phase or follow-up lane.
- **Deferred** means the item is intentionally out of scope for this phase and should stay separate until explicitly revisited.
- **Assessment** means the item needs evidence or a gate decision before implementation moves forward.

## Phase 9 Closure Lane

| Item | Status | Done When |
|---|---|---|
| 9.35 Module boundary cleanup | Complete | Orders, Inventory, Notifications, and Payments are isolated by contract; cross-module use goes through `API`; architecture tests catch leaks. |
| 9.36 Gateway boundary proof | Complete | Supported host/path patterns pass; invalid host/path/header combinations fail; gateway boundary tests stay green. |
| 9.37 Shared host consolidation | Complete | Health checks, OpenTelemetry, service discovery, and HttpClient resilience are standardized through `ServiceDefaults` without changing Docker Compose behavior. |
| 9.39 Traced multi-service flow proof | Complete | A single request preserves correlation metadata end to end and the proof repeats reliably. |
| 9.40 Final acceptance matrix | Complete | The matrix states complete/partial/open items and ties each one to a concrete command or test. |
| SharedContracts decision | Deferred | Keep out of Phase 9 unless a later phase truly needs it. |
| Any new service-contract refactor | Deferred | Do not reopen Phase 9 boundaries for cloud/event integration. |

### SharedContracts Implementation Plan

If Phase 10 transport work shows that the same event or DTO shape is being copied across multiple services, introduce a thin `SharedContracts` project as a versioned package with only the shared integration contracts.

Use it only for:
- cross-service event schemas that genuinely need a stable shared shape
- versioned message contracts consumed by more than one service
- minimal common envelope metadata that would otherwise drift between services

Do not use it for:
- service-specific request/response models
- domain entities
- gateway-only DTOs
- anything that weakens module boundaries

Implementation order:
1. Keep Phase 9 clean and do not add new contract refactors there.
2. During Phase 10, add `SharedContracts` only if transport/workflow code proves real duplication.
3. Keep the package tiny and versioned, with services depending on it one way only.
4. Revisit Phase 11 only if saga orchestration or service autonomy shows a stronger need.

### SharedContracts Checklist

| Item | Status | Done When |
|---|---|---|
| Phase 10 duplication check | Next | Transport/workflow code has confirmed that the same event/DTO shape is being duplicated across multiple services. |
| SharedContracts project shape | Deferred | The package is thin, versioned, and contains only shared integration-event DTOs and envelope types. |
| Service dependency direction | Deferred | Services depend on contracts, never the other way around. |
| Scope guardrails | Deferred | The package contains no domain entities, service-specific request/response models, or gateway-only DTOs. |
| Phase 11 revisit gate | Deferred | Orchestration or service autonomy proves a stronger need later. |

### Phase 10 Kickoff Pointer

The file-by-file Phase 10 implementation checklist now lives in
[docs/internal/phase10-implementation-checklist.md](./phase10-implementation-checklist.md).

Use that checklist as the single detailed source for the first transport slice. Keep the phase order transport-first:
- `Orders` emits the `OrderCreatedV1` integration event.
- `Service Bus` carries the durable handoff.
- `Inventory` and `Notifications` consume the downstream event.
- `SharedContracts` stays deferred unless the transport slice proves real duplication across services.

### Current Exit Criteria

- Phase 9.5 remains verified and closed.
- Phase 9.5 stays local-only; no Azure-side Keycloak parity or migration test belongs here.
- Phase 13 Aspire work remains separate from the Phase 9 blocker list.
- The Phase 9 closeout matrix and roadmap stay aligned with the compact lane above.
- Any Azure-side Keycloak parity or migration test, if ever needed, belongs in deferred-work tracking and must not be added to the numbered roadmap.

### Validation Rule

- Local HTTP and Docker dev HTTP matrix dry-runs stay green and resolve the same active tenant/provider set.
- The numbered VS Code task flow stays in sync with the current labels:
  - Local HTTP 01 through 05
  - Docker Dev HTTP 01 through 05
- The run pointers stay under `TestResults\Playwright\local-http\` and `TestResults\Playwright\docker-http\` respectively.
- The shared live sequence log remains the canonical manual-tracing artifact:
  - `TestResults\Playwright\local-http\sequence-summary.log`
  - `TestResults\Playwright\docker-http\sequence-summary.log`

### Tracked Run Order

| Lane | Purpose | Steps |
|---|---|---|
| Local Phase 10 quick loop | Fast developer validation | `01 Wait Ready + Keycloak`, `02 Playwright Smoke` |
| Docker Dev HTTP full validation | Full Phase 10 verification | `01 Wait Ready + Keycloak`, `02 Playwright Smoke`, `03 Integration Suite`, `04 Payment Matrix`, `05 Full Validation` |

1. Local HTTP: `1 Run: Local HTTP 01 Env Ready`
2. Local HTTP: `1 Run: Local HTTP 02 Playwright Smoke`
3. Local HTTP: `1 Run: Local HTTP 03 Matrix Sanity (1 Tenant, Local HTTP)`
4. Local HTTP: `1 Run: Local HTTP 04 Integration Suite (Local SQL, No Docker)`
5. Local HTTP: `1 Run: Local HTTP 05 Full Validation (All Tenants + Providers, Local HTTP)`
6. Docker Dev HTTP: `1 Run: Docker Dev HTTP 01 Wait Ready + Keycloak`
7. Docker Dev HTTP: `1 Run: Docker Dev HTTP 02 Playwright Smoke`
8. Docker Dev HTTP: `1 Run: Docker Dev HTTP 03 Integration Suite`
9. Docker Dev HTTP: `1 Run: Docker Dev HTTP 04 Payment Matrix`
10. Docker Dev HTTP: `1 Run: Docker Dev HTTP 05 Full Validation`

## Phase 13 Aspire Consolidation

### 13.1 - Inner-Loop Orchestration Proof

Goal:
- Finalize `AppHost` as the Aspire inner-loop orchestrator while keeping Docker Compose as the strict baseline.

Done when:
- Aspire can launch the same service graph as Docker Compose.
- Docker remains the supported CI and fallback path.
- The orchestration choice is explicit and documented.

### 13.2 - Aspire Consolidation

Goal:
- Treat Aspire as the final consolidation step after the module and gateway boundaries are already stable.

Done when:
- Aspire is validated after the earlier slices are green.
- If Aspire fails, it is fixed and rerun before the consolidation phase is closed.
- The consolidation path is documented as the next phase rather than a Phase 9 blocker.

### 13.3 - Deferred Phase 13 Items: Former Phase 9.38 / 9.41 Aspire Items

These items were moved here to prevent Phase 9 from carrying Aspire work as an artificial blocker.

- Inner-loop orchestration proof
- Aspire consolidation
- Any future Aspire testing/deepening work tied to AppHost, manifest generation, or .NET LTS evaluation

## Phase 9.5 - Local Identity Portability Verification

Goal:
- Prove the local Keycloak path works in live runs without replacing the cloud identity model.

Done when:
- Local HTTP uses the seeded Keycloak issuer successfully.
- Docker Dev HTTP mirrors the same issuer and claim behavior.
- The browser flow, API authorization, and tenant claim mapping all pass with the local identity provider.
- No production Entra wiring is regressed.

Status:
- Runtime verified in local HTTP and Docker Dev HTTP.
- Any follow-up is documentation or cleanup only, not new 9.5 capability.
- Azure production stays on Entra ID.
- If Azure ever needs a Keycloak-shaped dependency for parity or migration testing, track it as deferred work so it does not change the local-only scope of this proof.

## Closeout Rule

Phase 9 is complete when:
- Docker dev/http is green.
- Playwright smoke is green.
- Module boundaries are enforced.
- Gateway proof is green.
- Shared host consolidation is complete.
- Traced multi-service flow proof is green.
- Final acceptance matrix is green.
- Any Aspire work is explicitly tracked under the Phase 13 consolidation lane, not held open inside Phase 9.

