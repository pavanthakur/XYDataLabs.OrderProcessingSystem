# Developer Operating Model

Use this page as the working contract for reading and updating the documentation.

## Reading Order

Read the documentation in this order when starting fresh:

1. `README.md`
  - Canonical front door for the human-facing documentation tree.
2. `DEVELOPER-OPERATING-MODEL.md`
  - This page.
3. `learning/curriculum/1_MASTER_CURRICULUM.md`
  - Active execution source of truth.
4. `internal/AZURE-PROGRESS-EVALUATION.md`
  - Milestone-level truth.
5. `learning/curriculum/README.md`
  - Short learning-track navigation guide.
6. `reference/quick-command-reference.md`
  - Daily command and validation surface.
7. `guides/deployment/README.md`
  - Open this only when the task touches Azure bootstrap, workflows, IaC, secrets, or operations.

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
- Only the active `docs/` tree remains.

## Update Routing

- `learning/curriculum/1_MASTER_CURRICULUM.md` — day or phase checklist status
- `internal/AZURE-PROGRESS-EVALUATION.md` — phase-level status and Azure estate truth
- `learning/implementation-notes/` — detailed implementation evidence
- `architecture/decisions/` — non-trivial architectural decisions
- `guides/` — procedures and operator-facing workflows
- Delete stale notes after merging any still-useful guidance into the owning canonical page

## Working Rules

1. Freeze documentation rationalization unless a new inconsistency blocks real work.
2. Treat `docs/` as the only active human-facing documentation tree.
3. Treat `.github/` as the canonical home for workflow, prompt, and automation guidance.
4. Prefer updating one canonical page instead of duplicating the same guidance in multiple places.
5. Use `reference/quick-command-reference.md` before commits or deployments.
6. Use `architecture/decisions/` when changing architecture constraints, not ad hoc notes.
7. Delete stale material once any remaining actionable guidance has been folded into the canonical page that owns it.

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
  - Do not keep it as a separate document unless it still changes future execution or constraints.

## Practical Next Move

Documentation structure is stable enough to stop reorganizing and return to engineering work. Resume from Phase 7 using:

1. `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
2. `docs/internal/AZURE-PROGRESS-EVALUATION.md`
3. `docs/reference/quick-command-reference.md`

If a task touches Azure bootstrap, workflows, or IaC, open `docs/guides/deployment/README.md` for the relevant branch of guidance.