# Documentation Hub

Canonical hub for human-facing project documentation.

## Start Here

Choose the path that matches your intent:

1. `DEVELOPER-OPERATING-MODEL.md` — reading order and update rules
2. `AI-OPERATING-MODEL.md` — enterprise protocol for shared Copilot instructions, prompts, agents, validation, and deferrals
3. `learning/curriculum/1_MASTER_CURRICULUM.md` — active execution source of truth
4. `guides/deployment/README.md` — deployment and infrastructure guidance
5. `guides/configuration/README.md` — secrets, identity, and environment guidance
6. `reference/quick-command-reference.md` — daily commands and validation
7. `architecture/decisions/` — architecture constraints and ADRs
8. `internal/README.md` — active internal trackers and backlog

## Areas

- `architecture/` — ADRs and formal architecture material
- `guides/` — deployment, configuration, and development guides
- `reference/` — quick-reference operational material
- `runbooks/` — operational procedures
- `learning/` — curriculum, implementation evidence, and learning support material
- `internal/` — active internal tracking and backlogs

## Rules

1. Human-facing documentation lives under `docs/`.
2. `.github/` remains the canonical home for workflow, tooling, prompt, and agent documentation, while `AI-OPERATING-MODEL.md` owns the human-facing protocol for how those assets are governed.
3. Retired material is deleted after any still-useful guidance is merged into the canonical page that owns it.
4. The active learning source of truth is `docs/learning/curriculum/1_MASTER_CURRICULUM.md`.
5. Follow `DEVELOPER-OPERATING-MODEL.md` as the lightweight working agreement for what to update, when to update it, and what to leave alone.
