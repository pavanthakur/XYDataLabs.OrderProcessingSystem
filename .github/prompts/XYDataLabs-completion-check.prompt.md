---
agent: agent
description: "Scope-aware completion gate: run applicable safe validation, preserve required build/test/security and phase gates, and report documentation, guardrails, tests, automation and context with actual evidence and approval limits"
---

Run this after completing any feature, task, script, fix, workflow change, or phase checkpoint update.

Use `.github/completion-check-rubric.md` to decide whether a gap is non-negotiable or can be deferred.
If a gap is deferred, record it in `docs/internal/DEFERRED-WORK-LOG.md` with owner, rationale, risk, review date, and closure trigger before closing the task.

## Step 0 — Run automated checks first

Read `AGENTS.md` and classify the changed slice before selecting checks. The blocks below are the maintained validation catalog, not permission to run every command for every task. For governance/docs changes, use AI customization, relevant link/metadata/security checks and focused validator tests; record application-only checks as NOT APPLICABLE with rationale when no application boundary changed. For application changes, retain the required build, tests and security checks; retain mandatory phase, automation and Docker evidence when their existing conditions apply.

Inspect side effects first. Database access, Docker lifecycle/reset, provider transactions, Azure/directory operations and Git writes require explicit scoped approval under the shared rules. If a required check lacks approval, tooling or evidence, report BLOCKED/NOT TESTED and do not claim closeout PASS or silently waive it. Do not start another workstream or commit/push automatically. Use observed results for categories 2–5; metadata checks do not establish runtime or fresh-session behavioral acceptance.

**Build (warnings as errors):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
dotnet build XYDataLabs.OrderProcessingSystem.sln --warnaserror /warnnotaserror:NU1701 "/consoleloggerparameters:NoSummary;ForceNoAlign"
```
> `NU1701` is suppressed — it is a known pre-existing warning from `Openpay 1.0.25` (a .NET Framework-only package); all other warnings are errors.

**All test projects:**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
dotnet test tests/XYDataLabs.OrderProcessingSystem.Domain.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests --no-build --logger "console;verbosity=minimal"
```

**Secret / credential scan (no hardcoded values in source):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
pwsh .\scripts\validate-secret-hygiene.ps1
```

**Automation workspace validation (run when the task touches `automation/`, `/XYDataLabs-payment-automation`, verification-adapter contracts, or payment automation docs):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:local:matrix:dry
npm --prefix automation run run:docker:matrix:dry
npm --prefix automation run run:azure:matrix:dry
```

**Docker validation bundle (run when the task closes/freezes a phase or named sub-phase and touches Docker runtime orchestration, payment automation runtime targets, local setup orchestration, or closeout workflow surfaces):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http
```

---

## 1. Documentation

- [ ] Is the feature/change described in the relevant README, guide, or copilot-instructions.md?
- [ ] If a new script was added: does `scripts/README.md` (or the owning folder README) document it with usage, parameters, and purpose?
- [ ] If a new workflow was added: does `.github/workflows/README.md` reference it?
- [ ] If a prompt/agent was added or changed: is it in its owning `.github/prompts/README.md` index, with valid shared/Copilot entry links? Skills belong in `.github/skills/README.md`; do not require duplicate inventories in short entry files.
- [ ] If a new architectural decision was made: is there an ADR in `docs/architecture/decisions/`?
- [ ] If this task closed or materially advanced a curriculum/architecture phase: are all phase-status surfaces aligned (`ARCHITECTURE-EVOLUTION.md`, `docs/learning/curriculum/1_MASTER_CURRICULUM.md`, `docs/learning/curriculum/README.md`, `docs/internal/AZURE-PROGRESS-EVALUATION.md`, active implementation notes, `.github/instructions/curriculum.instructions.md`, `docs/DEVELOPER-OPERATING-MODEL.md` when focus changed, and `.github/copilot-instructions.md` if it contains a phase snapshot)?
- [ ] If this task finalized Phase 10.1 or any Phase 10 local-baseline document: are `docs/guides/development/phase10-tool-prerequisites.md`, `docs/internal/phase10-implementation-checklist.md`, and `ARCHITECTURE-EVOLUTION.md` consistent about the current next step?

## 2. Guardrails *(use secret scan results from Step 0)*

- [ ] Secret scan above: **0 hits** — no hardcoded passwords, keys, or connection strings
- [ ] If a new domain rule or constraint exists: is it enforced in the Domain layer (not just a comment)?
- [ ] If inputs cross a system boundary (API, UI, script parameter): is there validation?
- [ ] If the change could affect another tenant: is tenant isolation preserved?
- [ ] If a script has destructive behaviour: does it require confirmation or a `-Force` / `-WhatIf` flag?

## 3. Unit Tests *(use test results from Step 0)*

- [ ] Build: **0 errors, 0 warnings**
- [ ] Does the new/changed domain entity have unit tests in `Domain.Tests`?
- [ ] Does the new/changed CQRS handler have unit tests in `Application.Tests`?
- [ ] `Domain.Tests` passed (from Step 0 results)
- [ ] `Application.Tests` passed (from Step 0 results)

## 4. Integration / Architecture Tests *(use test results from Step 0)*

- [ ] Does the new/changed controller have tests in `API.Tests`?
- [ ] If an EF Core migration was added: has it been verified against the local DB?
- [ ] `API.Tests` passed (from Step 0 results)
- [ ] `Architecture.Tests` passed — layer boundaries still enforced (from Step 0 results)
- [ ] If this change touches `Program.cs` environment gates (`isDocker`, `isAzure`, `profileSuffix`, `runtimeSuffix`): gate logic is extracted to a testable helper and all 7 cells in the ADR-010 Runtime Context Matrix have been validated — either by unit test, `WebApplicationFactory` integration test, or physical log verification via `/XYDataLabs-verify-db-logs`. Reference: `docs/architecture/decisions/ADR-010-runtime-environment-detection.md`

## 5. Automation / CI-CD

- [ ] If a new script automates a task: can it run unattended (no interactive prompts in CI mode)?
- [ ] If a new workflow was added: is there a corresponding path trigger in the right workflow file?
- [ ] If something was previously manual: is it now captured in a script or workflow?
- [ ] If the task touched the payment automation workspace or workflow surfaces: did `npm --prefix automation run run:local:matrix:dry`, `run:docker:matrix:dry`, and `run:azure:matrix:dry` all pass?
- [ ] If this task closes or freezes a phase and it touched Docker runtime orchestration, payment automation runtime targets, or closeout workflow surfaces: did `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http` (or the narrowest applicable mapped target set) produce a bundle with `summary.md` and `summary.json`?
- [ ] If a VS Code task or Copilot prompt would help discoverability: has one been created?

## 6. Copilot Context

- [ ] Is `copilot-instructions.md` still accurate? (Run `/XYDataLabs-context-audit` if unsure)
- [ ] Is the concise repository-relative `memories/repo/active-work.md` current, evidence-qualified and linked to owners rather than duplicating resource inventories? Do not require nonexistent records or write personal memory.
- [ ] If this task changed current phase or next-phase status: has `/XYDataLabs-context-audit` been run, or has equivalent manual verification confirmed there is no status-surface drift?
- [ ] If this task closes Phase 9, a Phase 9 closure lane, or the Phase 10 local baseline / transport lane: are the numbered VS Code task sequences for both `local-http` and `docker-dev-http` documented and aligned with the closeout roadmap before declaring completion?
- [ ] If this task touched Azure deployment or container image delivery: did you apply the enterprise default review stance automatically?
  - Azure OIDC for Azure login
  - GitHub App for repo-secret automation
  - ACR preferred for Azure runtime image pulls
  - GHCR allowed only as a documented bridge
  - env-suffixed names and cleanup symmetry preserved
  - retention configured at the source
  - summary and child-job traceability links present

---

For each unchecked item, either:
- **Fix it within approved scope** (preferred) — verify the missing piece, then mark it done; do not expand into application/runtime repair without approval
- **Record it** — add an entry to `docs/internal/DEFERRED-WORK-LOG.md` with a clear owner, reason, risk, review date, and closure trigger

## Summary

Report results in this table:

Use PASS / FAIL / BLOCKED / NOT TESTED / NOT APPLICABLE with rationale. DEFERRED requires the existing approved deferral path, not an invented waiver. Separate structural, observed-agent and software-runtime evidence; none substitutes for the others. A pre-existing required-check failure remains FAIL even when outside this task's repair scope.

| Category | Result | Notes |
|---|---|---|
| Build | status | command/scope or applicability rationale |
| Secret scan | status | scope and safe finding counts, never matched values |
| Unit tests | status | actual commands/results |
| Integration/Arch tests | status | actual commands/results or applicability rationale |
| Documentation | status | owning references and link checks |
| Guardrails | status | remaining risks and any approved deferral reference |
| Automation | status | applicable checks and missing evidence |
| AI context | status | structural results; behavioral acceptance separately labelled |

After material approved work, refresh the concise repository-relative `memories/repo/active-work.md` with actual changes/results, evidence limits and one next action. Preserve unresolved constraints and pause/review boundaries. Read-only questions do not require routine updates; no automatic Git writes or next workstream.
