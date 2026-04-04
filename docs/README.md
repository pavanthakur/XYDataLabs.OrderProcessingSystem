# Documentation Hub

This folder is the canonical front door for human-facing project documentation.

## Start Here

Choose the path that matches your intent:

1. Open the guided developer operating model
	- `DEVELOPER-OPERATING-MODEL.md` — one-page reading order, chapter map, guardrails, and daily working flow
2. Learn the platform and current roadmap
	- `learning/curriculum/1_MASTER_CURRICULUM.md` — active source of truth for the learning journey
3. Deploy or operate Azure environments
	- `guides/deployment/README.md`
4. Configure secrets, identity, and environments
	- `guides/configuration/README.md`
5. Run commands quickly
	- `reference/quick-command-reference.md`
6. Understand architecture and non-negotiable decisions
	- `architecture/decisions/`
7. Track active internal progress and backlog items
	- `internal/README.md`

## Canonical Areas

- `architecture/` — ADRs and formal architecture material
- `guides/` — deployment, configuration, and development guides
- `reference/` — quick-reference operational material
- `runbooks/` — operational procedures
- `learning/` — curriculum, implementation evidence, and learning support material
- `internal/` — active internal tracking and backlogs
- `archive/` — retired and historical material retained for traceability

## Rules

1. Human-facing documentation lives under `docs/`.
2. `.github/` remains the canonical home for workflow, tooling, prompt, and agent documentation.
3. Retired material is archived, not deleted.
4. The active learning source of truth is `docs/learning/curriculum/1_MASTER_CURRICULUM.md`.
5. Follow `DEVELOPER-OPERATING-MODEL.md` as the lightweight working agreement for what to update, when to update it, and what to leave alone.

## High-Value Locations

- `DEVELOPER-OPERATING-MODEL.md` — guided index page for new contributors and future work
- `learning/curriculum/1_MASTER_CURRICULUM.md` — primary learning execution document
- `learning/curriculum/README.md` — curriculum navigation and current status
- `learning/implementation-notes/` — execution evidence and detailed notes
- `guides/deployment/` — Azure deployment and infrastructure guidance
- `reference/operations-quick-links.md` — fast operational navigation
- `archive/logs/documentation-rationalization-summary.md` — implementation trace for the documentation cleanup