---
agent: agent
description: "Run when starting a new feature that needs end-to-end implementation: entity, CQRS handlers, controller, EF migration, tests — all with multitenant support. Orchestrates the full development workflow."
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

Rules (from `ef-migrations.instructions.md`):
- Add `public DbSet<EntityName> EntityNames { get; set; }` property
- Add fluent configuration in `OnModelCreating()`:
  - `HasMaxLength()` for string properties
  - Composite index on `(TenantId, <primary lookup field>)` — follow existing pattern
  - FK relationship to `Tenants` table
- Add global query filter: `.HasQueryFilter(e => e.TenantId == _tenantProvider.TenantId)`
- Follow the same configuration pattern as existing entities (e.g., `CardTransaction`, `CustomerOrder`)

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

If this is a significant feature, run `/context-audit` to verify instruction files still reflect the codebase.
