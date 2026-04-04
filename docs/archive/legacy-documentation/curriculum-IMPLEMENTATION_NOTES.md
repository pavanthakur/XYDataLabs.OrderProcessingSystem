# Implementation Notes — Azure Curriculum Days 29-38

**Purpose:** Detailed execution evidence and implementation notes for completed curriculum days.
These notes supplement the checklist-level summaries in `1_MASTER_CURRICULUM.md`.

**Created:** 04/04/2026 | **Covers:** Days 29-38 (Weeks 5-8)

---

## Day 29: Bicep Modules ✅

**Bicep module pattern used:**
- Extract reusable resource definitions into `.bicep` files with `param` and `output` blocks
- `infra/modules/appservice.bicep` — reusable App Service + Plan module accepting env-specific params
- Referenced from `infra/main.bicep`:
  ```bicep
  module appService './modules/appservice.bicep' = {
    name: 'appservice'
    params: { ... }
  }
  ```
- Module outputs (e.g. `output appServiceId string = app.id`) allow cross-module resource wiring

---

## Day 30: Parameter Files ✅

**Multi-environment pattern:**
- `infra/parameters/dev.json`, `staging.json`, `prod.json` — same Bicep, different configs
- Parameterized: app name prefix, location, SQL tier, App Service SKU, Key Vault config
- Deploy command:
  ```powershell
  az deployment sub create --parameters @parameters/dev.json
  ```
- Staging Azure resource names use `stg` suffix (not `staging`) — e.g. `rg-orderprocessing-stg`

---

## Day 31: GitHub Actions Infra Deployment ✅

**Workflow enhancements implemented (`infra-deploy.yml`):**
- Added `what-if` step so PR reviewers see planned changes before merge
- Added `workflow_dispatch` with input dropdowns for manual triggers from GitHub UI
- Added `dryRun` boolean input: when `true`, runs `--what-if` only, skips real deployment
- Tested: triggered from Actions tab → environment=dev, dryRun=true → what-if diff confirmed in logs ✅
- See: `.github/workflows/README-INFRA-DEPLOY.md` for full input documentation

---

## Day 32-33: Azure SQL Provisioning + EF Migrations ✅

**Verified state as of 20/03/2026:**
- Resource group: `rg-orderprocessing-dev`
- SQL Server: `orderprocessing-sql-dev.database.windows.net`
- Database: `OrderProcessingSystem_Dev`
- All 6 EF Core migrations applied: 13 tables created, 120 Customer rows seeded ✅
- Confirmed via Azure Portal → SQL Database → Query editor

**Key EF migration commands:**
```powershell
dotnet ef migrations add InitialCreate --project XYDataLabs.OrderProcessingSystem.Infrastructure --startup-project XYDataLabs.OrderProcessingSystem.API
dotnet ef database update --connection "<azure-sql-connection-string>"
```

**Firewall note:** Local IP must be added to SQL firewall rule before running `dotnet ef database update` against Azure SQL.

---

## Day 34: Environment-Specific SQL Configuration ✅

**EF Core SQL logging — actual implementation (StartupHelper.cs):**

EF logging is **not** gated by `IsDevelopment()` — it is gated by the `Observability:EnableEfSensitiveDataLogging`
config flag in `sharedsettings.*.json`, controlled via `ObservabilityOptions`:

```csharp
if (observabilityOptions.EnableEfSensitiveDataLogging)
{
    options.LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()
           .EnableDetailedErrors();
}
```

The flag is `true` for `dev`, `false` for `stg` and `prod`. This means SQL query logging is config-driven,
not environment-name-driven. Setting `ASPNETCORE_ENVIRONMENT=dev` on Azure App Service does not trigger
it — you must explicitly set the flag in the shared settings file.

**Local console output confirmed (Day 34 verification):**
```
[03:23:48 INF] [dev] [Local] Request: GET /api/Customer/GetAllCustomersByName
info: RelationalEventId.CommandExecuted[20101]
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
[03:23:48 INF] [dev] [Local] Response: 200 in 587.2204 ms
```

**Azure verification:** `pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger` →
`GET /api/Customer/GetAllCustomersByName?name=at&pageNumber=1&pageSize=10` → 120 customers returned ✅

---

## Day 35: SQL Managed Identity ✅

**Actual roles granted** (see `Resources/Azure-Deployment/setup-sql-managed-identity.ps1`):

```sql
CREATE USER [pavanthakur-orderprocessing-api-xyapp-dev] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];  -- SELECT
ALTER ROLE db_datawriter ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];  -- INSERT/UPDATE/DELETE
ALTER ROLE db_ddladmin   ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];  -- CREATE/ALTER/DROP (EF migrations)
```

All three roles are required: `db_datareader` + `db_datawriter` for normal app operation, `db_ddladmin`
so EF Core migrations can run without a separate SQL admin connection.

**MI principal name:** Must match the App Service name exactly in `CREATE USER`.

---

## Day 36-37: DefaultAzureCredential + Passwordless SQL ✅

**Implementation approach — `Authentication=Active Directory Default`:**
- Connection strings for Azure SQL use `Authentication=Active Directory Default` in the connection string value
- `DedicatedTenantConnectionStrings` in all three environments (dev/stg/prod) use this pattern
- `DefaultAzureCredential` is resolved by the Azure.Identity library automatically:
  - Locally: `AzureCliCredential` (after `az login`)
  - On Azure App Service: `ManagedIdentityCredential`
- No `SqlConnection.AccessToken` manual wiring needed — the connection string keyword handles it

**Scope of passwordless coverage:**
- ✅ Azure SQL in all environments: passwordless via `Authentication=Active Directory Default`
- ✅ Key Vault in all environments: `DefaultAzureCredential` via `SharedSettingsLoader.cs`
- ⚠️ Default connection string in `sharedsettings.stg.json` and `sharedsettings.prod.json` still
  carries placeholder SQL admin credentials — used only for break-glass access and local tooling (e.g. SSMS).
  App traffic uses `DedicatedTenantConnectionStrings` which are passwordless.

**Verified:** App Insights traces and SQL audit logs show token-based auth for all deployed app queries.

---

## Day 38: Azure SQL Resilience Baseline ✅

**Test methodology:**
1. Stopped SQL server briefly from Azure Portal → observed API behaviour
2. EF Core `EnableRetryOnFailure()` in `StartupHelper.cs` provided baseline retry
3. Logs showed transient failures retried with eventual success
4. Timed the retry intervals to inform Polly policy tuning (Day 39)

**Next step (Day 39):** Add Polly policies — retry with exponential backoff + jitter, circuit breaker
(5 failures → 30s open), timeout (10s) — and wire retry telemetry to Application Insights.
