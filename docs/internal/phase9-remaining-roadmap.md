# Phase 9 Remaining Roadmap

This roadmap captures the remaining concrete Phase 9 closure work and the verified Phase 9.5 identity-portability lane. Aspire-specific consolidation items are split out where they belong.

## Current Readout

- Phase 9 module extraction, split-module boundaries, and Docker/local task wiring are in place.
- Local Keycloak portability wiring for Phase 9.5 is implemented in the repo and runtime-verified in local HTTP and Docker Dev HTTP.
- What remains for Phase 9 is the residual module-extraction and consolidation work listed below, plus any follow-up cleanup surfaced by those runs.

## Phase 9 Closure Lane

| Item | Status | Done When |
|---|---|---|
| 9.35 Module boundary cleanup | Complete | Orders, Inventory, Notifications, and Payments are isolated by contract; cross-module use goes through `API`; architecture tests catch leaks. |
| 9.36 Gateway boundary proof | Complete | Supported host/path patterns pass; invalid host/path/header combinations fail; gateway boundary tests stay green. |
| 9.37 Shared host consolidation | Complete | Health checks, OpenTelemetry, service discovery, and HttpClient resilience are standardized through `ServiceDefaults` without changing Docker Compose behavior. |
| 9.39 Traced multi-service flow proof | Complete | A single request preserves correlation metadata end to end and the proof repeats reliably. |
| 9.40 Final acceptance matrix | Complete | The matrix states complete/partial/open items and ties each one to a concrete command or test. |

### Current Exit Criteria

- Phase 9.5 remains verified and closed.
- Phase 13 Aspire work remains separate from the Phase 9 blocker list.
- The Phase 9 closeout matrix and roadmap stay aligned with the compact lane above.

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

1. Local HTTP: `1 Run: Local HTTP 01 Env Ready`
2. Local HTTP: `1 Run: Local HTTP 02 Playwright Smoke`
3. Local HTTP: `1 Run: Local HTTP 03 Matrix Sanity (1 Tenant, Local HTTP)`
4. Local HTTP: `1 Run: Local HTTP 04 Integration Suite (Local SQL, No Docker)`
5. Local HTTP: `1 Run: Local HTTP 05 Full Validation (All Tenants + Providers, Local HTTP)`
6. Docker Dev HTTP: `1 Run: Docker Dev HTTP 01 Env Ready (Docker Dev HTTP)`
7. Docker Dev HTTP: `1 Run: Docker Dev HTTP 02 Playwright Smoke (Docker Dev HTTP)`
8. Docker Dev HTTP: `1 Run: Docker Dev HTTP 03 Integration Suite (Docker Dev HTTP)`
9. Docker Dev HTTP: `1 Run: Docker Dev HTTP 04 Payment Matrix (All Tenants + Providers, Docker Dev HTTP)`
10. Docker Dev HTTP: `1 Run: Docker Dev HTTP 05 Full Validation (Profile + Suite + Smoke + Matrix, Docker Dev HTTP)`

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

### 13.3 - Reference Only: Former Phase 9.38 / 9.41 Aspire Items

These items were moved here to prevent Phase 9 from carrying Aspire work as an artificial blocker.

- Inner-loop orchestration proof
- Aspire consolidation
- Any future Aspire testing/deepening work tied to AppHost, manifest generation, or .NET LTS evaluation

### 13.4 - Deferred Azure Keycloak Parity Check

Goal:
- Reserve a later-phase slot for any Azure-side Keycloak-shaped parity or migration test that may be useful after the local portability proof is closed.

Done when:
- The item is explicitly tracked as a later implementation concern, not part of Phase 9.5.
- Entra ID remains the production identity model.
- Any Azure proof is documented with clear scope boundaries and does not change the local-only Phase 9.5 contract.

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
- If Azure ever needs a Keycloak-shaped dependency for parity or migration testing, track it as a later phase item (after Phase 9 closeout) so it does not change the local-only scope of this proof.

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

