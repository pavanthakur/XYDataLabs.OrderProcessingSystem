# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

For repo-shared AI governance, use [docs/AI-OPERATING-MODEL.md](../../docs/AI-OPERATING-MODEL.md) as the canonical protocol and [docs/internal/DEFERRED-WORK-LOG.md](../../docs/internal/DEFERRED-WORK-LOG.md) as the shared deferral register.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /XYDataLabs-day-complete, /XYDataLabs-docker-start, /XYDataLabs-sql-local-access, /XYDataLabs-context-audit, or /XYDataLabs-validate-adrs
```

## Available Prompts

### `/XYDataLabs-day-complete`

Purpose:
- Routes end-of-day curriculum updates to the correct documents.
- Ensures progress tracking stays consistent, including architecture phase status surfaces.
- Helps prevent missing updates in curriculum, daily progress, and related docs.

Use when:
- A curriculum day is finished.
- A phase is being closed or frozen and all status surfaces must be aligned.
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

### `/XYDataLabs-docker-start`

Purpose:
- Launches the standard local run matrix through one interactive prompt.
- Maps operator intent to the supported Docker or local `dotnet run` startup profiles.
- Prints the correct API and UI URLs after startup.

Use when:
- You want the fastest supported way to start dev, staging-style, prod-style, or local profiles without remembering the exact command.
- You need to stop a running Docker stack from the same entry point.

### `/XYDataLabs-completion-check`

Purpose:
- Runs a structured quality gate after completing any feature, task, script, or workflow.
- Checks six categories: documentation, guardrails, unit tests, integration/architecture tests, automation/CI-CD, and Copilot context.
- Fixes gaps immediately where possible; records any justified deferrals in `docs/internal/DEFERRED-WORK-LOG.md`.

Use when:
- Finishing any feature, fix, script, or DevOps task before considering it done.
- You want a systematic answer to: "Have we documented, guardrailed, tested, and automated this properly?"
- As the final step in any ad-hoc task that doesn't use `/XYDataLabs-new-feature`.
- After a phase close/freeze when you want a second guardrail that status and roadmap surfaces stayed aligned.

Note: `/XYDataLabs-new-feature` has its own built-in review step (Code Reviewer agent). Run `/XYDataLabs-completion-check` for everything else.

Governance note:
- Use `.github/completion-check-rubric.md` to decide whether a gap is non-negotiable or can be deferred.

### `/XYDataLabs-context-audit`

Purpose:
- Detects stale AI context by diffing memory files and copilot-instructions.md against the actual codebase.
- Catches drift in project tables, package references, directory layouts, and memory files.
- Reports findings with severity levels (HIGH/MEDIUM/LOW) and specific fix instructions.

Use when:
- Periodically (every few sessions or after major refactors).
- After renaming, adding, or removing projects or packages.
- When Copilot suggestions seem to reference outdated patterns or non-existent code.
- After a phase close/freeze if you want a direct audit for phase-status and roadmap drift.

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
5. Step 13 (conditional): if the feature touched payment code, run `/XYDataLabs-verify-db-logs`.

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


### `/XYDataLabs-verify-db-logs`

Purpose:
- End-to-end verification of a payment test run: log data **and** DB — in one pass.
- **docker/local**: reads today's `webapi-{env}-{date}.log` and `ui-{env}-{date}.log` physical files.
- **azure**: queries App Insights KQL (`ai-orderprocessing-{env}`) for both API and UI callback traces.
- Extracts OR prefix and charge IDs from the log automatically — no need to know the prefix upfront.
- In Azure mode, derives a shared logical run prefix (for example `OR-1-2ndApr`) before running DB queries.
- In Azure mode, filters API/UI traces using both `cloud_RoleName` and the structured `customDimensions['Application']` property to reduce cross-app noise.
- Runs Q2 / Q5 / Q8 on the shared DB and Q2-B / Q5-B / Q9-B on the TenantC dedicated DB, all scoped to today.
- Produces a correlated pass/fail table: API log → UI log → DB for every charge ID.

Use when:
- After any payment test run on any environment/profile/runtime combination (dev/stg/prod × http/https × docker/local/azure).
- When you want a single command that checks logs **and** DB without knowing the OR prefix in advance.
- When investigating missing callbacks or DB/log mismatches.

Prerequisites:
- At least one payment cycle completed today for the chosen environment.
- **docker/local**: containers or dotnet run have written today's log files to `logs/`; `Resources/Docker/.env.local` exists with `LOCAL_SQL_PASSWORD`; SQL Server running locally (localhost:1433).
- **azure**: `az login` completed; App Insights resource exists (`ai-orderprocessing-{env}`); firewall open via `open-local-sql-firewall.ps1`; KV `secrets/get` permission granted (first-time only).

Azure-specific note:
- UI callback evidence is required only for tenants whose `Use3DSecure = 1`; non-3DS tenants are expected to complete with `ThreeDSecureStage = not_applicable` and may have no UI callback entry.

Repeat Azure rerun note:
- For deterministic reruns outside chat, use `scripts/verify-payment-run-azure.ps1` instead of rebuilding the App Insights and SQL commands by hand.

Note: For deep-dive queries (Q1, Q3, Q4, Q6, Q6a, Q7, Q8-B and per-tenant 3DS toggle), open `docs/runbooks/payment-db-verification.md`.

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Add a new feature end-to-end | `/XYDataLabs-new-feature` |
| Finish a learning day | `/XYDataLabs-day-complete` |
| Start Docker or local run profiles | `/XYDataLabs-docker-start` |
| Verify docs/tests/automation after any task | `/XYDataLabs-completion-check` |
| Set up local dev environment after git clone | `/XYDataLabs-setup-local` |
| Need local SSMS/sqlcmd access to Azure SQL | `/XYDataLabs-sql-local-access` |
| Check for stale AI context / memory drift | `/XYDataLabs-context-audit` |
| Verify payment run: physical logs + DB correlated | `/XYDataLabs-verify-db-logs "prod https docker"` or `/XYDataLabs-verify-db-logs "dev http azure"` |
| Validate ADR markdown files before committing | `/XYDataLabs-validate-adrs` |

## Typical Workflows

```
[Starting a new feature]
└─ /XYDataLabs-new-feature  →  gathers requirements, orchestrates 12-step workflow
   └─ Steps 2-9: CQRS Backend agent (entity → build+test)
   └─ Step 10: Code Reviewer agent (architecture audit)
   └─ Step 11-12: commit → /XYDataLabs-context-audit

[After a coding/learning day]
└─ /XYDataLabs-day-complete  →  routes curriculum + command + roadmap updates
   └─ [Optional] /XYDataLabs-context-audit  →  verify no stale references created

[After bootstrap or deploy]
└─ /XYDataLabs-sql-local-access  →  open firewall + get SSMS connection details
   └─ [When done] /XYDataLabs-sql-local-access  →  close firewall rule

[After a payment test run — log + DB correlation]
└─ /XYDataLabs-verify-db-logs "prod http docker"  →  reads today’s log files, extracts charge IDs, runs DB queries, correlates all three
   └─ Any mismatch? → agent flags exact charge ID + likely cause (persistence fail / missed callback / file-lock)

[Before committing ADR changes]
└─ /XYDataLabs-validate-adrs  →  frontmatter schema check + markdownlint
   └─ All PASS? → safe to commit
   └─ Any FAIL? → fix violations listed, re-run

[After any task/fix/script/workflow (not covered by /new-feature)]
└─ /XYDataLabs-completion-check  →  6-category quality gate
   └─ Documented? Guardrailed? Unit tested? Integration tested? Automated? Context current?

[After a phase close/freeze]
└─ /XYDataLabs-day-complete  →  routes curriculum + roadmap + status-surface updates
   └─ /XYDataLabs-completion-check  →  mandatory quality gate before commit
   └─ /XYDataLabs-context-audit  →  mandatory drift audit before commit

[Fresh git clone / new machine]
└─ /XYDataLabs-setup-local  →  runs setup-local.ps1, summarises next steps

[Start a local runtime profile]
└─ /XYDataLabs-docker-start  →  choose dev/stg/prod Docker or local dotnet run
   └─ Agent prints the correct API and UI URLs for the chosen option
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
| `docs/AI-OPERATING-MODEL.md` | Canonical protocol for shared AI customization, validation, and deferrals |
| `docs/internal/DEFERRED-WORK-LOG.md` | Shared register for justified deferred work |
| `.github/completion-check-rubric.md` | Pass/defer rubric for `/XYDataLabs-completion-check` |
| `.github/prompts/XYDataLabs-day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/XYDataLabs-docker-start.prompt.md` | Interactive launcher for Docker and local runtime profiles |
| `.github/prompts/XYDataLabs-sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/prompts/XYDataLabs-context-audit.prompt.md` | Context drift detection audit |
| `.github/prompts/XYDataLabs-new-feature.prompt.md` | End-to-end feature development workflow |
| `.github/prompts/XYDataLabs-verify-db-logs.prompt.md` | End-to-end log + DB correlation for any env/profile combination |
| `.github/prompts/XYDataLabs-validate-adrs.prompt.md` | ADR frontmatter schema + markdownlint local validation |
| `.github/copilot-instructions.md` | Prompt index and quick usage reference |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt is added or its behavior changes, update this README and any bootstrap or troubleshooting docs that reference manual command sequences.
- When a prompt, agent, or instruction changes, run `pwsh scripts/validate-ai-customization.ps1` before merge.