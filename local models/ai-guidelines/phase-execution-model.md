# Phase Execution Model

Use this sequence for Phase 9 and future phases when running work through local models.

## Standard Sequence

1. Prepare context
   - Confirm active phase in `/memories/repo/active-work.md` or `.github/copilot-instructions.md`.
   - Open the relevant phase pack under `local models/zoocode/`.
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
   - Record run notes in `local models/prompt-runs/` if the phase produced implementation changes.
   - Update canonical docs only when the accepted phase slice requires it.

## Phase Pack Naming

Use a stable folder name per phase:

- `local models/zoocode/phase9/`
- `local models/zoocode/phase10/`
- `local models/zoocode/phase11/`

Avoid spaces in local execution folders. If a canonical folder contains spaces, keep a local normalized copy for tool compatibility.

## Profile Routing

| Work type | Profile | Expected output |
| --- | --- | --- |
| ADR, roadmap, boundary decision | Architect | Decision, constraints, first slice |
| Code implementation | Developer | Small edit, validation result |
| Regression repair | Developer | Minimal repair only |
| Final architecture acceptance | Architect | Acceptance or correction list |
| Context/governance sync | Developer after architect acceptance | Focused docs/context updates |

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
