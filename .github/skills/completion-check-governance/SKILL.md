---
name: completion-check-governance
description: "Use when closing out a task in this repository and you need the repo-standard completion gate: build, tests, secret scan, documentation checks, automation checks, Copilot-context checks, and deferral decisions."
---

# Completion Check Governance

Use this skill for repeatable task closeout work in this repository.

## Scope

Use when the task involves any of the following:

- Closing out a feature, fix, script change, workflow change, or governance update
- Running the repo-standard completion gate before commit or handoff
- Deciding whether a gap must be fixed now or can be deferred
- Verifying documentation, guardrails, tests, automation, and Copilot-context updates stayed aligned

Do not use this skill for:

- Initial feature implementation work before the change exists
- Read-only code review where no completion decision is needed
- Narrow local experiments that are not being closed out yet

## Required References

Open the relevant sources before running the closeout gate:

- `.github/prompts/XYDataLabs-completion-check.prompt.md`
- `.github/completion-check-rubric.md`
- `docs/internal/DEFERRED-WORK-LOG.md` when something may need deferral
- `docs/AI-OPERATING-MODEL.md` when the task touched shared AI customization surfaces
- `.github/copilot-instructions.md` when the task changed discoverability or repo context

## Operating Rules

1. Run executable checks first.
   - Use the prompt's build, test, and secret-scan path before evaluating the checklist.
2. Treat correctness and safety gaps as non-negotiable.
   - Follow the rubric for security, tenant isolation, deployment safety, shared repo truth, and missing validation.
3. Fix gaps now when they are within scope.
   - Do not defer a gap that weakens correctness, safety, or shared context accuracy.
4. If a gap is deferrable, record it visibly.
   - Use `docs/internal/DEFERRED-WORK-LOG.md` with the required fields.
5. Keep discovery surfaces synchronized.
   - If prompts, agents, skills, instructions, or shared docs changed, verify their discovery paths were updated.
6. Use the narrowest applicable validation.
   - Prefer the smallest executable check that still proves the changed slice is sound.

## Recommended Execution Flow

1. Identify the task type.
   - Backend code
   - Workflow or script
   - Documentation or governance
   - Shared AI customization
2. Run the automated checks required by `/XYDataLabs-completion-check`.
   - Build
   - Relevant test projects
   - Secret scan
   - Any required automation or Docker validation bundle for the touched area
3. Evaluate the six checklist categories.
   - Documentation
   - Guardrails
   - Unit tests
   - Integration and architecture tests
   - Automation and CI/CD
   - Copilot context
4. Fix any non-negotiable gaps immediately.
5. If something is deferrable, log it with owner, rationale, risk, review date, and closure trigger.
6. Report the closeout result in the repository's summary-table format.

## Common Checks

- Shared AI assets changed without `pwsh scripts/validate-ai-customization.ps1`
- New discovery surfaces were added but not documented in the owning README or `.github/copilot-instructions.md`
- A code change landed without the narrowest matching unit or integration test
- A workflow or script change introduced an undocumented or non-automated manual step
- A gap is being deferred even though it affects correctness, security, tenant isolation, deployment safety, or shared repo truth

## Output Guidance

Summarize results by completion category and call out any unresolved items.

- Report build, secret scan, tests, documentation, automation, and Copilot-context status
- Distinguish between fixed-now gaps and explicitly deferred gaps
- If a deferral is used, reference the shared deferred-work log entry

## Validation Path

For shared AI customization changes related to this skill:

- `pwsh scripts/validate-ai-customization.ps1`

For task closeout work, use the executable checks defined in `.github/prompts/XYDataLabs-completion-check.prompt.md`.

## Related Assets

- `.github/prompts/XYDataLabs-completion-check.prompt.md`
- `.github/completion-check-rubric.md`
- `docs/internal/DEFERRED-WORK-LOG.md`
- `docs/AI-OPERATING-MODEL.md`