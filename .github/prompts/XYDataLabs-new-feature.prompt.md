---
agent: agent
description: "Mandatory 13-step end-to-end workflow for a new feature — gathers requirements, creates Domain entity (TenantId enforced), CQRS command/query handlers, controller endpoint, EF Core migration, unit + integration tests, architecture test guard, ADR-010 runtime gate, and a commit-ready completion check"
---

# New Feature — End-to-End Development Workflow

The user wants to add a new feature. Follow this mandatory workflow in order. Do NOT skip steps. Do NOT proceed to the next step until the current step is verified.

## Step 1: Gather Requirements

Ask the user:
1. "What is the feature? (e.g., Shipment tracking, Invoice management)"
2. "What properties does the main entity need?"
3. "Is this entity tenant-owned? (default: yes — all business entities require TenantId)"
4. "Does it relate to any existing entity? (e.g., FK to Order, Customer)"

Once answered, confirm the plan before proceeding.

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
- Always commit all three files: migration `.cs`, `.Designer.cs`, and updated `ModelSnapshot.cs`
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

## Step 9: Build + Test

Run the full build and test suite:
```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln
dotnet test XYDataLabs.OrderProcessingSystem.sln --no-build
```

ALL tests must pass before proceeding.

## Step 10: Review

Before committing, perform a self-review against this checklist:

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
| All tests pass? | `dotnet test` exits with 0 failures |

## Step 11: Commit

```powershell
git add -A
git commit -m "Add {EntityName} entity with multitenant CQRS and EF migration

- Domain: {EntityName} entity with TenantId FK
- Application: Create/Get commands+handlers, DTO
- Infrastructure: DbContext config, migration, composite index
- API: {EntityName}Controller with dispatch endpoints
- Tests: handler unit tests + architecture tenant compliance"
```

## Step 12: Update Context (optional)

If this is a significant feature, run `/XYDataLabs-context-audit` to verify instruction files still reflect the codebase.

## Step 13: Payment Verification (conditional)

**Run this step only if the feature touched any of:**
- `Application/Features/Payments/`
- `XYDataLabs.OpenPayAdapter/`
- `Domain/Entities/CardTransaction*`, `PayinLog*`, `BillingCustomer*`, `PaymentProvider*`, `TransactionStatusHistory*`
- `Infrastructure/` payment-related data access or seeding

**Action:** Run `/XYDataLabs-verify-db-logs` to verify logs and DB records and confirm no data isolation or schema regressions were introduced. Running this also serves as physical verification of the ADR-010 log filename and sink selection cells for the runtime profile used — confirming the correct log file was written with the correct naming pattern.
