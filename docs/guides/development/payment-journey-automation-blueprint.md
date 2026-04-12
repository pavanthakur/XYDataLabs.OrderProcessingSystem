# Payment Journey Automation Blueprint

Canonical pre-implementation blueprint for browser-driven payment journey automation across local,
Docker, and optional Azure execution paths.

This blueprint is a **companion planning surface** for backend Phase 8. It does not create a new
backend phase, it does not renumber the roadmap, and it does not turn full payment UI journeys into
an every-PR gate.

## Objective

Create a separate automation workspace that can execute tenant-by-tenant payment journeys, handle
provider challenge paths without leaking provider concerns into the React app, invoke the existing
verification scripts as the source of runtime truth, and publish stable executive summaries plus
detailed evidence artifacts.

## Scope Boundaries

### In scope

- A separate `automation/` workspace outside `frontend/` and outside the .NET solution
- Browser-driven payment journey execution for the supported runtime targets
- Tenant-matrix orchestration for TenantA, TenantB, and TenantC
- Reuse of `scripts/verify-payment-run-physical.ps1` and `scripts/verify-payment-run-azure.ps1`
- Report generation with frozen executive-summary columns and machine-readable detail output
- Contract seams for future service or microservice-specific automation adapters

### Out of scope

- Folding UI automation into the React workspace or existing frontend CI job graph
- Rewriting the existing verification scripts in Node.js
- Making Azure scheduled payment journeys mandatory before local execution is proven
- Linux runner portability in the first implementation cut
- Treating full payment UI journeys as a required PR gate

## Separation Of Concerns

The automation design stays split into three lanes:

1. **Code validation lane** — existing unit, architecture, integration, typecheck, and build paths
2. **UI automation lane** — browser-driven payment journeys owned by the separate `automation/` workspace
3. **Runtime verification lane** — existing PowerShell verification scripts and log/database evidence paths

The browser lane may call the runtime verification lane, but it does not reimplement it.

## Discovery Pointers And Precedence

Update pointers in this order when the blueprint moves forward:

1. `ARCHITECTURE-EVOLUTION.md` — primary roadmap pointer for pre-Phase-8 discovery
2. `README.md` — repo front door pointer for onboarding and broad discovery
3. `docs/DEVELOPER-OPERATING-MODEL.md` — developer resume-from-Phase-8 pointer
4. `docs/guides/development/README.md` and `docs/guides/development/ui-modernization-plan.md` — sibling guide surfaces
5. `docs/internal/AZURE-PROGRESS-EVALUATION.md` — status note only, not a primary discovery pointer

## Placeholder Workspace Layout

The separate automation workspace starts as a placeholder with frozen seams and a registered no-op
service adapter:

```text
automation/
  README.md
  package.json
  tsconfig.json
  config/
    runtime-targets.example.json
  src/
    contracts/
      execution-request.ts
      runtime-target-catalog.ts
      tenant-execution-catalog.ts
      payment-fixture-provisioner.ts
      provider-challenge-handler.ts
      verification-adapter.ts
      report-composer.ts
      service-automation-adapter.ts
    adapters/
      service/
        noop-service-automation-adapter.ts
    orchestrator/
      service-automation-registry.ts
      placeholder-orchestrator.ts
```

This scaffold proves the seams and registration path before any real payment journey is added.

## Frozen Contracts

### 1. ExecutionRequest

`allowPartialExecution` is owned by the execution request surface.

- GitHub Actions home: workflow input `allowPartialExecution`
- Local home: CLI flag `--allow-partial`
- Not allowed: environment-variable-only control, or storing the flag inside the runtime target catalog

The resolved boolean may flow into the runner, but its canonical policy home is the workflow-input
and CLI contract frozen in Phase 0A.

### 2. RuntimeTargetCatalog

Owns runtime target definitions only.

- Required initial target keys: `local-http`, `local-https`, `docker-dev-http`, `docker-dev-https`, `docker-stg-http`, `docker-stg-https`, `docker-prod-http`, `docker-prod-https`, `azure-dev`
- Required fields: target key, base URL, verification mode, browser mode, expected tenant source, challenge capability, and support flags
- Hard rule: adding Docker or Azure targets must be a configuration change, not an orchestrator interface change

### 3. TenantExecutionCatalog

Resolves the tenant matrix for a selected runtime target.

- Default behavior: fail fast if any required tenant metadata cannot be resolved
- Partial behavior: allowed only when `allowPartialExecution = true`
- Required output: resolved tenants, skipped tenants, and explicit resolution failures

### 4. PaymentFixtureProvisioner

Owns test data preparation and cleanup boundaries.

Frozen contract surface:

- `prepare(...)` returns created or reused fixture references plus baseline metadata
- `cleanup(...)` returns one of `deleted`, `reset`, or `manual-review`, plus any residual IDs

Phase 3 acceptance bar for local HTTP runs:

- No untracked residual fixture state is allowed
- Every automation-created fixture is either deleted or reset to a named reusable baseline
- `manual-review` is not an acceptable cleanup outcome for the initial local HTTP batch exit

### 5. ProviderChallengeHandler

Owns provider challenge and OTP behavior outside the React app.

- Required outcomes: `passed`, `partial`, `failed`, `not-applicable`
- Ownership rule: provider challenge automation belongs to the automation workspace, never to React production code
- Non-production default: if the provider sandbox accepts arbitrary three-digit OTP values, the initial automation code is `999`
- Production rule: OTP values are never hardcoded for production paths
- OTP feasibility is decided in Phase 0B, not in the contract-freeze phase

### 6. VerificationAdapter

Owns invocation of the existing runtime verification scripts.

- Physical targets call `scripts/verify-payment-run-physical.ps1`
- Azure targets call `scripts/verify-payment-run-azure.ps1`
- Invocation boundary: Node uses `child_process.spawn` with `pwsh` 7, JSON on stdout, diagnostics on stderr
- Linux portability is explicitly deferred until a real runner need exists

### 7. ReportComposer

Owns the frozen executive summary plus detailed evidence artifacts.

The executive summary column set is frozen in Phase 0A with these twelve columns:

1. `runId`
2. `runtimeTarget`
3. `tenantCode`
4. `paymentProvider`
5. `threeDsExpectation`
6. `journeyOutcome`
7. `challengeOutcome`
8. `verificationOutcome`
9. `cleanupOutcome`
10. `startedUtc`
11. `finishedUtc`
12. `evidenceReference`

### 8. ServiceAutomationAdapter

Owns optional service or microservice-specific hooks.

- A no-op adapter must exist from Phase 1 onward
- The no-op adapter must be registered with the orchestrator registry
- The no-op adapter must be invoked during placeholder execution and return a no-op result

This seam is considered proven only when registration and invocation are both exercised.

## Execution Policies

The following policies are frozen by the blueprint:

1. Full payment UI journeys do not run on every pull request.
2. Runtime verification remains script-first; browser automation does not replace it.
3. Azure scheduled promotion requires named owner approval.
4. Provider challenge handling stays outside production React code.
5. Docker and Azure expansion must remain catalog-driven, not orchestrator-driven.

## Phase Plan

### Phase 0A — Contract Freeze And Reporting Freeze

**Goal:** Freeze the execution request rules, report contract, target catalog shape, and
verification invocation boundary before runner implementation begins.

**Deliverables:**

- This blueprint approved as the canonical automation plan
- `allowPartialExecution` frozen as workflow input plus CLI flag ownership
- `RuntimeTargetCatalog`, `TenantExecutionCatalog`, `PaymentFixtureProvisioner`, `VerificationAdapter`, `ReportComposer`, and `ServiceAutomationAdapter` signatures frozen
- Twelve executive-summary columns frozen
- PowerShell invocation contract frozen as `spawn` + JSON stdout + `pwsh` 7

**Exit criteria:**

1. Workflow-input policy owns `allowPartialExecution`; the runtime target catalog does not.
2. `ReportComposer` has a stable executive-summary schema.
3. `VerificationAdapter` has a stable invocation boundary.

### Phase 0B — OTP And Provider Challenge Feasibility Spike

**Goal:** Prove what level of provider challenge and OTP automation is realistically supportable
without blocking the structural blueprint.

**Deliverables:**

- Provider challenge decision tree documented as `passed`, `partial`, `failed`, `not-applicable`
- OTP feasibility notes captured with explicit blockers or supported paths
- Validation recorded for whether sandbox OTP `999` is accepted as the default non-production challenge code
- Evidence captured for local supportability before Azure promotion is considered

**Exit criteria:**

1. OTP supportability is explicit, not assumed.
2. The first implementation slice knows whether the challenge path starts at `passed` or `partial`.
3. If the provider accepts arbitrary three-digit OTP values, the non-production handler standardizes on `999`; otherwise the fallback rule is documented explicitly.

### Phase 1 — Placeholder Workspace And Registry Seam

**Goal:** Stand up the separate automation workspace and prove the service-adapter seam is real.

**Deliverables:**

- `automation/` scaffolded outside `frontend/`
- Contract stubs checked in under `automation/src/contracts/`
- No-op `ServiceAutomationAdapter` implemented, registered, and invoked by the placeholder orchestrator
- `RuntimeTargetCatalog.resolve` available for placeholder execution using example config

**Exit criteria:**

1. The orchestrator can resolve a runtime target and invoke the registered no-op adapter.
2. The no-op adapter result appears in placeholder execution output.
3. The microservice seam exists as runnable wiring, not just as file layout.

### Phase 2 — Single-Tenant Local HTTP Pilot

**Goal:** Exercise the first real payment journey against the simplest supported runtime target.

**Deliverables:**

- `RuntimeTargetCatalog.resolve` exercised for `local-http`
- `TenantExecutionCatalog.resolve` exercised for the first real tenant selection
- `PaymentFixtureProvisioner.prepare` exercised for the first real fixture setup
- `VerificationAdapter.execute` exercised against the physical verification script
- `ReportComposer` produces the first real executive summary row plus detailed evidence

**Exit criteria:**

1. The first local HTTP journey completes with a typed report artifact.
2. Target resolution, tenant resolution, fixture preparation, and verification invocation are all exercised for real.

### Phase 3 — Three-Tenant Local HTTP Batch And Cleanup

**Goal:** Prove batch orchestration and cleanup discipline across the tenant matrix.

**Deliverables:**

- TenantA, TenantB, and TenantC run through the batch orchestrator
- `PaymentFixtureProvisioner.cleanup` exercised on every tenant run
- Cleanup outcomes are captured as `deleted` or `reset`
- `allowPartialExecution` behavior is exercised explicitly for failure handling

**Exit criteria:**

1. Every tenant run emits a report row and cleanup outcome.
2. Local HTTP batch leaves no untracked residual fixtures.
3. Partial execution occurs only when the explicit workflow input or CLI flag enables it.

### Phase 4 — Local HTTPS And Optional Azure Promotion

**Goal:** Expand the proven local model to HTTPS and then to Azure under controlled ownership.

**Deliverables:**

- `local-https` added as a catalog entry
- Azure execution kept optional and protected by named owner approval
- Azure-specific verification remains script-first through `verify-payment-run-azure.ps1`

**Exit criteria:**

1. HTTPS support is catalog-driven.
2. Azure promotion has a named owner and explicit approval rule.
3. No Azure execution path bypasses the verification adapter.

### Phase 5 — Docker Profile Expansion

**Goal:** Add Docker profiles without changing orchestrator contracts.

**Deliverables:**

- Docker targets added only as runtime target catalog entries
- Existing orchestrator contracts reused unchanged
- Reports continue to use the same frozen executive summary columns

**Exit criteria:**

1. Docker profiles are added as configuration entries in `RuntimeTargetCatalog`.
2. No orchestrator interface changes are required for Docker support.
3. Existing report and verification contracts remain unchanged.

## Implementation Guardrails

1. Keep the automation workspace outside `frontend/` and outside the .NET solution graph.
2. Reuse existing verification scripts; do not fork verification logic into Node.
3. Keep provider-specific challenge logic isolated behind `ProviderChallengeHandler`.
4. Require explicit residual-state reporting from `PaymentFixtureProvisioner.cleanup`.
5. Keep Azure scheduling manual or owner-approved until local and Docker runs are stable.
6. Treat OTP `999` as a non-production-only convention, never as a production credential or secret.

## Canonical References

- `ARCHITECTURE-EVOLUTION.md`
- `README.md`
- `docs/DEVELOPER-OPERATING-MODEL.md`
- `docs/guides/development/ui-modernization-plan.md`
- `scripts/README.md`
