# Phase 9 Sub-Phase Plan

This folder now keeps one retained example slice for future phases and removes the older duplicated 9.x slice folders.

## What Remains

- One canonical example slice: `9.18`
- The reusable phase closeout scripts
- The closeout runbook and evidence logs
- The Ollama handoff and log-watching scripts

## Why 9.18 Is the Retained Example

`9.18` is the cleanest example of the remaining phase plan because it focuses on a real closure-style deliverable: the API surface and boundary verification.

It is the example to reuse when future phases need a similar architect / developer / review / automation workflow.

## Canonical Example

### 9.18 - API Finalization

Purpose:
- Finish the service contract surface for Orders, Inventory, Notifications, and Payments.

What this should produce:
- Stable public contracts for each module boundary.
- Namespace alignment for the final contract layout.
- Boundary tests proving internals are not leaked.

First files to expect:
- `XYDataLabs.OrderProcessingSystem.*.API` project files
- module contract records and interfaces

Representative command sequence:
```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step architect
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step developer
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step review
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Slice 9.18 -Step automation
```

Exit criteria:
- All required public contracts are explicit and compile cleanly.
- Architecture tests prove the public surface is the only cross-module boundary.
- The slice creates or updates real C# code files in the repo.

## Closure Rule

- Stop on the first real blocker.
- Fix only that blocker.
- Rerun the same step.
- Do not skip ahead.
- Keep the logs as the evidence trail.

## Future Phase Pattern

When the next phase is planned, use this same structure:

1. Keep one canonical example slice.
2. Keep one closure runner.
3. Keep one closeout log.
4. Remove duplicate per-slice wrappers after closure is proven.


