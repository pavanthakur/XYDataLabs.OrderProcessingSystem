# Prompt README

This folder contains reusable VS Code Chat agent prompts for common operational tasks in this repository.

These prompts are intended to reduce missed post-deployment steps, standardize repeated workflows, and give a consistent entry point for tasks that are easy to forget during Azure setup, validation, and daily learning progress updates.

Follow [AGENTS.md](../../AGENTS.md) for shared engineering behavior. This README owns prompt/agent discovery; [the skill index](../skills/README.md) owns skill discovery. For governance/routing use [docs/AI-OPERATING-MODEL.md](../../docs/AI-OPERATING-MODEL.md), and use [docs/internal/DEFERRED-WORK-LOG.md](../../docs/internal/DEFERRED-WORK-LOG.md) for justified deferrals. Client entries link these owners instead of repeating every asset.

Use [.github/instructions/ai-operating.instructions.md](../instructions/ai-operating.instructions.md) as the shared local slice-sizing and drift-control rule file.

## How To Use

1. Open VS Code Chat.
2. Switch to Agent mode.
3. Type the prompt command exactly as shown below.

Quick tip:

```text
Ctrl+Shift+I → Agent mode → type /XYDataLabs-day-start, /XYDataLabs-day-complete, /XYDataLabs-sql-local-access, /XYDataLabs-setup-local, /XYDataLabs-docker-start, /XYDataLabs-payment-automation, /XYDataLabs-completion-check, /XYDataLabs-context-audit, /XYDataLabs-new-feature, /XYDataLabs-validate-adrs, /XYDataLabs-verify-db-logs, /azure-deploy-test, /phase-handoffs/phase-09-microservices-architecture, or /phase-handoffs/phase-09-microservices-implementation
```

## Available Prompts

### `/XYDataLabs-day-start`

Purpose:
- Reads repository-relative `memories/repo/active-work.md` as a checkpoint, with bounded read-only checks of Git state, the relevant plan and material evidence.
- Reports active/pause state, historical or unavailable evidence, next actions and key paths without broad rediscovery or automatic full test runs.

Use when:
- Beginning a new work session in this repository.
- Returning after a context reset or a long gap and you want the current phase and next action first.

### `/XYDataLabs-day-complete`

Purpose:
- Routes end-of-day curriculum updates to the correct documents.
- Applies only routes relevant to approved work; a pause or governance-only task does not mark curriculum/phase work complete.
- Refreshes the concise handoff after material approved work, with actual validation/evidence limits; Git writes, snapshots and consequential validation require explicit authorization.
- Ensures progress tracking stays consistent, including architecture phase status surfaces.
- Makes payment automation validation mandatory during phase closeout when the work touched `automation/` or the payment automation workflow surfaces.
- Helps prevent missing updates in curriculum, daily progress, and related docs.
- For Phase 10 local baseline or transport closeout, keep `Phase 10.1` and the next active `Phase 10.2` slice aligned across the roadmap, checklist, and status trackers before declaring completion.
- For Phase 9 closeout, verify the numbered VS Code task sequence for both `local-http` and `docker-dev-http` is documented and aligned before declaring completion.

Use when:
- A curriculum day is finished.
- A phase is being closed or frozen and all status surfaces must be aligned.
- A phase closeout touched payment automation and you need the dry-run matrix enforced before commit.
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

### `/XYDataLabs-payment-automation`

Purpose:
- Launches the separate payment automation workspace from one standard interactive entry point.
- Maps operator intent to supported local, Docker, and Azure single-target runs plus local, Docker, and Azure matrix automation runs.
- Supports dry runs, tenant filtering, headed mode, and optional keep-local-sessions behavior for local targets.

Use when:
- You want to run the automation workspace without remembering the exact npm command and flags.
- You want a repeatable path for local payment-journey execution before or during backend Phase 8 work.
- You want the same entry point to run `docker-dev-*`, `docker-stg-*`, or `docker-prod-*` payment automation targets directly.
- You want the same entry point to run `azure-dev`, `azure-stg`, or `azure-prod` payment automation targets after Azure deployment and validate via App Insights/Azure SQL.
- You want the slash-workflow companion to the existing `/XYDataLabs-verify-db-logs` evidence prompt.

### `/XYDataLabs-completion-check`

Purpose:
- Runs a structured quality gate after completing any feature, task, script, or workflow.
- Selects applicable safe checks from the changed scope; governance metadata does not automatically trigger application suites or consequential runtime operations. Required unapproved/unavailable checks remain BLOCKED/NOT TESTED.
- Checks six categories: documentation, guardrails, unit tests, integration/architecture tests, automation/CI-CD, and Copilot context.
- Fixes gaps immediately where possible; records any justified deferrals in `docs/internal/DEFERRED-WORK-LOG.md`.
- For phase checkpoints, compare the relevant approved plan and actual evidence; do not hardcode an old next slice or infer completion from historical results.
- For Phase 9 closeout, also verify the numbered VS Code task sequence for both `local-http` and `docker-dev-http` is documented and aligned with the closeout roadmap.

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
- Verify the current approved phase plan/checkpoint and its evidence limits rather than hardcoding an old next slice or treating paused work as authorized.

Use when:
- Periodically (every few sessions or after major refactors).
- After renaming, adding, or removing projects or packages.
- When Copilot suggestions seem to reference outdated patterns or non-existent code.
- After a phase close/freeze if you want a direct audit for phase-status and roadmap drift.

### `/XYDataLabs-new-feature`

Purpose:
- Orchestrates end-to-end feature development with multitenant support.
- Enforces the mandatory end-to-end workflow: requirements and surface classification → entity → DTO → CQRS → DbContext → migration → controller → tests → build → review → commit preparation → context refresh → payment verification (conditional).
- Routes frontend work to `frontend-feature-development` and payment-provider work to `payment-provider-development` without duplicating those skills in the prompt.
- References the relevant instruction files and validation commands for the approved backend, frontend, and full-stack scope.

Use when:
- Adding a new entity with full CQRS, controller, EF migration, and tests.
- You want the agent to follow the established development workflow automatically.

Workflow:
1. Run `/XYDataLabs-new-feature` — it gathers requirements and confirms the plan before implementing only approved scope.
2. Backend Steps 2-9 are handled by the **CQRS Backend** agent (entity through build+test); frontend scope additionally follows the **Frontend Feature Development** skill and frontend validation commands.
3. Step 10: switch to **Code Reviewer** agent for architecture/security review.
4. Steps 11-12: present the reviewed diff/file list and proposed commit message; refresh relevant context. No staging/commit/push without explicit authorization.
5. Step 13 (conditional): payment-related changes require `/XYDataLabs-verify-db-logs` evidence before closeout/commit; obtain scoped approval for consequential access and report unavailable/unapproved checks as BLOCKED/NOT TESTED, not PASS.

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
- **docker/local**: reads today's `webapi-{env}-{date}.log` physical API log and derives UI evidence from browser-originated `ui_payment_*` telemetry captured in that same API log.
- **azure**: queries App Insights KQL (`ai-orderprocessing-{env}`) for both API and UI callback traces.
- The prompt is script-first by runtime: it should delegate to the matching verifier script before falling back to manual investigation steps.
- Extracts OR prefix and charge IDs from the log automatically — no need to know the prefix upfront.
- In Azure mode, derives a shared logical run prefix (for example `OR-1-2ndApr`) before running DB queries.
- In Azure mode, filters API/UI traces using both `cloud_RoleName` and the structured `customDimensions['Application']` property to reduce cross-app noise.
- Runs Q2 / Q5 / Q8 on the shared DB and Q2-B / Q5-B / Q9-B on the TenantC dedicated DB, all scoped to today.
- Produces a correlated pass/fail table: API log → UI telemetry → DB for every charge ID.

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

Repeat physical rerun note:
- For deterministic reruns outside chat, use `scripts/verify-payment-run-physical.ps1` for `docker` and `local` runtimes.

Prompt routing note:
- `/XYDataLabs-verify-db-logs` should call the same runtime-specific verifier script internally unless the user explicitly asks for the raw manual investigation path or the script needs debugging.
- User-facing output should be the formatted pass/fail table first; use JSON only when the user explicitly asks for machine-readable output or when temporary parsing is needed behind the scenes.

Note: For deep-dive queries (Q1, Q3, Q4, Q6, Q6a, Q7, Q8-B and per-tenant 3DS toggle), open `docs/runbooks/payment-db-verification.md`.

### `/azure-deploy-test`

Purpose:
- Guides a safe Azure deploy-and-smoke session for the active transport stack.
- Explains the split between Bicep infrastructure and GitHub Actions orchestration.
- Keeps the operator focused on `what-if`, deploy, output verification, transport smoke, and replay smoke.

Use when:
- You are preparing or reviewing an Azure deployment for the active transport stack.
- You need a command-first explanation of what to commit, what to ignore, and what to verify after deploy.
- You want a standard answer for whether a workflow change is needed or whether the existing workflow is enough.

Important notes:
- `infra/main.phase10.bicep` is the source of truth for the current transport slice.
- GitHub Actions should orchestrate the deployment, not model the Azure resources.
- Always use the deployment outputs before verification or smoke tests.
- Keep `.azure-cli` and other local auth caches out of the commit.

Workflow:
1. Read `docs/guides/deployment/azure-deploy-smoke.md`.
2. Run `az deployment sub what-if` against `infra/main.phase10.bicep`.
3. Deploy with `az deployment sub create`.
4. Verify Service Bus, Function App, Container Apps, Log Analytics, Managed Environment, and App Insights using deployment outputs.
5. Run the transport publish/consume smoke and replay smoke.
6. Update docs or workflow YAML only if the deployment shape or automation behavior changed.

### Phase Handoff Prompts

Purpose:
- Stores phase-specific architect/developer handoff prompts for external or role-specialized models.
- Keeps AI handoff guidelines out of the canonical human-facing `docs/` tree.
- Gives each major phase a repeatable two-prompt structure: architecture strategy first, implementation slices second.

Use when:
- Starting a major architecture phase that benefits from an architect model and developer model handoff.
- Preparing a model-specific prompt for Continue or another local model workflow.
- Reusing Phase 9 YARP module-isolation guidance for Deepseek 14B/64k or Qwen 14B/64k.

Current prompts:
- `phase-handoffs/phase-09-microservices-architecture.prompt.md` — Deepseek 14B/64k architect prompt for ADR-021 and module-isolation blueprint.
- `phase-handoffs/phase-09-microservices-implementation.prompt.md` — Qwen 14B/64k developer prompt for narrow Phase 9 implementation slices.
- `phase-handoffs/local-model-phase-handoff-guide.md` — standard local Ollama/Continue/Cline model-routing and validation guide for phase work.

## Which Prompt Should I Use?

| Scenario | Prompt |
|----------|--------|
| Start a session from active handoff | `/XYDataLabs-day-start` |
| Add a new feature end-to-end | `/XYDataLabs-new-feature` |
| Finish a learning day | `/XYDataLabs-day-complete` |
| Start Docker or local run profiles | `/XYDataLabs-docker-start` |
| Run payment automation workspace flows | `/XYDataLabs-payment-automation` |
| Verify docs/tests/automation after any task | `/XYDataLabs-completion-check` |
| Set up local dev environment after git clone | `/XYDataLabs-setup-local` |
| Need local SSMS/sqlcmd access to Azure SQL | `/XYDataLabs-sql-local-access` |
| Check for stale AI context / memory drift | `/XYDataLabs-context-audit` |
| Verify payment run: API log + UI telemetry + DB correlated | `/XYDataLabs-verify-db-logs "prod https docker"` or `/XYDataLabs-verify-db-logs "dev http azure"` |
| Validate ADR markdown files before committing | `/XYDataLabs-validate-adrs` |
| Prepare external-model phase handoff prompts | `/phase-handoffs/phase-09-microservices-architecture` then `/phase-handoffs/phase-09-microservices-implementation` |

## Typical Workflows

```
[Starting a new feature]
└─ /XYDataLabs-new-feature  →  confirms approved scope, orchestrates 13-step workflow
   └─ Steps 2-9: CQRS Backend agent (entity → build+test)
   └─ Step 10: Code Reviewer agent (architecture audit)
   └─ Step 11-12: prepare commit (approval required) → refresh relevant context
   └─ Step 13: conditional payment evidence before closeout/commit (scoped approval required)

[After a coding/learning day]
└─ /XYDataLabs-day-complete  →  routes only relevant approved docs/handoff updates; no automatic Git writes
   └─ [Optional] /XYDataLabs-context-audit  →  verify no stale references created

[After bootstrap or deploy]
└─ /XYDataLabs-sql-local-access  →  open firewall + get SSMS connection details
   └─ [When done] /XYDataLabs-sql-local-access  →  close firewall rule

[After a payment test run — log + DB correlation]
└─ /XYDataLabs-verify-db-logs "prod http docker"  →  reads today’s API log, correlates browser UI telemetry, runs DB queries, correlates all three
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
   └─ [If automation scope changed] run automation dry-run matrix and record results
   └─ [If Phase 9 closeout] verify `local-http` + `docker-dev-http` VS Code task sequences
   └─ /XYDataLabs-completion-check  →  mandatory quality gate before commit
   └─ /XYDataLabs-context-audit  →  mandatory drift audit before commit

[Fresh git clone / new machine]
└─ /XYDataLabs-setup-local  →  runs setup-local.ps1, summarises next steps

[Start a local runtime profile]
└─ /XYDataLabs-docker-start  →  choose dev/stg/prod Docker or local dotnet run
   └─ Agent prints the correct API and UI URLs for the chosen option

[Run payment automation]
└─ /XYDataLabs-payment-automation  →  choose local, Docker, or Azure target mode, or local/Docker/Azure matrix mode
   └─ Agent runs the correct automation workspace command with tenant and headed/keep-session options
   └─ For post-run evidence correlation, follow with /XYDataLabs-verify-db-logs when needed
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
| `AGENTS.md` | Shared short engineering behavior and task-context routing |
| `docs/AI-OPERATING-MODEL.md` | Canonical protocol for shared AI customization, validation, and deferrals |
| `docs/internal/DEFERRED-WORK-LOG.md` | Shared register for justified deferred work |
| `.github/completion-check-rubric.md` | Pass/defer rubric for `/XYDataLabs-completion-check` |
| `.github/prompts/XYDataLabs-completion-check.prompt.md` | Repo-standard task closeout and quality gate |
| `.github/prompts/XYDataLabs-day-complete.prompt.md` | Day completion routing workflow |
| `.github/prompts/XYDataLabs-docker-start.prompt.md` | Interactive launcher for Docker and local runtime profiles |
| `.github/prompts/XYDataLabs-payment-automation.prompt.md` | Interactive launcher for the separate payment automation workspace |
| `.github/prompts/XYDataLabs-setup-local.prompt.md` | First-clone local environment bootstrap workflow |
| `.github/prompts/XYDataLabs-sql-local-access.prompt.md` | SQL firewall open/close workflow |
| `.github/prompts/XYDataLabs-context-audit.prompt.md` | Context drift detection audit |
| `.github/prompts/XYDataLabs-new-feature.prompt.md` | End-to-end feature development workflow |
| `.github/prompts/XYDataLabs-verify-db-logs.prompt.md` | End-to-end log + DB correlation for any env/profile combination |
| `.github/prompts/XYDataLabs-validate-adrs.prompt.md` | ADR frontmatter schema + markdownlint local validation |
| `scripts/verify-payment-run-physical.ps1` | Deterministic physical-log rerun for docker/local payment verification |
| `scripts/verify-payment-run-azure.ps1` | Deterministic Azure rerun for App Insights + Azure SQL payment verification |
| `.github/copilot-instructions.md` | Thin Copilot-specific entry linking shared rules and owning indexes |

## Operational Guidance

- Start with `dev` before promoting changes to `staging` and `main`.
- Use prompts to avoid missing required manual post-deploy steps.
- When a prompt/agent is added or its behavior changes, update this owning index and any affected procedure docs; keep client entry links valid without copying the full inventory there.
- When a prompt, agent, or instruction changes, run `pwsh scripts/validate-ai-customization.ps1` before merge.
