# Phase Execution Model

Use this sequence for Phase 9 and future phases when running work through local models.

## Standard Sequence

1. Prepare context
   - Confirm active phase in `/memories/repo/active-work.md` or `.github/copilot-instructions.md`.
   - Open the relevant phase pack under `local models/zoocode/`.
   - Build a slice-specific context file with `local models/ai-guidelines/build-slice-context.ps1` before any model call.
   - Fail fast if the generated context exceeds the limit; narrow the slice instead of forcing the run.
   - Confirm local model availability with `local models/ollama/run-local-ollama.ps1`.

2. Architect pass
   - Run the architect profile.
   - Produce ADR/blueprint corrections and the first developer slice.
   - Review and accept or request correction.

3. Developer pass
   - Run the developer profile on one accepted slice only.
   - Validate immediately after the first edit.
   - Repair only defects caused by the slice.

4. Review pass
   - Compare implementation against architect constraints.
   - Capture validation evidence.
   - Decide whether to continue to next slice.

5. Closeout
   - Run repo-specific completion checks for the touched surface.
   - Require a clean build, the relevant automated test suites, and any phase-specific end-to-end verification before the phase is considered complete.
   - Treat build warnings separately from build failures; do not use warnings to claim closure.
   - Record run notes in `local models/prompt-runs/` if the phase produced implementation changes.
   - Update canonical docs only when the accepted phase slice requires it.

## Phase Pack Naming

Use a stable folder name per phase:

- `local models/zoocode/phase9/`
- `local models/zoocode/phase10/`
- `local models/zoocode/phase11/`

Avoid spaces in local execution folders. If a canonical folder contains spaces, keep a local normalized copy for tool compatibility.

## Context Guardrail

Apply the same context-builder guardrail to every new phase pack:

- Phase 9.x phase packs should use the shared builder by default.
- Phase 10.x phase packs should use the shared builder by default.
- Any future phase pack should inherit the same fail-fast sizing rule before a model call.
- If a phase needs larger context, justify it explicitly and keep the acceptance gate narrow.

## Profile Routing

| Work type | Profile | Expected output |
| --- | --- | --- |
| ADR, roadmap, boundary decision | Architect | Decision, constraints, first slice |
| Code implementation | Developer | Small edit, validation result |
| Regression repair | Developer | Minimal repair only |
| Final architecture acceptance | Architect | Acceptance or correction list |
| Context/governance sync | Developer after architect acceptance | Focused docs/context updates |
| Phase closeout | Architect then automation | Clean build, test results, and explicit sign-off |

## Evidence To Capture

For each meaningful run, capture:

- Date and phase.
- Model and provider.
- Prompt file used.
- Input context files.
- Output summary.
- Files changed.
- Validation command and result.
- Repo-owner decision.

## Universal Phase Closeout Bar

Apply this same finish line to every new phase pack, including future Phase 10+ work:

1. Build the solution cleanly using the phase-appropriate restore strategy.
2. Run the architecture test suite for the changed surface.
3. Run the gateway or host-routing tests if the phase touches runtime routing.
4. Run the integration test suite for the changed surface.
5. Run Playwright or equivalent end-to-end verification when the phase includes user-flow validation.
6. Record any warnings or non-blocking issues separately from phase completion.
7. Mark the phase complete only when the acceptance gates are green or explicitly waived in writing.
