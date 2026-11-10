---
agent: agent
description: "Profile-scoped new-feature workflow for backend, frontend or full-stack work: approve requirements, select applicable architecture and tenant safeguards, implement affected surfaces, validate and prepare a reviewed handoff without automatic Git writes"
---

# New Feature — End-to-End Development Workflow

The user wants to add a new feature. Follow the applicable workflow in order after classifying its surfaces. Do not skip applicable gates; identify inapplicable steps with a scope-based reason rather than executing unrelated work or reporting it as PASS.

## Scope, Approval And Evidence

- Inspect Git status/HEAD and the relevant plan, code and tests through bounded read-only checks. The repository handoff is navigation, not proof; retain historical environment/scope/revision limits and report unavailable evidence as unavailable, not PASS.
- Implement only the approved feature plan. Begin with targeted validation, then satisfy the applicable broader acceptance gates; do not run a full suite merely to orient the session.
- Before tests or commands, inspect their side effects. Database queries/mutations, Docker lifecycle/reset, provider transactions/refunds and Azure/directory operations require explicit scoped approval. Generating/reviewing a migration under the approved feature plan does not authorize applying it to a database. Destructive resets need immediate per-operation approval.
- Git staging, commit, push, merge, tag/branch creation and other Git writes require explicit authorization. Prepare the reviewed diff/file list and proposed commands; passing tests does not grant Git authorization. Preserve unrelated changes and stop to reconcile overlapping work.
- If a required check cannot run safely or lacks approval/evidence, report BLOCKED/NOT TESTED and retain the acceptance requirement. Do not silently waive it, start another phase or treat the feature as complete.
- If the approved task changes shared AI instructions, prompts, agents, skills, or governance documentation, apply the four gates from `docs/AI-OPERATING-MODEL.md`: complete discovery and the knowledge-preservation matrix first, present the design and exact file list for approval, then implement and perform acceptance. Do not treat this feature prompt as implementation authorization for AI governance changes.

## Step 1: Gather Requirements

Ask the user:
1. "What is the feature? (e.g., Shipment tracking, Invoice management)"
2. "Does this require a new or changed backend entity? If so, what properties are needed?"
3. "For a backend entity change, is it tenant-owned? (default: yes — all business entities require TenantId)"
4. "For a backend entity change, does it relate to an existing entity? (e.g., FK to Order, Customer)"
5. "Does this feature add or rename any deployed runtime dependency or automation-visible Azure service? (e.g., Container App, Function App, queue/topic/subscription, Key Vault secret family, App Insights dependency, gateway/UI endpoint)"
6. "Does this feature change the React frontend, shared frontend packages, API SDK contracts, tenant-session behavior, payment UI, or browser navigation? (default: no)"

Once answered, confirm the plan before proceeding.

## Step 1B: Classify Feature Surfaces

Before creating backend files, classify the approved scope as backend-only, frontend-only, or full-stack:

- Backend work follows Steps 2–10 through the **CQRS Backend** skill and this prompt.
- Frontend work follows the **Frontend Feature Development** skill and `.github/instructions/frontend.instructions.md`.
- Payment-provider or payment-flow work also follows the **Payment Provider Development** skill.
- Full-stack work must keep backend DTO/API changes, the frontend API SDK, tenant-session behavior, UI tests, and runtime validation synchronized.
- Do not force a frontend-only task through the backend entity/migration sequence. Do not treat a frontend mock or page test as proof of backend or provider acceptance.
- If a new reusable workflow is proposed, prefer orchestrating an existing specialist skill over creating a duplicate feature-development skill; justify any new skill against the skill quality contract.

Apply these validation profiles:

| Profile | Applicable workflow |
|---|---|
| Backend-only | Steps 2–8 for affected backend surfaces, Step 8B when runtime/deployment impact exists, backend validation in Step 9, and applicable review/handoff gates |
| Frontend-only | Frontend skill and checks in Step 9; omit Steps 2–8 and backend-only review items unless their surfaces are affected. Do not create an entity/migration or require the .NET solution suite for an isolated UI change |
| Full-stack | Both affected frontend and backend lanes, coordinated contracts, and applicable runtime/payment checks |

Requirements, plan approval, applicable Step 10 review, commit preparation and context refresh apply to every profile. Step 8B applies to any profile with runtime/deployment impact; it does not authorize deployment. Step 13 remains required when payment behavior is affected. If an apparent frontend-only task changes backend contracts or behavior, reclassify it before implementation; profile selection cannot waive an applicable security, isolation or payment gate.

## Step 2: Domain Entity

Create the entity in `XYDataLabs.OrderProcessingSystem.Domain/Entities/`.

Rules (from `clean-architecture.instructions.md` + `multitenant-payment-schema.instructions.md`):
- Entity MUST inherit from appropriate base class or implement required properties
- Tenant-owned entities MUST have `public int TenantId { get; set; }` as FK to `Tenants.Id`
- ZERO infrastructure imports in Domain — no EF Core, no Azure SDK
- Use data annotations: `[Required]`, `[MaxLength()]` where appropriate
- Add navigation property to `Tenant` if following existing entity patterns

## Step 3: DTO

Create the DTO in `XYDataLabs.OrderProcessingSystem.Application/DTO/`.

Rules:
- DTO must NOT expose `TenantId` (resolved from request context, not client input)
- Map only properties the API consumer needs
- Use the same naming convention as existing DTOs in the project

## Step 4: CQRS Command/Query + Handler

Create in `XYDataLabs.OrderProcessingSystem.Application/Features/{FeatureName}/Commands/` or `Queries/`.

Rules (from `clean-architecture.instructions.md`):
- Use hand-rolled CQRS: implement `ICommand<T>` / `IQuery<T>` and `ICommandHandler<,>` / `IQueryHandler<,>`
- Do NOT use MediatR — this project uses `IDispatcher`
- Handler returns `Result<T>` from SharedKernel — do NOT throw exceptions for expected failures
- Handler must NOT import Infrastructure namespaces directly — use interfaces (e.g., `IRepository<T>`, DbContext via constructor injection)
- Register handler in DI if required by the project's registration pattern

## Step 5: DbContext Configuration

Update `XYDataLabs.OrderProcessingSystem.Infrastructure/DataContext/OrderProcessingSystemDbContext.cs`.

Rules (from `ef-migrations.instructions.md` + `multitenant-payment-schema.instructions.md`):
- Add `public DbSet<EntityName> EntityNames { get; set; }` property
- Add the **same** `DbSet<EntityName>` to `IAppDbContext` in `Application/Abstractions/IAppDbContext.cs` — architecture tests enforce parity
- In `OnModelCreating()`, add `ConfigureTenantOwnership<EntityName>(modelBuilder);` — this single call configures:
  - FK to `Tenants(Id)`
  - Global query filter on `TenantId`
  - `DeleteBehavior.Restrict`
- Do NOT manually configure these three concerns individually — always use `ConfigureTenantOwnership<T>()`
- Add any entity-specific fluent configuration (e.g. `HasMaxLength()`, composite indexes beyond TenantId)
- Follow the same configuration pattern as existing entities (e.g., `CardTransaction`, `CustomerOrder`)

> ⚠ **Conditional — startup behavior across environments:** EF auto-migration at startup is gated by `!isAzure` in `Program.cs` — it runs in local and Docker dev/stg/prod contexts but is **suppressed** in Azure (cells 5–7 in the ADR-010 matrix). If this entity relies on seeding data via `DbInitializer` at startup, confirm the Azure case is handled — Azure will not have just run the migration automatically. Reference: `docs/architecture/decisions/ADR-010-runtime-environment-detection.md`.

## Step 6: EF Migration

Generate and verify the migration.

Commands to run (in order):
```powershell
# 1. Generate migration
dotnet ef migrations add Add{EntityName} `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext

# 2. REVIEW: Open the generated migration file and verify Up()/Down() are correct

# 3. Drift check — generate temp migration, verify it's empty
dotnet ef migrations add DriftCheck `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext

# 4. Remove drift check migration
dotnet ef migrations remove `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext
```

Rules (from `ef-migrations.instructions.md`):
- Include all three files in the reviewed change set: migration `.cs`, `.Designer.cs`, and updated `ModelSnapshot.cs`; committing them requires explicit authorization
- Never manually edit the ModelSnapshot
- Verify `Down()` is reversible
- Update `ef-migrations.instructions.md` "Applied Migrations" section with the new migration

## Step 7: API Controller

Create in `XYDataLabs.OrderProcessingSystem.API/Controllers/`.

Rules:
- Thin controller — dispatch to command/query handlers via `IDispatcher`
- No business logic in controllers
- No Infrastructure namespace imports
- Follow existing controller patterns (route naming, response types)

## Step 7B: API Surface Tenant Compliance

Before proceeding to tests, verify the controller and request DTOs comply with tenant rules:

- **No action parameter** may be named `TenantId`, `TenantCode`, or `TenantExternalId`
- **No request DTO property** may be named `TenantId`, `TenantCode`, or `TenantExternalId`
- Tenant context is resolved from the `X-Tenant-Code` header via middleware — never from client input
- Response DTOs must NOT expose `TenantId` (internal FK only)
- The architecture test `Controllers_Should_Not_Accept_TenantId_Or_TenantCode_Parameters` enforces this at CI

## Step 8: Tests

### Unit Tests
Create handler tests in `tests/XYDataLabs.OrderProcessingSystem.Application.Tests/`.
- Test happy path and failure scenarios
- Use Moq for dependencies, Bogus for test data if already in use

### Architecture Tests
Add to `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/`:
- Entity has `TenantId` property
- Entity does not have forbidden properties (follow `CardTransaction_Should_Not_Store_Raw_Card_Data` pattern)
- Layer dependency tests (if not already covered by existing generic tests)

**Note:** The following are enforced automatically by existing dynamic guardrail tests — no per-entity tests needed:
- `All_TenantOwned_Entities_Should_Inherit_AuditBase` — checks all IAppDbContext entities
- `All_TenantOwned_Entities_Should_Have_Global_Query_Filter` — checks ConfigureTenantOwnership was called
- `All_TenantOwned_Entities_Should_Have_FK_To_Tenants` — checks FK to Tenants(Id)
- `IAppDbContext_DbSets_Must_Match_OrderProcessingSystemDbContext_Minus_Tenant` — checks parity
- `Controllers_Should_Not_Accept_TenantId_Or_TenantCode_Parameters` — checks API surface
- `IgnoreQueryFilters_Usage_Must_Be_In_Allow_List_Only` — catches unapproved filter bypass
- `All_CQRS_Handlers_Must_Return_Result_T` — ensures Result<T> pattern

> **Conditional — `Program.cs` environment gate change:** If this feature modifies any `isDocker`, `isAzure`, `profileSuffix`, or `runtimeSuffix` gate in `Program.cs`:
> 1. **Extract** the gate logic to a static helper in `API/Helpers/` or `SharedKernel/` so it is unit-testable (top-level statements cannot be tested directly)
> 2. **Add `[Theory]` unit tests** covering all relevant boolean input combinations — reference the 7-cell matrix in ADR-010 for the full set
> 3. **Add `WebApplicationFactory` integration tests** for each behavioral gate (Swagger availability, CORS header content, developer exception page, EF migration trigger) — set `ASPNETCORE_ENVIRONMENT`, `DOTNET_RUNNING_IN_CONTAINER`, `WEBSITE_SITE_NAME` as env vars and assert the output differs as expected per cell
> 4. **Add a row** to the ADR-010 Feature Gate Inventory for the new gate
>
> This is the same class of gap as the `TransactionReferenceId` bug (commit `49077f3`) — a code path with no test. Reference: `docs/architecture/decisions/ADR-010-runtime-environment-detection.md`

## Step 8B: Azure Runtime/Automation Impact Check (conditional)

Run this step if the feature adds or renames any deployed runtime dependency, automation-visible endpoint, background worker, Azure Function, queue/topic/subscription, payment/provider dependency, Key Vault secret family, App Insights dependency, gateway route, or UI/API runtime target.

Required update set:
- Add explicit metadata for `azure-dev`, `azure-stg`, and `azure-prod` in `automation/config/runtime-targets.json`.
- Update `automation/src/contracts/runtime-target-catalog.ts` when a new runtime-target field is introduced.
- Update the owning workflow/script so Actions 2/3/4 or verifier automation reads the value from `runtime-targets.json` or receives workflow outputs derived from it.
- Extend `Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` so future hardcoded resource-name regressions fail locally.

Rules:
- Do NOT commit generated Azure Container Apps FQDNs, revision names, random suffixes, GUIDs, or one-run discovery output into `runtime-targets.json`.
- Stable configured resource names are allowed in `runtime-targets.json`; generated runtime values must be discovered at execution time from Azure control plane or workflow outputs.
- Deployment/IaC may create resources from suffix parameters; post-deploy automation validation must be driven by `runtime-targets.json`.

## Step 9: Build + Test

After targeted checks, satisfy the validation lanes for the approved profile below. Inspect their configuration and side effects first; do not run database/provider/cloud operations without scoped approval. Report a missing required run as BLOCKED/NOT TESTED, not a waived or passed gate.

**Frontend lane — frontend-only and full-stack:** run the affected frontend checks from `frontend/`:

```powershell
npm run typecheck
npm run test:web
npm run build
```

Run browser verification when navigation, callbacks, or visible payment behavior changes. Report unavailable browser or runtime evidence as BLOCKED/NOT TESTED.

**Backend lane — backend-only and full-stack:** retain the solution build/test gate after targeted backend checks:
```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln
dotnet test XYDataLabs.OrderProcessingSystem.sln --no-build
```

All applicable tests must pass before proceeding, or retain an explicitly permitted, recorded deferral under the completion rubric. An unrelated lane is not applicable, not PASS; an unavailable required lane is BLOCKED/NOT TESTED.

## Step 10: Review

Before committing, perform a self-review against this checklist. Apply backend entity/schema/handler items only when those surfaces changed; a frontend-only task does not need a migration, query filter or handler. Security, scope and relevant contract/test checks remain required for every profile.

| Check | Rule |
|-------|------|
| TenantId FK present? | All tenant-owned entities require `TenantId int NOT NULL` → `Tenants.Id` |
| Global query filter? | `.HasQueryFilter(e => e.TenantId == _tenantProvider.TenantId)` |
| Composite index? | `(TenantId, <lookup field>)` index defined |
| No layer violations? | Domain/Application have zero Infrastructure imports |
| No raw secrets/PII? | No card numbers, CVV, connection strings in entity |
| Result<T> pattern? | Handler returns `Result<T>`, not throwing exceptions |
| DTO excludes TenantId? | TenantId is never exposed to API consumers |
| Migration reviewed? | Up() and Down() are correct and reversible |
| Drift check passed? | Temp migration was empty |
| ConfigureTenantOwnership called? | Entity registered in `ConfigureTenantOwnership<T>()` — not manual FK/filter/delete config |
| IAppDbContext updated? | `DbSet<T>` added to both concrete DbContext and `IAppDbContext` interface |
| No tenant params in controller? | No `TenantId`/`TenantCode`/`TenantExternalId` in action params or request DTOs |
| Applicable tests pass? | Required profile lanes pass; retain explicit unavailable/blocked outcomes and only permitted recorded deferrals |
| Frontend contract and tests? | SDK/types, component tests, typecheck, build, and required browser checks are aligned for frontend scope |
| Azure runtime target impact handled? | New automation-visible Azure dependencies update `runtime-targets.json`, TypeScript contract, owning workflow/script, and Phase 10 environment contract validator together |

## Step 11: Prepare Commit — Explicit Approval Required

Review `git status --short` and the diff. Present the exact intended file list, relevant validation results/limitations, and a suggested commit message:

```text
Add {EntityName} entity with multitenant CQRS and EF migration

- Domain: {EntityName} entity with TenantId FK
- Application: Create/Get commands+handlers, DTO
- Infrastructure: DbContext config, migration, composite index
- API: {EntityName}Controller with dispatch endpoints
- Tests: handler unit tests + architecture tenant compliance
```

This is preparation only: do not stage or commit automatically. After explicit authorization, stage only reviewed paths (not unrelated work), recheck the staged diff and run the approved Git operation. Commit permission is not push, merge, tag, deployment or payment-run permission. Do not execute a commit until all required validation for the approved feature, including Step 13 when applicable, is satisfied or an allowed deferral is recorded.

## Step 12: Refresh Relevant Context

After material approved work, refresh the concise repository-relative `memories/repo/active-work.md` with observed changes, validation commands/results, evidence scope/limits and one next action. Keep it under 8 KiB; use revision UNKNOWN when evidence is unbound, and preserve unresolved constraints and unrelated work. Do not write personal/global memory or duplicate the phase roadmap. A read-only question does not require an update.

If this is a significant feature, perform the relevant `/XYDataLabs-context-audit` checks against current code/evidence to verify instruction files still reflect the codebase. No broad audit or consequential validation is authorized merely by loading this prompt.

## Step 13: Payment Verification (conditional)

**Run this step only if the feature touched any of:**
- `Application/Features/Payments/`
- `XYDataLabs.OpenPayAdapter/`
- `Domain/Entities/CardTransaction*`, `PayinLog*`, `BillingCustomer*`, `PaymentProvider*`, `TransactionStatusHistory*`
- `Infrastructure/` payment-related data access or seeding

**Action:** The applicable `/XYDataLabs-verify-db-logs` evidence remains required before feature closeout/commit. Inspect its commands and obtain explicit scoped approval for database/provider/cloud access before execution; it does not authorize a new charge, refund, reset or deployment. Correlate actual logs and DB records for the selected runtime, and verify no data isolation or schema regression. Confirm the ADR-010 log filename/sink selection only from observed evidence; if unavailable or unapproved, leave the gate BLOCKED/NOT TESTED rather than infer PASS.

Finish with the reviewed diff, actual validation outcomes, unresolved findings and proposed next action. Do not automatically commit, push or start the next phase.
