# Phase 9 Navigation

This is the single consolidated entry point for the remaining Phase 9 pack.

## What To Use For What

- `phase9-closeout-runbook.md` for the execution sequence.
- `phase9-closeout-matrix.md` for the evidence/status summary.
- `phase9-subphase-plan.md` for the retained example slice.
- `folder-policy.md` for file placement and cleanup rules.
- `run-phase9.ps1` for architect/developer/review/automation step execution.
- `launch-phase9-all-e2e.ps1` for the current sequential phase launcher.
- `run-phase9-closeout-core.ps1` for build/gateway/architecture gate checks.
- `run-phase9-closeout-playwright.ps1` for the browser acceptance gate.
- `run-phase9-payment-e2e.ps1` for docker payment profile verification.
- `run-phase9-payment-matrix.ps1` for the payment combination matrix.
- `start-ollama-controlled.ps1` for controlled local model startup.
- `watch-phase9-logs.ps1` for live log triage.

## Keep

- Closeout and verification scripts
- Direct-write scripts that still support the closure path
- `9.18` as the one retained example slice

## Retire After Closure

- Duplicate per-slice launch wrappers
- Old per-slice evidence markdown
- `_temp` artifacts that are no longer needed for the final audit

## Rule

- Stop on the first real blocker.
- Fix only that blocker.
- Rerun the same step.
- Do not skip ahead.
- Do not add new slice scaffolding unless a future phase truly needs it.

