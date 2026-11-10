# GitHub Copilot — Repository Entry Point

Follow the shared engineering contract in [AGENTS.md](../AGENTS.md). This file adds Copilot-specific discovery guidance; it is not a second architecture inventory, phase tracker or deployment runbook.

## Session And Scope

For session continuation, read [the concise repository handoff](../memories/repo/active-work.md) through the available filesystem/repository tools. Use bounded read-only checks of Git state, the relevant plan and material evidence. A handoff or historical PASS does not prove current-candidate or Azure acceptance; missing revision binding/evidence must stay explicit.

Preserve paused scope, unrelated changes and all shared approval boundaries. Do not automatically run full suites, stage/commit/push, create snapshots, launch agents or execute consequential validation. Completing a prompt is not permission for another operation.

## Context Routing And Discovery

Use [the AI operating model](../docs/AI-OPERATING-MODEL.md#task-context-routing) to select only the guidance needed for the task.

- File-pattern instructions live in [instructions/](instructions/). Copilot applies them according to supported client/settings behavior; other tools must not assume `applyTo` metadata is interpreted automatically.
- [The prompt/agent index](prompts/README.md) owns command and role discovery. Select the relevant workflow; do not load every prompt or automatically launch another agent.
- [The skill index](skills/README.md) owns discovery of the five existing skills. Read the selected skill's full entry and only its required task-specific references.
- [Architecture and ADRs](../ARCHITECTURE.md) own invariants; [the documentation hub](../docs/README.md) owns human navigation. Do not copy their inventories or status snapshots here.
- Reuse phase plans for approved scope, the existing handoff for continuation, and raw results for evidence. Never create competing memory or roadmap files.

## Strict Azure Runtime Target Convention

For approved Azure automation work, `automation/config/runtime-targets.json` owns configured target metadata; generated addresses come from deployment/control-plane outputs under the existing explicit fallback policy. Do not commit generated ACA hostnames, revision suffixes or discovery output into the catalog. Read [the Azure workflow instructions](instructions/azure-workflows.instructions.md) and run `Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` when applicable. This guidance does not authorize deployment.

## Validation

For shared AI changes, update the owning index and run `pwsh -NoProfile -File scripts/validate-ai-customization.ps1`, applicable link checks and `git diff --check`. Explicit routing is the baseline; native discovery and fresh-session behavior remain client/version-dependent until observed. Report actual results and stop for review without automatic Git writes.
