# Phase 9 Zoo Code Runner

Use this as the router for the Phase 9 local-model workflow. The pack is intentionally step-based so each command can be run as a one-liner with minimal human loop.

## Phase 9 defaults

- Default model: `qwen2.5-coder:7b`
- Default context: `4096`
- Escalation model: `deepseek-r1:8b` only when the local Qwen output is insufficient
- Developer context: `4096`
- Architecture/review context: `4096`

## One-line execution

Run the local runner script for each step:

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step architect
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step developer
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step review
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step automation
```

## Step flow

1. `architect` creates the Phase 9 architecture handoff and writes the next developer handoff.
2. `developer` implements the accepted slice only and writes the implementation report.
3. `review` checks the diff and writes a review report with corrections.
4. `automation` runs the narrow validation commands and writes the QA report.

## Handover rule

Each step must leave behind the artifact needed for the next step. Do not ask the operator to rebuild context manually unless the step explicitly needs a fresh Repomix snapshot.

## Human loop minimization

- Keep each step one command.
- Keep each step one model.
- Keep each step one artifact.
- Keep each step one next action.
