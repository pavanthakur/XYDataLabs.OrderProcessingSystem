# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /day-complete, /sql-local-access, or /context-audit
```

## Available Prompts

### `/day-complete`

Purpose:
- Routes end-of-day curriculum updates to the correct documents.
- Ensures progress tracking stays consistent.
- Helps prevent missing updates in curriculum, daily progress, and related docs.

Use when:
- A curriculum day is finished.
- You want guided document updates for learning progress.

### `/sql-local-access`

Purpose:
- Opens or closes the Azure SQL firewall for your current public IP.
- Prints the SQL connection details for local SSMS or sqlcmd access.

Use when:
- You need temporary local SQL access to Azure SQL.
- You want to validate data directly in SSMS.

Important notes:
- Uses the `dev-machine` firewall rule name and safely reuses it.
- Close the firewall rule when done.
- This is for local SQL access, not App Service runtime access.

### `/context-audit`

Purpose:
- Detects stale AI context by diffing memory files and copilot-instructions.md against the actual codebase.
- Catches drift in project tables, package references, directory layouts, and memory files.
- Reports findings with severity levels (HIGH/MEDIUM/LOW) and specific fix instructions.

Use when:
- Periodically (every few sessions or after major refactors).
- After renaming, adding, or removing projects or packages.
- When Copilot suggestions seem to reference outdated patterns or non-existent code.

### `/new-feature`

Purpose:
- Orchestrates end-to-end feature development with multitenant support.
- Enforces the mandatory 12-step workflow: requirements → entity → DTO → CQRS → DbContext → migration → controller → tests → build → review → commit → context check.
- References all relevant instruction files at each step.

Use when:
- Adding a new entity with full CQRS, controller, EF migration, and tests.
- You want the agent to follow the established development workflow automatically.

Workflow:
1. Run `/new-feature` — it gathers requirements and starts implementation.
2. Steps 2-9 are handled by the **CQRS Backend** agent (entity through build+test).
3. Step 10: switch to **Code Reviewer** agent for architecture/security review.
4. Steps 11-12: commit and optionally run `/context-audit`.

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Add a new feature end-to-end | `/new-feature` |
| Finish a learning day | `/day-complete` |
| Need local SSMS/sqlcmd access to Azure SQL | `/sql-local-access` |
| Check for stale AI context / memory drift | `/context-audit` |

## Typical Workflows

```
[Starting a new feature]
└─ /new-feature  →  gathers requirements, orchestrates 12-step workflow
   └─ Steps 2-9: CQRS Backend agent (entity → build+test)
   └─ Step 10: Code Reviewer agent (architecture audit)
   └─ Step 11-12: commit → /context-audit

[After a coding/learning day]
└─ /day-complete  →  routes curriculum + command updates
   └─ [Optional] /context-audit  →  verify no stale references created

[After bootstrap or deploy]
└─ /sql-local-access  →  open firewall + get SSMS connection details
   └─ [When done] /sql-local-access  →  close firewall rule
```

## Custom Agents

Select these in the VS Code Chat agent picker for focused, context-scoped assistance:

| Agent | File | Use when |
|-------|------|----------|
| Azure DevOps | `.github/agents/azure-devops.agent.md` | Workflows, Bicep, PowerShell scripts, Docker, OIDC |
| CQRS Backend | `.github/agents/cqrs-backend.agent.md` | C# domain/application/infrastructure code, CQRS, EF Core |
| Code Reviewer | `.github/agents/code-reviewer.agent.md` | Architecture compliance review, security audit (read-only) |

## Related Files

| File | Purpose |
|------|--------|
| `.github/prompts/day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/prompts/context-audit.prompt.md` | Context drift detection audit |
| `.github/prompts/new-feature.prompt.md` | End-to-end feature development workflow |
| `.github/copilot-instructions.md` | Prompt index and quick usage reference |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt is added or its behavior changes, update this README and any bootstrap or troubleshooting docs that reference manual command sequences.