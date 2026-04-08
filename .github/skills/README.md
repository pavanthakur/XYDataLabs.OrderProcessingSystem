# Skills README

This folder contains repo-owned Copilot skills for workflows that are repeated, stable, and too large to express cleanly as prompts alone.

Use skills sparingly. A skill is justified only when:

1. The workflow already exists and is repeated often.
2. Prompts, instructions, and existing docs are no longer sufficient on their own.
3. The workflow has a clear validation path and stable operating rules.

For the governing protocol, see `docs/AI-OPERATING-MODEL.md`.

## Available Skills

| Skill | Folder | Use when |
|-------|--------|----------|
| Azure Deployment Operations | `.github/skills/azure-deployment-operations/` | Working on Azure bootstrap, deployment workflows, OIDC validation, App Service rollout checks, Bicep preflight, or deployment troubleshooting in this repo |

## Authoring Rules

1. Each skill lives in its own folder with a `SKILL.md` file.
2. `SKILL.md` must include YAML frontmatter with `name` and `description`.
3. The `description` must contain clear discovery phrases such as `Use when...` so the skill can be found reliably.
4. When a skill is added or changed, update this README, `.github/copilot-instructions.md`, and run `pwsh scripts/validate-ai-customization.ps1`.
5. Skills complement prompts and agents; they do not replace the canonical docs or CI validation path.