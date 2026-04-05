# Developer Operating Model

One-page operating model for working in this repository after the documentation rationalization. Treat this as the guided index page for a new reader opening the project for the first time.

## Reading Order

Read the documentation in this order when starting fresh:

1. `README.md`
   - Canonical front door for the human-facing documentation tree.
   - Use it to understand the major documentation areas.
2. `DEVELOPER-OPERATING-MODEL.md`
   - This page.
   - Use it to understand how to navigate the documentation like a book with chapters.
3. `learning/curriculum/1_MASTER_CURRICULUM.md`
   - Active execution source of truth.
   - Tells you what phase/day is current and what to work on next.
4. `internal/AZURE-PROGRESS-EVALUATION.md`
   - Milestone-level truth.
   - Use it to understand which phases are complete, what Azure assets exist, and what Phase 7 requires.
5. `learning/curriculum/README.md`
   - Short navigation guide for the learning track.
   - Best daily companion to the master curriculum.
6. `reference/quick-command-reference.md`
   - Daily command and validation surface.
   - Use it before builds, deployments, or commits.
7. `guides/deployment/README.md`
   - Open this only when the task touches Azure bootstrap, workflows, IaC, secrets, or operations.

## Chapter Map

Think of the canonical `docs/` tree as a book with these chapters:

- `README.md`
  - Book cover and table of contents.
- `learning/`
  - Execution chapter.
  - Contains the current curriculum, implementation evidence, and longer-form supporting material.
- `internal/`
  - Control-room chapter.
  - Contains milestone truth and internal backlog material.
- `reference/`
  - Pocket handbook chapter.
  - Contains commands, operational shortcuts, and repeatable validation steps.
- `guides/`
  - How-to chapter.
  - Contains deployment, configuration, and development procedures.
- `architecture/`
  - Decision register chapter.
  - Contains ADRs and non-negotiable architectural choices.
- `runbooks/`
  - Operations chapter.
  - Contains repeatable operational procedures for incidents, validation, and support tasks.
- `archive/`
  - History chapter.
  - Use only for traceability, not for active navigation or implementation.

## Daily Working Flow

Use this sequence when working on the project:

```text
docs/README.md
  -> docs/DEVELOPER-OPERATING-MODEL.md
     -> docs/learning/curriculum/1_MASTER_CURRICULUM.md
        -> docs/internal/AZURE-PROGRESS-EVALUATION.md
           -> choose the current deliverable
              -> implement in code
              -> validate with docs/reference/quick-command-reference.md
              -> consult docs/guides/ only if the task involves Azure, workflows, Docker, or configuration
              -> record detailed evidence in docs/learning/implementation-notes/ when needed
```

## Current State

- Days 1-38 are complete.
- Phase 7 is the next active engineering phase.
- The canonical learning source of truth is `docs/learning/curriculum/1_MASTER_CURRICULUM.md`.
- The canonical milestone tracker is `docs/internal/AZURE-PROGRESS-EVALUATION.md`.
- The legacy `Documentation/` tree has been retired; documentation traceability now lives under `docs/archive/logs/`.

## What To Update And When

- Update `learning/curriculum/1_MASTER_CURRICULUM.md`
  - When day or phase checklist status changes.
- Update `internal/AZURE-PROGRESS-EVALUATION.md`
  - When phase-level status, Azure estate status, or milestone truth changes.
- Update `learning/implementation-notes/`
  - When a development day needs deeper implementation evidence than a checklist entry.
- Update `architecture/decisions/`
  - When a change introduces or revises a non-trivial architectural decision.
- Update `guides/`
  - When operator-facing procedures or workflows change.
- Do not use `archive/` for active work
  - Archive is historical context only.

## Guardrails Going Forward

1. Freeze documentation rationalization unless a new inconsistency blocks real work.
2. Treat `docs/` as the only active human-facing documentation tree.
3. Treat `.github/` as the canonical home for workflow, prompt, and automation guidance.
4. Prefer updating one canonical page instead of duplicating the same guidance in multiple places.
5. Use `reference/quick-command-reference.md` before commits or deployments.
6. Use `architecture/decisions/` when changing architecture constraints, not ad hoc notes.
7. Use `archive/logs/documentation-rationalization-summary.md` and `archive/logs/documentation-audit.md` only for traceability and audit.

## Simple Process Rules

Use these as the standing working agreement for smoother maintenance and learning activity:

1. One source of truth per topic.
   - Curriculum progress: `learning/curriculum/1_MASTER_CURRICULUM.md`
   - Milestone and phase truth: `internal/AZURE-PROGRESS-EVALUATION.md`
   - Commands and validation: `reference/quick-command-reference.md`
   - Procedures: `guides/`
   - Architecture decisions: `architecture/decisions/`
2. Update the minimum number of documents necessary.
   - Most tasks should update zero or one canonical document.
   - Only broader workflow or structure changes should touch multiple docs.
3. Do not create parallel guidance.
   - If a page already owns a topic, update that page.
   - Do not create a new note just because it is faster in the moment.
4. Archive is read-only for normal work.
   - Use it for traceability only.
   - Do not resume active work from archived material.
5. If the task changes code only, do not force a documentation update.
   - Update docs only when behavior, workflow, architecture, or user/operator guidance changed.

## Lightweight Maintenance Cadence

Keep maintenance simple:

- At the start of the day
  - Open `README.md`
  - Open `learning/curriculum/1_MASTER_CURRICULUM.md`
  - Open `internal/AZURE-PROGRESS-EVALUATION.md`
- At the end of a meaningful task
  - Update the curriculum if checklist status changed
  - Update the progress tracker if a phase-level fact changed
  - Update a guide only if the actual procedure changed
- Once per week
  - Spend 10 minutes checking for obvious broken links, duplicate guidance, or stale navigation
  - Fix only real issues; do not restart broad cleanup work
  - If documentation changed materially, run `node scripts/validate-doc-links.js`

## Definition Of Done For Normal Work

Before closing a feature, day, or infra task, use this short rule:

1. The code, script, or workflow change is complete.
2. The relevant validation or test path was run.
3. The owning source-of-truth page was updated if needed.
4. No duplicate or side-note document was introduced.
5. If `docs/` changed, `node scripts/validate-doc-links.js` passes.

## Change Routing Rule

If you are unsure where an update belongs, route it like this:

- "What should I do next?"
  - `learning/curriculum/1_MASTER_CURRICULUM.md`
- "What phase are we in, and what is complete?"
  - `internal/AZURE-PROGRESS-EVALUATION.md`
- "How do I run, validate, deploy, or troubleshoot this?"
  - `guides/` or `reference/`
- "Did we make a decision future developers must not break?"
  - `architecture/decisions/`
- "Is this just historical context?"
  - `archive/`

## Simplification Rule

When documentation starts to feel noisy, choose simplification by default:

1. Link to an existing canonical page instead of copying content.
2. Remove duplicate guidance instead of rewriting it in two places.
3. Prefer short navigation pages over large summary documents.
4. Prefer one clear checklist over long narrative status notes.
5. If a process needs more than a few bullets to explain, it probably belongs in a guide, not in the operating model.

## High-Value Control Documents

- `docs/README.md`
- `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
- `docs/internal/AZURE-PROGRESS-EVALUATION.md`
- `docs/reference/quick-command-reference.md`
- `docs/guides/deployment/README.md`
- `docs/archive/logs/documentation-rationalization-summary.md`
- `docs/archive/logs/documentation-audit.md`

## Practical Next Move

Documentation structure is stable enough to stop reorganizing and return to engineering work. Resume from Phase 7 using:

1. `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
2. `docs/internal/AZURE-PROGRESS-EVALUATION.md`
3. `docs/reference/quick-command-reference.md`

If a task touches Azure bootstrap, workflows, or IaC, open `docs/guides/deployment/README.md` for the relevant branch of guidance.