# Phase 9 Folder Policy

## Purpose

Keep Phase 9 process artifacts, generated evidence, and product code clearly separated so future phases can reuse the same workflow without mixing concerns.

## 1. Process Artifacts

Keep these in `local models\zoocode\phase9`:

- `phase9-navigation.md`
- `README.md`
- `phase9-index.md`
- `phase9-roadmap.md`
- `run-phase9.ps1`
- `run-phase9-e2e.ps1`
- `build-slice-context.ps1`
- `direct-write-*.ps1` that are still wired into active closure or retained as the example set
- `9.x\architect.md`
- `9.x\developer.md`
- `9.x\review.md`
- `9.x\automation.md`

These files define the phase workflow, prompts, execution rules, and the retained example slice.

## 2. Product Code

Keep implementation files only in the real solution folders:

- `XYDataLabs.OrderProcessingSystem.Application\...`
- `XYDataLabs.OrderProcessingSystem.Domain\...`
- `XYDataLabs.OrderProcessingSystem.Gateway\...`
- `tests\...`

These files are the actual product deliverables.

## 3. Temp Evidence

Keep run-time evidence in `local models\zoocode\phase9\_temp`:

- model output
- chat history
- logs
- generated validation artifacts

These files are for triage and proof, not product behavior.

## 4. Junk To Delete

Delete only files that are clearly accidental, broken, or duplicate.

Examples:

- stray root-level sample files
- accidental `.py`, `.js`, or `.cs` files created by drift
- duplicate artifacts in the wrong folder

Do not delete useful phase docs or automation scripts just to reduce noise.

If a helper is no longer needed for closure, move it into the archive list described in `direct-write-archive.md` rather than deleting it immediately.

## 5. Separation Rule

- `local models` is for process and automation
- solution folders are for implementation
- do not mix orchestration into product code folders
- do not mix business code into process folders unless it is an intentional generated deliverable

## 6. Future Phase Rule

Use the Phase 9 process structure as the template for later phases:

1. architect
2. developer
3. review
4. automation

Create the next phase under `local models\zoocode` using the same separation model.

## 7. Final Housekeeping Rule

- Keep everything useful for the next phase
- Remove only clearly non-working or accidental clutter
- Preserve process history if it helps future phase planning

## 8. Direct-Write Closure Slices

- `9.21`, `9.22`, and `9.23` must use direct-write scripts only.
- Do not route these slices through aider-style edit instructions.
- Keep their artifacts in `local models\zoocode\phase9\_temp`.
