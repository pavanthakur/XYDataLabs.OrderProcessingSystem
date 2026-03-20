# ADR-004: EF Core 8 with Azure SQL for Relational Data

**Date:** 2024-12-28  
**Status:** Accepted — passwordless auth implemented (see ADR-006)  
**Deciders:** Project architect

---

## Context

The application requires relational data storage with:
- Complex relationships: Customers → Orders → OrderProducts → Payments
- Schema migrations as the domain model evolves
- Azure-hosted database for dev/staging/prod environments
- Future path to passwordless authentication (no connection string passwords)

## Decision

Use **EF Core 8** with **SQL Server provider** against **Azure SQL** (Basic tier for dev).

- `OrderProcessingSystemDbContext` handles all tables
- Code-first migrations via `dotnet ef migrations add`
- Connection string key: `OrderProcessingSystemDbConnection`
- Dev SQL logging: `LogTo(Console.WriteLine)` + `EnableSensitiveDataLogging()` guarded by `IsDevelopment()`
- Azure SQL dev server: `orderprocessing-sql-dev.database.windows.net`

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| EF Core 8 | Code-first migrations, LINQ queries, change tracking, strong .NET ecosystem integration | Performance overhead vs raw SQL for high-throughput | ✅ Selected |
| Dapper | Lightweight, full SQL control, fast | No migrations, no change tracking, more boilerplate | ❌ Rejected for primary store |
| Cosmos DB (NoSQL) | Globally distributed, flexible schema | Not suitable for relational order/customer model | ❌ Rejected for primary store (Cosmos added Day 66 for product catalog) |

## Consequences

**Positive:**
- Schema migrations are version-controlled and reproducible
- Strongly-typed LINQ queries reduce SQL injection risk
- `EnableRetryOnFailure()` provides built-in transient fault handling (5 retries, 30s max delay)

**Negative / Trade-offs:**
- EF Core change tracking adds memory overhead — use `AsNoTracking()` for read-only queries
- Complex reporting queries should bypass EF Core and use raw SQL or Views

**Current state (as of March 2026):**
- Passwordless auth active: `Authentication=Active Directory Default` (see ADR-006)
- No SQL password exists in source control, config files, or GitHub secrets
- SQL admin password stored exclusively in Azure Key Vault (`sql-admin-password` secret)

**Migration commands:**
```powershell
dotnet ef migrations add <Name> \
  --project XYDataLabs.OrderProcessingSystem.Infrastructure \
  --startup-project XYDataLabs.OrderProcessingSystem.API

dotnet ef database update \
  --project XYDataLabs.OrderProcessingSystem.Infrastructure \
  --startup-project XYDataLabs.OrderProcessingSystem.API \
  --connection "<Azure SQL connection string>"
```

## Related
- ADR-001: Clean Architecture — EF Core lives exclusively in Infrastructure layer
- ADR-006: Passwordless SQL with DefaultAzureCredential + Managed Identity (implemented 2026-03-20)
