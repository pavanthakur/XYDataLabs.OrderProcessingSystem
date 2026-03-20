# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /day-complete or /sql-local-access
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

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Finish a learning day | `/day-complete` |
| Need local SSMS/sqlcmd access to Azure SQL | `/sql-local-access` |

## Related Files

| File | Purpose |
|------|---------|
| `.github/prompts/day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/copilot-instructions.md` | Prompt index and quick usage reference |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt is added or its behavior changes, update this README and any bootstrap or troubleshooting docs that reference manual command sequences.