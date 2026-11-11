# Skills README

This folder is the canonical home for the repository skills. Copilot discovery depends on the supported client/harness; Codex uses explicit routing from `AGENTS.md` unless native discovery is actually observed. Do not duplicate these bodies into another skill library.

Use skills sparingly. A skill is justified only when:

1. The workflow already exists and is repeated often.
2. Prompts, instructions, and existing docs are no longer sufficient on their own.
3. The workflow has a clear validation path and stable operating rules.

For the governing protocol, see `docs/AI-OPERATING-MODEL.md`.

## Available Skills

| Skill | Folder | Use when |
|-------|--------|----------|
| Azure Deployment Operations | `.github/skills/azure-deployment-operations/` | Planning/reviewing the current Phase 10 Container Apps wrapper, OIDC, Bicep, readiness or Azure troubleshooting; legacy App Service guidance only for explicit compatibility work |
| CQRS Backend Implementation | `.github/skills/cqrs-backend-implementation/` | Working on C# backend code in this repo: Domain entities, CQRS handlers, DTOs, Infrastructure data access, API controllers, migrations, or backend test coverage |
| Code Review Guardrails | `.github/skills/code-review-guardrails/` | Reviewing changes in this repo for architecture compliance, tenant safety, security issues, CQRS correctness, migration safety, or missing backend test coverage |
| Completion Check Governance | `.github/skills/completion-check-governance/` | Closing out a task with the repo-standard completion gate: build, tests, secret scan, documentation, automation, Copilot-context checks, and deferral decisions |
| Context Audit Governance | `.github/skills/context-audit-governance/` | Auditing this repo for stale AI context, discovery-surface drift, repo memory inaccuracies, prompt/index mismatches, or secret-like values in AI-facing assets |
| Frontend Feature Development | `.github/skills/frontend-feature-development/` | Implementing or reviewing React and TypeScript features in `frontend/apps/web` or shared frontend packages, especially tenant-aware API and payment UI changes |
| Payment Provider Development | `.github/skills/payment-provider-development/` | Implementing or reviewing payment-provider adapters, tenant provider routing, callbacks, idempotency, payment automation, or provider-specific verification |

## Authoring Rules

1. Each skill lives in its own folder with a `SKILL.md` file.
2. `SKILL.md` must include YAML frontmatter with `name` and `description`.
3. The `description` must contain clear discovery phrases such as `Use when...` so the skill can be found reliably.
4. Every skill must define purpose, activation conditions, exclusions, required sources, related skills, progressive-disclosure references, implementation workflow, security/approval boundaries, validation path, and completion criteria.
5. When a skill is added or changed, update this owning index, keep the shared/Copilot entry links to it valid, and run `pwsh scripts/validate-ai-customization.ps1`. Do not repeat every skill name/body in always-loaded instructions.
6. Skills complement prompts and agents; they do not replace the canonical docs or CI validation path.
7. Read the selected `SKILL.md` completely and retrieve only its applicable required references. Native discovery, explicit reading and tool permissions are separate capabilities; an index entry is not execution approval or permission to delegate.
