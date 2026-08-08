# Infrastructure

EF Core, SQL Server, multi-tenancy, seed data, and payment provider resolution. The only layer that touches the database and Azure SDKs.

## Key components

| Folder / File | Purpose |
|---------------|---------|
| `DataContext/OrderProcessingSystemDbContext` | Main EF Core context — all domain entities |
| `DataContext/TenantRegistryDbContext` | Tenant registry — `Tenant` and `PaymentProvider` tables |
| `Migrations/` | EF Core migrations — run via `dotnet ef`, the Azure migration wrapper, or the explicit local/bootstrap tooling |
| `SeedData/DbInitializer` | Applies idempotent shared and dedicated tenant seed data during explicit bootstrap or migration flows |
| `Multitenancy/TenantRegistryService` | Implements `ITenantRegistry` — `FindByCode(string)` is the sync resolver at payment dispatch |
| `Multitenancy/EntityFrameworkTenantResolver` | Resolves tenant context for EF query filtering |
| `Payments/TenantPaymentProviderConfigurationResolver` | Reads `PaymentProvider` rows from DB; resolves per-tenant provider config at runtime |
| `Validator/` | Startup validators (e.g. `RazorpayConfigValidator` — enforces key prefix vs `IsProduction` flag) |

## Database

- Connection string key: `OrderProcessingSystemDbConnection`
- Azure: `Authentication=Active Directory Default` (Managed Identity — no passwords)
- Local: `Server=localhost; Database=OrderProcessingSystem_Local`
- Retry: `EnableRetryOnFailure()` is required on all contexts

## Seed data rules (DbInitializer)

`DbInitializer` is part of the explicit bootstrap path. Phase 10 local and Docker bootstrap flows are moving migration/seed ownership out of API runtime startup and into dedicated operational steps.

- `StartupSeedTenantCodes = { "TenantA", "TenantB" }` — shared pool
- TenantC only seeds when `DedicatedTenantConnectionStrings:TenantC` is configured
- **Re-seed does NOT overwrite runtime fields** (`Use3DSecure`, `IsActive`) — DB value is authoritative
- Seed-time defaults for `Use3DSecure` come from the `Use3DSecureSeedDefaults` dictionary in `DbInitializer` — never from `IConfiguration`

## Rules

- Never read per-tenant config from `IConfiguration` or sharedsettings JSON — DB only.
- All EF contexts must use `Authentication=Active Directory Default` in Azure environments.
