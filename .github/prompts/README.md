# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /XYDataLabs-day-complete, /XYDataLabs-sql-local-access, /XYDataLabs-context-audit, or /XYDataLabs-validate-adrs
```

## Available Prompts

### `/XYDataLabs-day-complete`

Purpose:
- Routes end-of-day curriculum updates to the correct documents.
- Ensures progress tracking stays consistent.
- Helps prevent missing updates in curriculum, daily progress, and related docs.

Use when:
- A curriculum day is finished.
- You want guided document updates for learning progress.

### `/XYDataLabs-sql-local-access`

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

### `/XYDataLabs-setup-local`

Purpose:
- Bootstraps local development environment after a fresh `git clone`.
- Runs `scripts/setup-local.ps1` — creates `.env.local`, sets `dotnet user-secrets`, trusts HTTPS dev cert.
- Summarises next steps for VS F5 and Docker.

Use when:
- Setting up the project on a new or clean machine.
- `.env.local` is missing or you need to reset local passwords.

### `/XYDataLabs-completion-check`

Purpose:
- Runs a structured quality gate after completing any feature, task, script, or workflow.
- Checks six categories: documentation, guardrails, unit tests, integration/architecture tests, automation/CI-CD, and Copilot context.
- Fixes gaps immediately where possible; records any justified deferrals.

Use when:
- Finishing any feature, fix, script, or DevOps task before considering it done.
- You want a systematic answer to: "Have we documented, guardrailed, tested, and automated this properly?"
- As the final step in any ad-hoc task that doesn't use `/XYDataLabs-new-feature`.

Note: `/XYDataLabs-new-feature` has its own built-in review step (Code Reviewer agent). Run `/XYDataLabs-completion-check` for everything else.

### `/XYDataLabs-context-audit`

Purpose:
- Detects stale AI context by diffing memory files and copilot-instructions.md against the actual codebase.
- Catches drift in project tables, package references, directory layouts, and memory files.
- Reports findings with severity levels (HIGH/MEDIUM/LOW) and specific fix instructions.

Use when:
- Periodically (every few sessions or after major refactors).
- After renaming, adding, or removing projects or packages.
- When Copilot suggestions seem to reference outdated patterns or non-existent code.

### `/XYDataLabs-new-feature`

Purpose:
- Orchestrates end-to-end feature development with multitenant support.
- Enforces the mandatory 13-step workflow: requirements → entity → DTO → CQRS → DbContext → migration → controller → tests → build → review → commit → context check → payment verification (conditional).
- References all relevant instruction files at each step.

Use when:
- Adding a new entity with full CQRS, controller, EF migration, and tests.
- You want the agent to follow the established development workflow automatically.

Workflow:
1. Run `/XYDataLabs-new-feature` — it gathers requirements and starts implementation.
2. Steps 2-9 are handled by the **CQRS Backend** agent (entity through build+test).
3. Step 10: switch to **Code Reviewer** agent for architecture/security review.
4. Steps 11-12: commit and optionally run `/XYDataLabs-context-audit`.
5. Step 13 (conditional): if the feature touched payment code, run `/XYDataLabs-verify-payments`.

### `/XYDataLabs-validate-adrs`

Purpose:
- Runs both ADR validation checks locally before committing.
- Step 1: `scripts/validate-adr-frontmatter.ps1` — checks filename pattern, H1 format, `**Status:**` presence, and valid status word for every `ADR-NNN-.md` file.
- Step 2: `npx markdownlint-cli2` — checks markdown formatting using `.markdownlint.json`.

Use when:
- Before committing changes to any ADR file.
- After creating a new ADR and wanting to verify it conforms to the schema.
- To run the same checks locally that CI runs on push/PR.

Important notes:
- ADR-000 template is excluded from all checks.
- If `npx` is not available, Step 1 alone is sufficient before committing — markdownlint runs automatically in CI.
- To enable the CI counterpart: set `ADR_VALIDATION_ENABLED` repo variable to `true` in GitHub Settings → Secrets and variables → Actions → Variables tab → Repository variables. Off by default.

### `/XYDataLabs-verify-payments`

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

### `/XYDataLabs-verify-db-logs`

Purpose:
- End-to-end verification of a payment test run: physical log files **and** DB — in one pass.
- Reads today's `webapi-{env}-{date}.log` and `ui-{env}-{date}.log` filtered to today's date.
- Extracts OR prefix and charge IDs from the log automatically — no need to know the prefix upfront.
- Runs Q2 / Q5 / Q8 on the shared DB and Q2-B / Q5-B / Q9-B on the TenantC dedicated DB, all scoped to today.
- Produces a correlated pass/fail table: API log → UI log → DB for every charge ID.

Use when:
- After any payment test run on any environment/profile combination (dev/stg/prod × http/https docker, local dotnet run).
- When you want a single command that checks logs **and** DB without knowing the OR prefix in advance.
- When investigating missing callbacks or DB/log mismatches.

Prerequisites:
- At least one payment cycle completed today for the chosen environment.
- Docker containers or dotnet run have written today's log files to `logs/`.
- SQL Server is running locally (localhost:1433). `Resources/Docker/.env.local` exists with `LOCAL_SQL_PASSWORD`.

Note: For deep-dive queries (Q1, Q3, Q4, Q6, Q6a, Q7, Q8-B and per-tenant 3DS toggle), open `docs/runbooks/payment-db-verification.md`.

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Add a new feature end-to-end | `/XYDataLabs-new-feature` |
| Finish a learning day | `/XYDataLabs-day-complete` |
| Verify docs/tests/automation after any task | `/XYDataLabs-completion-check` |
| Set up local dev environment after git clone | `/XYDataLabs-setup-local` |
| Need local SSMS/sqlcmd access to Azure SQL | `/XYDataLabs-sql-local-access` |
| Check for stale AI context / memory drift | `/XYDataLabs-context-audit` |
| Verify payment DB records after a test run | `/XYDataLabs-verify-payments` |
| Verify payment run: physical logs + DB correlated | `/XYDataLabs-verify-db-logs` |
| Validate ADR markdown files before committing | `/XYDataLabs-validate-adrs` |

## Typical Workflows

```
[Starting a new feature]
└─ /XYDataLabs-new-feature  →  gathers requirements, orchestrates 12-step workflow
   └─ Steps 2-9: CQRS Backend agent (entity → build+test)
   └─ Step 10: Code Reviewer agent (architecture audit)
   └─ Step 11-12: commit → /XYDataLabs-context-audit

[After a coding/learning day]
└─ /XYDataLabs-day-complete  →  routes curriculum + command updates
   └─ [Optional] /XYDataLabs-context-audit  →  verify no stale references created

[After bootstrap or deploy]
└─ /XYDataLabs-sql-local-access  →  open firewall + get SSMS connection details
   └─ [When done] /XYDataLabs-sql-local-access  →  close firewall rule

[After a payment test run or payment feature change]
└─ /XYDataLabs-verify-payments  →  filtered DB queries for the most recent OR series (quick, DB only)
   └─ Fails? → open docs/runbooks/payment-db-verification.md for full diagnostics

[After a payment test run — full log + DB correlation in one pass]
└─ /XYDataLabs-verify-db-logs  →  reads today's log files, extracts charge IDs, runs DB queries, correlates all three
   └─ Any mismatch? → agent flags exact charge ID + likely cause (persistence fail / missed callback / file-lock)

[Before committing ADR changes]
└─ /XYDataLabs-validate-adrs  →  frontmatter schema check + markdownlint
   └─ All PASS? → safe to commit
   └─ Any FAIL? → fix violations listed, re-run

[After any task/fix/script/workflow (not covered by /new-feature)]
└─ /XYDataLabs-completion-check  →  6-category quality gate
   └─ Documented? Guardrailed? Unit tested? Integration tested? Automated? Context current?

[Fresh git clone / new machine]
└─ /XYDataLabs-setup-local  →  runs setup-local.ps1, summarises next steps
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
| `.github/prompts/XYDataLabs-day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/XYDataLabs-sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/prompts/XYDataLabs-context-audit.prompt.md` | Context drift detection audit |
| `.github/prompts/XYDataLabs-new-feature.prompt.md` | End-to-end feature development workflow |
| `.github/prompts/XYDataLabs-verify-payments.prompt.md` | Payment DB verification for a specific OR series |
| `.github/prompts/XYDataLabs-verify-db-logs.prompt.md` | End-to-end log + DB correlation for any env/profile combination |
| `.github/prompts/XYDataLabs-validate-adrs.prompt.md` | ADR frontmatter schema + markdownlint local validation |
| `.github/copilot-instructions.md` | Prompt index and quick usage reference |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt is added or its behavior changes, update this README and any bootstrap or troubleshooting docs that reference manual command sequences.