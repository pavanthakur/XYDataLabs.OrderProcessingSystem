---
name: code-review-guardrails
description: "Use when reviewing changes in this repository for architecture compliance, tenant safety, security issues, CQRS correctness, migration safety, or missing backend test coverage."
---

# Code Review Guardrails

Use this skill for repeatable, read-oriented review work in this repository.

## Scope

Use when the task involves any of the following:

- Reviewing uncommitted changes before commit
- Auditing a pull request or patch for architecture violations
- Checking tenant safety, secret hygiene, or payment-data handling
- Verifying CQRS correctness and `Result<T>` usage
- Inspecting EF Core migrations for safety or drift risk
- Confirming backend test coverage expectations were met

Do not use this skill for:

- Making code edits directly
- Azure deployment workflow review focused on OIDC, Bicep, or App Service rollout paths
- UI-only style or design critique unrelated to repo guardrails

## Required References

Open the relevant sources before reviewing:

- `.github/agents/code-reviewer.agent.md`
- `.github/prompts/XYDataLabs-completion-check.prompt.md` when the review is part of task closeout
- `.github/instructions/clean-architecture.instructions.md`
- `.github/instructions/multitenant-payment-schema.instructions.md` when payment or tenant-owned data is involved
- `.github/instructions/ef-migrations.instructions.md` when Infrastructure or migrations changed
- `.github/instructions/architecture.instructions.md` when ADR or architecture docs changed

## Operating Rules

1. Stay read-only.
   - Analyze and report findings.
   - Do not edit files as part of the review.
2. Review against repository rules, not preference.
   - Cite the violated architecture, security, tenancy, or workflow rule.
3. Prioritize risk over style.
   - Focus on bugs, regressions, security, tenant isolation, and missing tests.
4. Treat expected-failure handling as a guardrail.
   - Backend handlers should return `Result<T>` rather than throwing for normal flows.
5. Treat tenant and payment boundaries as non-negotiable.
   - Missing `TenantId`, tenant filter bypass, raw PAN, or CVV2 exposure are immediate findings.
6. Treat migration safety as part of the review, not an optional follow-up.
   - Flag data loss risk, missing mapping updates, and breaking schema assumptions.

## Recommended Execution Flow

1. Classify the review.
   - Feature review
   - Fix review
   - Migration review
   - Guardrail audit
   - Closeout/completion review
2. Identify the changed files and highest-risk slices first.
   - Domain and Application boundaries
   - Tenant-owned models and queries
   - Controllers, scripts, and external boundaries
   - Migration assets and persistence mappings
3. Apply the review checklist.
   - Layering
   - Tenant safety
   - Payment-data safety
   - `Result<T>` and CQRS correctness
   - Migration safety
   - Test coverage
   - Secret hygiene
4. Report findings in severity order.
5. If the review is part of task completion, align the findings with `/XYDataLabs-completion-check` and the deferral rubric.

## Common Checks

- Domain or Application code importing Infrastructure namespaces
- Tenant-owned entities or queries missing `TenantId` protections
- Raw secrets, connection strings, keys, or tokens committed in source
- Payment-related models exposing PAN or CVV2 instead of masked/tokenized values
- CQRS handlers returning plain values or throwing for expected outcomes
- Migrations that drop data, omit mapping updates, or lack corresponding test coverage
- New backend behavior without matching Domain, Application, API, or Architecture tests where appropriate

## Output Guidance

Report findings first, ordered by severity.

- Include file and line references for each finding
- Keep summaries brief and secondary to findings
- If no findings are present, state that explicitly and mention any residual testing or review gaps

## Validation Path

For shared AI customization changes related to this skill:

- `pwsh scripts/validate-ai-customization.ps1`

For the code under review, prefer the narrowest available executable evidence referenced by `/XYDataLabs-completion-check`.

## Related Assets

- `.github/agents/code-reviewer.agent.md`
- `.github/prompts/XYDataLabs-completion-check.prompt.md`
- `.github/completion-check-rubric.md`
- `docs/internal/DEFERRED-WORK-LOG.md`