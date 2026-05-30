---
name: context-audit-governance
description: "Use when auditing this repository for stale AI context, drift between discovery surfaces and the live codebase, memory inaccuracies, prompt/index mismatches, or secret-like values in AI-facing assets."
---

# Context Audit Governance

Use this skill for repeatable AI-context drift detection in this repository.

## Scope

Use when the task involves any of the following:

- Auditing `.github/copilot-instructions.md` against the live codebase
- Checking repo memory files for factual drift
- Verifying prompt, agent, and skill discovery surfaces are still aligned
- Detecting stale project tables, test-project lists, package references, or directory maps
- Checking AI-facing assets for secret-like values or unsafe tracked config samples

Do not use this skill for:

- Regular feature implementation work
- Narrow code review on a single patch that does not involve shared AI context
- Azure deployment troubleshooting unrelated to AI-surface drift

## Required References

Open the relevant sources before running the audit:

- `.github/prompts/XYDataLabs-context-audit.prompt.md`
- `.github/copilot-instructions.md`
- `.github/prompts/README.md`
- `.github/skills/README.md`
- `docs/AI-OPERATING-MODEL.md`
- `/memories/repo/` files relevant to repo facts and conventions

## Operating Rules

1. Audit the live codebase, not assumptions.
   - Compare prompts, instructions, memories, and discovery docs to actual files, projects, packages, and directories.
2. Treat stale always-on context as high risk.
   - Wrong facts in `.github/copilot-instructions.md` or repo memory can mislead every future session.
3. Report drift concretely.
   - Show current value, actual value, and the affected file.
4. Include AI-facing secret hygiene in the audit.
   - Check instructions, prompts, memory files, and tracked config samples for secret-like literals.
5. Prefer fixing shared-truth surfaces at the source.
   - If the codebase is correct and the docs or memory are stale, update the stale surface rather than weakening the audit.
6. Use the repository's severity model.
   - High for wrong always-on context, medium for missing discovery or incomplete coverage, low for minor drift.

## Recommended Execution Flow

1. Run the prompt-defined audit areas.
   - Project table accuracy
   - Package and framework references
   - Test project structure
   - CQRS and architecture pattern accuracy
   - Directory layout
   - Prompt discoverability
   - Memory freshness
   - Secret hygiene
   - ADR directory consistency
   - Architecture status surface consistency
2. Compare each discovery or memory surface to the live repo state.
3. Classify findings by severity.
4. List the exact edits required for high and medium findings.
5. If audit-driven changes are made to shared AI surfaces, rerun AI customization validation.

## Common Checks

- `.github/copilot-instructions.md` project or test tables missing live projects
- Repo memory describing packages or CQRS tooling that no longer exists
- Prompt indexes that omit newer prompts, agents, or skills
- Architecture phase/status surfaces disagreeing on completed phase or next phase
- AI-facing markdown or tracked config samples containing credential-like literals

## Output Guidance

Present findings as an audit table.

- Include file, issue, current value, actual value, and severity
- Put high and medium issues first
- Follow the table with exact fixes needed for each high and medium issue

## Validation Path

For shared AI customization changes related to this skill:

- `pwsh scripts/validate-ai-customization.ps1`

If `docs/` changed materially while fixing audit findings:

- `node scripts/validate-doc-links.js`

## Related Assets

- `.github/prompts/XYDataLabs-context-audit.prompt.md`
- `docs/AI-OPERATING-MODEL.md`
- `.github/prompts/README.md`
- `.github/copilot-instructions.md`
- `.github/skills/README.md`