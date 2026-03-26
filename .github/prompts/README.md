# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /xylab-day-complete, /xylab-sql-local-access, or /xylab-context-audit
```

## Available Prompts

### `/xylab-day-complete`

Purpose:
- Routes end-of-day curriculum updates to the correct documents.
- Ensures progress tracking stays consistent.
- Helps prevent missing updates in curriculum, daily progress, and related docs.

Use when:
- A curriculum day is finished.
- You want guided document updates for learning progress.

### `/xylab-sql-local-access`

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

### `/xylab-context-audit`

Purpose:
- Detects stale AI context by diffing memory files and copilot-instructions.md against the actual codebase.
- Catches drift in project tables, package references, directory layouts, and memory files.
- Reports findings with severity levels (HIGH/MEDIUM/LOW) and specific fix instructions.

Use when:
- Periodically (every few sessions or after major refactors).
- After renaming, adding, or removing projects or packages.
- When Copilot suggestions seem to reference outdated patterns or non-existent code.

### `/xylab-new-feature`

Purpose:
- Orchestrates end-to-end feature development with multitenant support.
- Enforces the mandatory 13-step workflow: requirements → entity → DTO → CQRS → DbContext → migration → controller → tests → build → review → commit → context check → payment verification (conditional).
- References all relevant instruction files at each step.

Use when:
- Adding a new entity with full CQRS, controller, EF migration, and tests.
- You want the agent to follow the established development workflow automatically.

Workflow:
1. Run `/xylab-new-feature` — it gathers requirements and starts implementation.
2. Steps 2-9 are handled by the **CQRS Backend** agent (entity through build+test).
3. Step 10: switch to **Code Reviewer** agent for architecture/security review.
4. Steps 11-12: commit and optionally run `/xylab-context-audit`.
5. Step 13 (conditional): if the feature touched payment code, run `/xylab-verify-payments`.

### `/xylab-verify-payments`

Purpose:
- Runs filtered payment DB verification queries scoped to the most recent OR series.
- Verifies CardTransactions, TransactionStatusHistories, and cross-tenant bleed checks across both shared-pool and dedicated-tenant DBs.
- Adapts expected values to the current `Use3DSecure` state per tenant (checked via pre-flight query first).

Use when:
- After any payment test run (manual or via the UI).
- After a payment-related feature change before committing.
- When investigating a suspected payment data issue.

Prerequisites:
- API ran at least one payment cycle for the OR series you're verifying.
- You know the OR prefix (e.g. `OR-9-26Mar`) — or run the discovery query shown in Step 1.

Note: This prompt generates focused verification queries. For the full reference query set and design context, see `docs/runbooks/payment-db-verification.md`.

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Add a new feature end-to-end | `/xylab-new-feature` |
| Finish a learning day | `/xylab-day-complete` |
| Need local SSMS/sqlcmd access to Azure SQL | `/xylab-sql-local-access` |
| Check for stale AI context / memory drift | `/xylab-context-audit` |
| Verify payment DB records after a test run | `/xylab-verify-payments` |

## Typical Workflows

```
[Starting a new feature]
└─ /xylab-new-feature  →  gathers requirements, orchestrates 12-step workflow
   └─ Steps 2-9: CQRS Backend agent (entity → build+test)
   └─ Step 10: Code Reviewer agent (architecture audit)
   └─ Step 11-12: commit → /xylab-context-audit

[After a coding/learning day]
└─ /xylab-day-complete  →  routes curriculum + command updates
   └─ [Optional] /xylab-context-audit  →  verify no stale references created

[After bootstrap or deploy]
└─ /xylab-sql-local-access  →  open firewall + get SSMS connection details
   └─ [When done] /xylab-sql-local-access  →  close firewall rule

[After a payment test run or payment feature change]
└─ /xylab-verify-payments  →  filtered DB queries for the most recent OR series
   └─ Fails? → open docs/runbooks/payment-db-verification.md for full diagnostics
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
| `.github/prompts/xylab-day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/xylab-sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/prompts/xylab-context-audit.prompt.md` | Context drift detection audit |
| `.github/prompts/xylab-new-feature.prompt.md` | End-to-end feature development workflow |
| `.github/prompts/xylab-verify-payments.prompt.md` | Payment DB verification for a specific OR series |
| `.github/copilot-instructions.md` | Prompt index and quick usage reference |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt is added or its behavior changes, update this README and any bootstrap or troubleshooting docs that reference manual command sequences.