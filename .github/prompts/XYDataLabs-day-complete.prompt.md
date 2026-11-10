---
agent: agent
description: "After material approved work or a pause: routes relevant documentation and concise handoff updates, preserves evidence limits and completion gates, and requires explicit approval for consequential operations"
---

# Day Completion Routing

The user has just completed or partially completed a curriculum day, or is closing out / freezing an architecture phase.

Use the current task and observed evidence to identify what was completed, partially completed or paused. Ask what was done only if that information is missing; do not reconstruct the whole repository.

Apply only the following routes relevant to the approved scope. A governance-only task or pause does not imply curriculum completion, phase closeout or permission to start the next workstream.

## Approval And Evidence Boundaries

- Inspect Git status/HEAD, relevant plan sections and evidence through bounded read-only checks. Treat `memories/repo/active-work.md` as a checkpoint, not proof; unavailable evidence is unavailable, not PASS. Record environment, revision or UNKNOWN, scope and limitations for material claims.
- Git staging, commit, push, merge, tag/branch creation and other Git writes require explicit authorization for the intended operation. Quality checks do not grant that authorization. Prepare a reviewed file list, diff and proposed commands/message; never stage all unrelated work automatically.
- Tests must fit the approved task. Identify side effects before execution: database queries/mutations, Docker lifecycle/reset, sandbox/live charges, refunds, Azure deployment/directory/firewall changes and other consequential operations require explicit scoped approval. A destructive reset requires immediate per-operation approval.
- If required validation needs unavailable tools, credentials, evidence or unapproved side effects, report NOT TESTED/BLOCKED and preserve the gate. Do not silently waive it or record completion. Existing deferral rules still apply.
- Paths under `memories/repo/` refer to this repository, not a personal memory store. Do not create missing memory files or write personal/global memory as part of closeout; use existing owning docs or report the missing reference. Never store credentials or sensitive payment payloads.

## Routing Rules

1. **If the task actually completed curriculum items within approved scope:**
   - Open `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
   - Mark completed items `[x]`, update the `**Completed:**` date line

2. **If the task established or changed a reusable command/procedure** (not every invocation):
   - Update it in the matching section in `docs/reference/quick-command-reference.md`; avoid copying routine output or existing commands
   - Also add them to the appropriate canonical topic file under `docs/reference/`:

     | Topic | File |
     |-------|------|
   | Git, validation, daily workflow | `docs/reference/git-workflow.md` |
   | Azure CLI, Bicep, infra, OIDC | `docs/reference/azure-infra.md` |
   | Azure SQL, EF Core, sqlcmd, firewall | `docs/reference/azure-sql-ef.md` |
   | Local dev, dotnet run, Docker | `docs/reference/local-dev.md` |

   - Create a new section in both files if the topic doesn't exist yet

3. **If an approved consequential architecture decision needs an ADR:**
   - Create a new ADR in `docs/architecture/decisions/ADR-NNN-title.md`
   - Use ADR-000-template.md format: Status / Context / Decision / Consequences
   - Next ADR number = highest existing number + 1

4. **If an approved reusable pattern materially affects future work:**
   - Update the existing owning architecture/reference document; do not create or update a personal memory store

5. **If an approved operation changed the Azure resource contract:**
   - Update its existing owning configuration/runbook; an existing repository memory index may link there. Record secret references only, never credential values; do not place generated FQDNs in the stable runtime target catalog

6. **If the task established a material .NET convention or project boundary:**
   - Update the existing owning guidance; update `memories/repo/dotnet-conventions.md` only if it exists and needs correction

7. **If a workflow/deployment gotcha was discovered:**
   - Update the existing workflow runbook; `memories/repo/workflow-split.md`, if present, should link to its owner rather than duplicate it

8. **If a full week is now complete** (all days in the week have ✅ Completed dates):
   - Update the week heading in `1_MASTER_CURRICULUM.md` to add `— Complete` suffix:
     `### ✅ Weeks N-N: <Week Name> (Days X-Y) — Complete`
   - Update the **COMPLETED SO FAR** bullet at the top of the master file if it exists

9. **If the day's work closes or materially advances an architecture phase or sub-phase:**
    - Update `ARCHITECTURE-EVOLUTION.md` so the strategic roadmap matches repo truth
    - Sync all architecture status and navigation surfaces that summarize the active phase or current milestone, including:
       - `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
       - `docs/learning/curriculum/README.md`
       - `docs/internal/AZURE-PROGRESS-EVALUATION.md`
       - `docs/learning/implementation-notes/implementation-notes-days-29-38.md` or the active implementation-notes file
       - `.github/instructions/curriculum.instructions.md`
       - `docs/DEVELOPER-OPERATING-MODEL.md` when the active phase/current focus changed
       - `.github/copilot-instructions.md` if it contains a current phase snapshot
       - `docs/guides/development/phase10-tool-prerequisites.md` and `docs/internal/phase10-implementation-checklist.md` when the current work is Phase 10 local baseline, toolchain, or transport setup
    - Update all of the following in `ARCHITECTURE-EVOLUTION.md` when applicable:
       - top-level `Current Status`
       - roadmap table status column
       - the affected phase heading/status block
       - any repeated summary/status snapshot near the end of the file
    - If the current work is Phase 10.1 local baseline reconciliation, make sure the roadmap says so explicitly and that Phase 10.2 is still the next active engineering slice
    - If the work closes a minor sub-phase or verification lane such as Phase 8.5, 8.7, or 9.5, update the corresponding phase-roadmap and closeout docs so the sub-phase reads as verified/complete instead of pending
    - If the work closes Phase 9, a Phase 9 closure lane, or the Phase 10 local baseline / transport lane, verify the numbered VS Code task sequence for both `local-http` and `docker-dev-http` is documented and aligned before considering the phase complete
    - Treat architecture-status drift across these files as a blocking inconsistency to fix before finishing
    - If the work is a phase freeze/closeout, do not stop at the checklist change; confirm the phase now reads consistently as complete/next across all status surfaces in the same session

10. **If the approved task produced unique implementation detail worth retaining:**
   - Open `docs/learning/implementation-notes/implementation-notes-days-29-38.md`
   - Add a `## Day N: <Title>` section if the day had notable implementation nuance
   - Include:
     - What was built, configured, or verified — step by step
     - Important commands run with any notable output
     - Key gotchas or discoveries (especially environment/config differences)
     - What this enables for the next day
   - Use numbered sub-headings (e.g. `**1. Topic**`) when the day had multiple distinct activities
   - Include code blocks for any actual code added or console output confirmed
   - Skip this step if the day was purely checklist tasks with no unique detail worth preserving

11. **If any multi-environment file was modified** (Bicep modules, parameter files, sharedsettings, workflows):
    - Review applicability across ALL three environments — dev + staging + prod; preserve intentional environment policy differences:
      - `infra/parameters/dev.json` → `staging.json` → `prod.json`
      - `sharedsettings.dev.json` → `sharedsettings.stg.json` → `sharedsettings.prod.json`
    - Staging Azure resource names use suffix `stg` (not `staging`) — e.g. `rg-orderprocessing-stg`
    - If a Bicep module adds new params, add placeholder entries in all 3 parameter files
    - Flag any missing required environment change; do not expand the approved scope or deploy environments automatically

12. **If the work touched the payment automation workspace, Docker runtime orchestration, or their shared workflow surfaces** (`automation/`, `Resources/Docker/`, `/XYDataLabs-payment-automation`, verification-adapter contracts, or payment automation operator docs):
      - After inspecting the scripts for side effects and confirming scope/approval, run the documented dry-run validation matrix before treating the work as complete:
         - `npm --prefix automation run run:local:matrix:dry`
         - `npm --prefix automation run run:docker:matrix:dry`
         - `npm --prefix automation run run:azure:matrix:dry`
      - Record the pass/fail outcome in the active implementation-notes file when the day had meaningful automation work
      - If the changed slice is runtime-specific and the real target run is explicitly approved, run the narrowest applicable path as additional evidence; target availability alone is not authorization
   - If the work is a phase freeze/closeout and it touched Docker runtime orchestration, payment automation runtime targets, or closeout workflow surfaces, the real Docker validation bundle remains required. Inspect the command's effects and obtain any necessary scoped approval before running `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http` or the narrowest applicable mapped target set; record the generated bundle path. Without approval/evidence, report the gate BLOCKED/NOT TESTED, not complete
      - Treat a missing automation validation run as a blocking gap for phase closeout, not an optional follow-up

13. **If the closing commit closes a major architectural seam (Phase 7, 8, 11, 13, 14) or precedes an irreversible architectural change** (microservices split, primary key strategy change, multi-region rollout):
    - Prepare a snapshot-pair proposal per `docs/internal/branch-and-blueprint-strategy.md` (decision: ADR-018); create it only after explicit approval:
      - Annotated tag: `v-YYYYMMDD-phase<N>-<slug>` (e.g. `v-20260510-phase8-frontend-spa`)
      - Backup branch: `dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>` (e.g. `dev-backup-20260510-FrontendSPA-Upto-Phase8`)
    - Both pointers reference the same anchor commit (the closing commit of the seam)
    - Tag message must follow §1.3 of the strategy doc: phase, anchor commit, companion branch, ADRs ratified, automation matrix link, Docker matrix status, Azure status, intentionally-absent items
    - Propose pushing the tag and branch to origin; execute only with explicit push authorization for those exact refs
    - The branch protection rule on `dev-backup-**` must already exist (one-time GitHub Settings step — instructions in §1.5 of the strategy doc); flag if missing
    - Skip this step for minor phase closeouts (8.5, 8.7, 9.5) and ordinary Day Complete runs

## After Routing
- If the work is a phase freeze/closeout or changed roadmap/status surfaces, run `/XYDataLabs-completion-check` (or perform its equivalent quality gate) before suggesting a commit; fix any non-deferred gaps first
- If the work is a phase freeze/closeout or changed roadmap/status surfaces, run `/XYDataLabs-context-audit` (or perform its equivalent status-surface audit) before suggesting a commit; fix any HIGH or MEDIUM drift first
- If the work is a phase freeze/closeout and it touched the payment automation workspace or workflow surfaces, do not ask "Ready to commit?" until the dry-run automation matrix above passed in the same session or an explicit deferral was recorded
- If the work is a phase freeze/closeout and it touched Docker runtime orchestration, payment automation runtime targets, or closeout workflow surfaces, do not ask "Ready to commit?" until the Docker validation bundle command above produced a bundle with the expected summary files or an explicit deferral was recorded
- For a phase freeze/closeout, do not ask "Ready to commit?" until both mandatory checks above are complete in the same session
- If the work is Phase 10 local baseline reconciliation, or it changed the Phase 10 toolchain / prompt / task surfaces, make sure the day-complete route updated the Phase 10 status line before considering the session closed
- **After material approved implementation, verification or a pause, refresh repository-relative `memories/repo/active-work.md`** — keep the checkpoint under 8 KiB and record date, observed branch/revision context, changes, validation commands/results, evidence scope/limits and one next action. UNKNOWN revision binding and unavailable artifacts must stay explicit. Move superseded narrative out of active context; retain useful history in Git and existing evidence. Preserve unresolved safety constraints and unrelated work; if another task changed the handoff, reconcile rather than overwrite. Read-only questions do not require routine updates. Never claim live revalidation or completion that did not occur.
- Summarise what was updated and where
- Suggest a commit message in the format: `Day <N>: <what was done>`
- Stop with the reviewed diff, validation results, limitations and proposed commit message. Ask for explicit Git-operation approval only when the user wants that next step; never begin the next phase or technical workstream automatically.
