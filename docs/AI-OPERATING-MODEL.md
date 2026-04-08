# AI Operating Model

Use this page as the canonical protocol for repo-shared AI customization and governance.

This document does not replace [DEVELOPER-OPERATING-MODEL.md](DEVELOPER-OPERATING-MODEL.md). It extends it for work that changes shared Copilot context, reusable prompts, custom agents, validation workflows, the repo-owned skills layer, or future AI operating layers such as hooks and MCP.

## Purpose

Use this operating model to answer four questions before making a repo-shared AI change:

1. Which primitive should be used?
2. Which files must be updated together?
3. Which checks are mandatory before merge?
4. If something cannot be completed now, where is the deferral recorded?

## Operating Principles

1. Shared AI behavior is a repository governance concern, not a personal preference.
2. The repo already has strong AI assets in `.github/`; add new layers only when the existing layers are insufficient.
3. CI is the compliance boundary. Local tasks and hooks can accelerate feedback, but they are not the source of truth.
4. Every repo-shared AI customization must have a discoverable owner, validation path, and update path.
5. Deferrals are allowed only when recorded in [internal/DEFERRED-WORK-LOG.md](internal/DEFERRED-WORK-LOG.md) with an owner, rationale, and review date.

## Decision Matrix

| Primitive | Use when | Canonical home | Validation expectation |
|----------|----------|----------------|------------------------|
| Workspace instructions | The rule should shape most sessions in this repo | `.github/copilot-instructions.md` | Update owning references and run `pwsh scripts/validate-ai-customization.ps1` |
| File instructions | The rule should auto-attach for specific file patterns | `.github/instructions/` | Frontmatter must include `applyTo`; discovery docs stay in sync |
| Prompts | The workflow is explicit, operator-triggered, and repeatable | `.github/prompts/` | Prompt README and Copilot index must both stay current |
| Agents | A role-specific mode or review boundary is needed | `.github/agents/` | Agent metadata must be present and listed in discovery surfaces |
| Completion rubric | A quality gate needs a defensible pass/defer rule | `.github/completion-check-rubric.md` | Prompt behavior and deferral path must reference the rubric |
| Deferred-work register | Work is intentionally postponed but must remain visible | `docs/internal/DEFERRED-WORK-LOG.md` | Each entry needs owner, rationale, review date, and closure trigger |
| Hooks | Deterministic local lifecycle enforcement is needed | Future `.github/hooks/` | Must mirror CI rules; local-only behavior cannot be authoritative |
| Skills | A specialist workflow is too large or stateful for a prompt alone | `.github/skills/` | Add only after the workflow is repeated often enough to justify a shared package |
| MCP | External tool access or dynamic data sources are required | Future shared MCP config | Read-only first, approved server inventory, explicit auth and audit model required |

## Current Shared AI Surfaces

| Surface | Purpose |
|--------|---------|
| `.github/copilot-instructions.md` | Global repo context loaded into every session |
| `.github/instructions/` | File-pattern-based guidance |
| `.github/prompts/README.md` | Discovery surface for reusable prompts |
| `.github/prompts/*.prompt.md` | Reusable slash workflows |
| `.github/agents/*.agent.md` | Specialized subagent modes |
| `.github/skills/README.md` | Discovery surface for repo-owned skills |
| `.github/skills/*/SKILL.md` | Stable specialist workflows too large for prompts alone |
| `.github/completion-check-rubric.md` | Defensible non-negotiable versus deferrable quality gate guidance |
| `docs/internal/DEFERRED-WORK-LOG.md` | Shared register for justified deferrals |
| `scripts/validate-ai-customization.ps1` | Deterministic validation for shared AI assets |
| `.github/workflows/validate-ai-customization.yml` | CI enforcement for shared AI asset changes |
| `.vscode/tasks.json` | Optional local task entrypoints that mirror the shared AI validation path |

## Mandatory Change Protocol

Use this sequence whenever a change touches `.github/copilot-instructions.md`, `.github/instructions/`, `.github/prompts/`, `.github/agents/`, `.github/skills/`, or the AI governance docs/scripts tied to them.

1. Choose the smallest primitive that solves the problem.
2. Update the owning asset.
3. Update the required discovery surfaces.
   - Prompt changes: `.github/prompts/README.md` and `.github/copilot-instructions.md`
   - Agent changes: `.github/prompts/README.md` and `.github/copilot-instructions.md`
  - Skill changes: `.github/skills/README.md` and `.github/copilot-instructions.md`
   - Protocol changes: this page and any directly affected workflow/script README
4. Run `pwsh scripts/validate-ai-customization.ps1`.
  - Optional local shortcut: run the VS Code task `Validate: AI customization` or `Validate: AI governance bundle`.
5. If `docs/` changed materially, run `node scripts/validate-doc-links.js`.
6. If something remains incomplete, classify it using [.github/completion-check-rubric.md](../.github/completion-check-rubric.md) and record the deferral in [internal/DEFERRED-WORK-LOG.md](internal/DEFERRED-WORK-LOG.md).
7. Merge only when the repo-shared AI surfaces, discovery docs, and validation path agree.

## Required Review Path

| Change type | Minimum review path |
|-------------|---------------------|
| Prompt or agent wording only | Update discovery docs and pass AI customization validation |
| New prompt or new agent | Update discovery docs, validate locally, and ensure CI workflow covers the new asset |
| New instruction file or `applyTo` expansion | Validate metadata, verify file targeting is specific, and re-check for context bloat risk |
| New guardrail or policy | Update this operating model or the completion rubric, not just a prompt body |
| New workflow/script supporting AI governance | Document it in the owning README and add CI coverage |
| New skill | Update skill discovery docs, validate metadata, and prove the workflow is stable enough to justify the extra layer |
| MCP introduction | Treat as architecture-level governance work; require explicit protocol and access model first |

## Deferral Protocol

Use [.github/completion-check-rubric.md](../.github/completion-check-rubric.md) to decide whether a gap is non-negotiable or deferrable.

If the gap is deferrable:

1. Create or update an entry in [internal/DEFERRED-WORK-LOG.md](internal/DEFERRED-WORK-LOG.md).
2. Record the source task, owner, rationale, risk, review date, and closure trigger.
3. Do not close the task until the deferral is visible in the shared register.

If the gap is non-negotiable:

1. Fix it in the same change.
2. Re-run validation.
3. Only then treat the work as complete.

## Maintenance Cadence

- At the end of any repo-shared AI customization task:
  - Run `pwsh scripts/validate-ai-customization.ps1`
  - Run `node scripts/validate-doc-links.js` if `docs/` changed
  - If you want a local shortcut, use the VS Code task `Validate: AI governance bundle`
- Once per week:
  - Review [internal/DEFERRED-WORK-LOG.md](internal/DEFERRED-WORK-LOG.md)
  - Run `/XYDataLabs-context-audit` if prompts, agents, instructions, or major repo structure changed
- After major repo refactors:
  - Re-check `.github/copilot-instructions.md`
  - Re-check instruction `applyTo` patterns
  - Re-check prompt and agent discoverability in `.github/prompts/README.md`
  - Re-check skill discoverability in `.github/skills/README.md`

## Future Layers

Hooks and MCP are intentionally not baseline requirements today.

Introduce them only when all three conditions are true:

1. The workflow is already stable and repeated.
2. The existing prompt/agent/instruction model is no longer sufficient.
3. Validation, ownership, and audit expectations are defined before rollout.

For MCP specifically, the first shared pilot must stay read-only until the server inventory, authentication model, and audit expectations are documented and reviewed.