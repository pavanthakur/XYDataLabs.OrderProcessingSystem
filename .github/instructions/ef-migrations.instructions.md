---
applyTo: "**/Infrastructure/**,**/Migrations/**,**/DataContext/**"
---
# EF Core Conventions — XYDataLabs.OrderProcessingSystem

## DbContext
- Business context: `OrderProcessingSystemDbContext` — tenant-owned entities with query filters and FK enforcement
- Registry context: `TenantRegistryDbContext` — lightweight, used for tenant resolution only (no query filters, no ITenantProvider)
- Migrations are managed for `OrderProcessingSystemDbContext` only
- Project: `XYDataLabs.OrderProcessingSystem.Infrastructure`
- Startup project for migrations: `XYDataLabs.OrderProcessingSystem.API`
- Design-time factory: `DesignTimeDbContextFactory` (decouples EF tooling from Program.cs)

## Connection String
- Key name in config: `OrderProcessingSystemDbConnection`
- Constant: `Constants.Configuration.OrderProcessingSystemDbConnectionString`
- Registered in: `Infrastructure/StartupHelper.cs` → `InjectInfrastructureDependencies()`
- Dev SQL logging: `LogTo(Console.WriteLine)` + `EnableSensitiveDataLogging()` guarded by `IsDevelopment()`

## Azure SQL (Dev)
- Server: `orderprocessing-sql-dev.database.windows.net`
- Database: `OrderProcessingSystem_Dev`
- Admin: `sqladmin` (passwordless via `Authentication=Active Directory Default` — see ADR-006)
- Resource Group: `rg-orderprocessing-dev`

## Migration Commands
```powershell
# Add new migration (--context required because two DbContexts exist)
dotnet ef migrations add <MigrationName> `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --context OrderProcessingSystemDbContext

# Apply to Azure SQL (with firewall rule open for current IP)
$ip = (Invoke-RestMethod https://api.ipify.org)
az sql server firewall-rule create --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --name "dev-machine" --start-ip-address $ip --end-ip-address $ip
$sqlPwd = Read-Host "Enter Azure SQL password" -MaskInput
$azureCs = "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=OrderProcessingSystem_Dev;User ID=sqladmin;Password=$sqlPwd;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
dotnet ef database update --project XYDataLabs.OrderProcessingSystem.Infrastructure --startup-project XYDataLabs.OrderProcessingSystem.API --connection $azureCs
az sql server firewall-rule delete --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --name "dev-machine"
```

## Applied Migrations (current baseline)
1. `20260324195231_InitialCreate` — full schema (MaskedCardNumber, no CVV2, BillingCustomerId FK)
2. `20260324202503_SeedBaselineTenants` — inserts TenantA and TenantB rows (IF NOT EXISTS guards — safe for Azure re-apply)
3. `20260324210853_SeedDedicatedTenantC` — inserts TenantC as Dedicated-tier tenant (IF NOT EXISTS guard, ConnectionString NULL — ops must provision per environment)

This repository was rebaselined in March 2026. Historical migrations were intentionally removed. The current migration chain starts from a single clean baseline and future migrations must build from that baseline only.

## Current Schema Notes
- `Tenants` is the tenant authority table — TenantA and TenantB are seeded by `20260324202503_SeedBaselineTenants` migration; TenantC (Dedicated tier) is seeded by `20260324210853_SeedDedicatedTenantC` migration (all with IF NOT EXISTS SQL for Azure safety)
- `Tenants` now includes `TenantTier` (nvarchar 20, NOT NULL, default 'SharedPool') and `ConnectionString` (nvarchar 500, nullable)
- TenantA and TenantB are SharedPool (ConnectionString = NULL); TenantC is Dedicated (ConnectionString = NULL in migration — ops provisions per environment)
- `TenantRegistryDbContext` owns the `Tenants` DbSet for tenant resolution (no query filters, no ITenantProvider dependency)
- `OrderProcessingSystemDbContext` still configures `Tenants` entity for FK integrity from business entities
- Tenant-owned tables use `TenantId int NOT NULL` as an FK to `Tenants.Id`
- `Tenants` is excluded from global query filters; tenant-owned entities are filtered by `ITenantProvider.TenantId`
- Required composite indexes currently include:
  - `CardTransactions (TenantId, CustomerOrderId)`
  - `CardTransactions (TenantId, AttemptOrderId)`
  - `PayinLogs (TenantId, AttemptOrderId)`
  - `TransactionStatusHistories (TenantId, AttemptOrderId)`

## Safe Migration Workflow
1. **Generate**: `dotnet ef migrations add <Name> --project Infrastructure --startup-project API`
2. **Review**: Open generated `.cs` — verify `Up()`/`Down()` are correct and reversible
3. **Drift check**: Generate a second temporary migration and confirm it is empty, then remove it
4. **Test locally**: Run API with `http` profile — migration auto-applies via `DbInitializer.Initialize()`
5. **Test Docker**: Run `start-docker.ps1 -Environment dev` — migration auto-applies via `Database.Migrate()`
6. **Commit**: Check in migration `.cs`, `.Designer.cs`, and updated `ModelSnapshot.cs`
7. **CI validates**: `EfMigrationDriftTests.Model_Should_Not_Have_Pending_Changes()` catches model/snapshot drift
8. **Deploy**: Azure environments use `run-database-migrations.ps1` or pipeline-applied `dotnet ef database update`

## Migration Safety Rules
- **Always commit all three files**: `<timestamp>_<Name>.cs`, `<timestamp>_<Name>.Designer.cs`, `OrderProcessingSystemDbContextModelSnapshot.cs`
- **Never manually edit the ModelSnapshot** — it's auto-generated by EF Core
- **Never skip the review step** — check `Up()` for data loss, verify `Down()` is reversible
- **Baseline tenant seeds** (`TenantA`, `TenantB`) live in `20260324202503_SeedBaselineTenants` migration `Up()` as raw `migrationBuilder.Sql()` with `IF NOT EXISTS` guards — never use `migrationBuilder.InsertData()` for tenant seeds (breaks Azure re-apply)
- **Data migrations** (UPDATE/INSERT SQL) for future changes go inside the migration `Up()` method, not in seed code
- **DesignTimeDbContextFactory** ensures migration generation works independently of Program.cs
- **Architecture test** `EfMigrationDriftTests` runs in CI — prevents forgetting to create a migration after model changes

## Seed data placement rule

Two categories of seed data exist in this repository. They are not interchangeable.

**Baseline reference rows — allowed and required in the baseline migration**
Rows that must exist immediately after migration for the database to be in a valid operational state. Currently: `TenantA` and `TenantB` in the `Tenants` table (SharedPool tier).
Rule: if the application cannot start or the middleware cannot function without these rows, they belong in the baseline migration `Up()` method, not in `DbInitializer`.

**Dedicated-tier baseline tenant rows — separate migration per tenant**
Rows that register a tenant for dedicated database routing but do not assign a connection string (ops provisions per environment). Currently: `TenantC` in `20260324210853_SeedDedicatedTenantC`.
Rule: each Dedicated-tier tenant gets its own migration with IF NOT EXISTS guard. ConnectionString is intentionally NULL in the migration — environment-specific provisioning sets it via Key Vault or App Settings. An unprovisioned Dedicated tenant fails loud (HTTP 400), never silently falls back to SharedPool.

**Sample and runtime bootstrap data — must live outside migrations in `DbInitializer.cs`**
Rows that populate an otherwise valid database with demo, development, or environment-specific data. Currently: customers, products, orders, OpenPay provider configuration.
Rule: if the database is structurally valid without these rows, they belong in `DbInitializer`, not in a migration.

Do not move baseline reference rows out of the migration without an explicit architecture review. Doing so weakens deterministic database bootstrapping and breaks any environment that skips `DbInitializer` (for example, CI pipeline fresh migrations).

## Multi-Tenancy Schema
- `TenantId` column: `int NOT NULL` FK to `Tenants.Id` on all tenant-owned tables
- `Tenants` carries `Id`, `ExternalId`, `Code`, `Name`, and `Status`
- Request resolution uses `X-Tenant-Code`, not `X-Tenant-Id`
- Global query filters apply to tenant-owned entities and do not apply to `Tenants`
- Both `SaveChanges()` and `SaveChangesAsync()` stamp `TenantId` only for tenant-owned base-class entities
- Non-request operations must set `TenantId` explicitly
