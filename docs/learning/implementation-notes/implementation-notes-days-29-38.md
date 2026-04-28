# Implementation Notes - Azure Curriculum Days 29-38

Purpose: Detailed execution evidence and implementation notes for completed curriculum days.
These notes supplement the checklist-level summaries in `1_MASTER_CURRICULUM.md`.

Created: 04/04/2026 | Covers: Days 29-38 (Weeks 5-8)

---

## Day 29: Bicep Modules

Bicep module pattern used:
- Extract reusable resource definitions into `.bicep` files with `param` and `output` blocks
- `infra/modules/appservice.bicep` — reusable App Service + Plan module accepting env-specific params
- Referenced from `infra/main.bicep`:
  ```bicep
  module appService './modules/appservice.bicep' = {
    name: 'appservice'
    params: { ... }
  }
  ```
- Module outputs (for example `output appServiceId string = app.id`) allow cross-module resource wiring

---

## Day 30: Parameter Files

Multi-environment pattern:
- `infra/parameters/dev.json`, `staging.json`, `prod.json` — same Bicep, different configs
- Parameterized: app name prefix, location, SQL tier, App Service SKU, Key Vault config
- Deploy command:
  ```powershell
  az deployment sub create --parameters @parameters/dev.json
  ```
- Staging Azure resource names use `stg` suffix (not `staging`) — for example `rg-orderprocessing-stg`

---

## Day 31: GitHub Actions Infra Deployment

Workflow enhancements implemented (`infra-deploy.yml`):
- Added `what-if` step so PR reviewers see planned changes before merge
- Added `workflow_dispatch` with input dropdowns for manual triggers from GitHub UI
- Added `dryRun` boolean input: when `true`, runs `--what-if` only, skips real deployment
- Tested: triggered from Actions tab -> environment=dev, dryRun=true -> what-if diff confirmed in logs
- See: `.github/workflows/README-INFRA-DEPLOY.md` for full input documentation

---

## Day 32-33: Azure SQL Provisioning + EF Migrations

Verified state as of 20/03/2026:
- Resource group: `rg-orderprocessing-dev`
- SQL Server: `orderprocessing-sql-dev.database.windows.net`
- Database: `OrderProcessingSystem_Dev`
- All 6 EF Core migrations applied: 13 tables created, 120 Customer rows seeded
- Confirmed via Azure Portal -> SQL Database -> Query editor

Key EF migration commands:
```powershell
dotnet ef migrations add InitialCreate --project XYDataLabs.OrderProcessingSystem.Infrastructure --startup-project XYDataLabs.OrderProcessingSystem.API
dotnet ef database update --connection "<azure-sql-connection-string>"
```

Firewall note: Local IP must be added to SQL firewall rule before running `dotnet ef database update` against Azure SQL.

---

## Day 34: Environment-Specific SQL Configuration

EF Core SQL logging - actual implementation (StartupHelper.cs):

EF logging is not gated by `IsDevelopment()` - it is gated by the `Observability:EnableEfSensitiveDataLogging`
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
it - you must explicitly set the flag in the shared settings file.

Local console output confirmed (Day 34 verification):
```
[03:23:48 INF] [dev] [Local] Request: GET /api/Customer/GetAllCustomersByName
info: RelationalEventId.CommandExecuted[20101]
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
[03:23:48 INF] [dev] [Local] Response: 200 in 587.2204 ms
```

Azure verification: `pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger` ->
`GET /api/Customer/GetAllCustomersByName?name=at&pageNumber=1&pageSize=10` -> 120 customers returned.

---

## Day 35: SQL Managed Identity

Actual roles granted (see `Resources/Azure-Deployment/setup-sql-managed-identity.ps1`):

```sql
CREATE USER [pavanthakur-orderprocessing-api-xyapp-dev] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];
ALTER ROLE db_datawriter ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];
ALTER ROLE db_ddladmin   ADD MEMBER [pavanthakur-orderprocessing-api-xyapp-dev];
```

All three roles are required: `db_datareader` + `db_datawriter` for normal app operation, `db_ddladmin`
so EF Core migrations can run without a separate SQL admin connection.

MI principal name: Must match the App Service name exactly in `CREATE USER`.

---

## Day 36-37: DefaultAzureCredential + Passwordless SQL

Implementation approach - `Authentication=Active Directory Default`:
- Connection strings for Azure SQL use `Authentication=Active Directory Default` in the connection string value
- `DedicatedTenantConnectionStrings` in all three environments (dev/stg/prod) use this pattern
- `DefaultAzureCredential` is resolved by the Azure.Identity library automatically:
  - Locally: `AzureCliCredential` (after `az login`)
  - On Azure App Service: `ManagedIdentityCredential`
- No `SqlConnection.AccessToken` manual wiring needed - the connection string keyword handles it

Scope of passwordless coverage:
- Azure SQL in all environments: passwordless via `Authentication=Active Directory Default`
- Key Vault in all environments: `DefaultAzureCredential` via `SharedSettingsLoader.cs`
- Default connection string in `sharedsettings.stg.json` and `sharedsettings.prod.json` still
  carries placeholder SQL admin credentials - used only for break-glass access and local tooling.
  App traffic uses `DedicatedTenantConnectionStrings` which are passwordless.

Verified: App Insights traces and SQL audit logs show token-based auth for all deployed app queries.

---

## Day 38: Azure SQL Resilience Baseline

Test methodology:
1. Stopped SQL server briefly from Azure Portal -> observed API behaviour
2. EF Core `EnableRetryOnFailure()` in `StartupHelper.cs` provided baseline retry
3. Logs showed transient failures retried with eventual success
4. Timed the retry intervals to inform Polly policy tuning (Day 39)

Next step (Day 39): Add Polly policies - retry with exponential backoff + jitter, circuit breaker
(5 failures -> 30s open), timeout (10s) - and wire retry telemetry to Application Insights.

Transition note:

- This file is the active canonical implementation-evidence document for curriculum days 29-38.
- It also carries detailed evidence for later day closures when the work is tightly coupled to the same Azure SQL / health-check / CI-CD foundation and does not justify a second partial notes file.

---

## Day 42-43: Phase 7 Closure - Typed Boundaries + Deployment Readiness

Phase 7 reached a verification freeze with two final slices that were easy to get wrong if treated as cosmetic refactors. The later strict-closeout backlog is intentionally narrow: custom OTel metrics are now implemented in code and need cross-runtime verification, `Address` remains deferred by design, and broader optimistic concurrency remains deferred until another aggregate shows real competing-writer risk.

**1. Strongly typed IDs were pushed to the caller-facing boundary**

- `CustomerId`, `OrderId`, and `ProductId` were already in the Domain and EF Core mapping layer.
- The remaining leak was at the application contract boundary (`CreateOrderCommand`, `GetOrderDetailsQuery`, customer commands/queries) and API controller construction layer.
- The final slice changed command/query records to accept typed IDs directly, updated controllers to construct typed IDs at the boundary, and added `IParsable<T>` on the typed ID wrappers so ASP.NET route binding could parse `CustomerId` and `OrderId` directly from route segments.
- Verification was deliberately not limited to compile-time success; the suite already proved SQL translation for typed IDs and was extended earlier in the session to prove route binding through HTTP for `GET /api/v1/Order/{id}`.

Representative code added during the boundary slice:

```csharp
public readonly record struct OrderId(int Value) : IComparable<OrderId>, IParsable<OrderId>

public sealed record GetOrderDetailsQuery(OrderId OrderId) : IQuery<Result<OrderDto>>;

[HttpGet("{id}", Name = nameof(GetOrderDetailsById))]
public async Task<ActionResult> GetOrderDetailsById(OrderId id, CancellationToken cancellationToken)
```

**2. Deployment readiness semantics were corrected at the HTTP contract, not just in the workflow URL**

- The deployment workflow originally probed Swagger with a retry loop and treated any HTTP 200 as success.
- Before switching the workflow URL, the health-check mapping in `Program.cs` was inspected. The trap was real: default `MapHealthChecks()` semantics return HTTP 200 for `HealthStatus.Degraded` unless `ResultStatusCodes` is overridden.
- That meant swapping the workflow URL from Swagger to `/health/ready` without changing the endpoint mapping could have created false confidence: the workflow would report success even when dependencies were degraded.
- The fix was applied at both layers:
  - `Program.cs` now maps both degraded and unhealthy readiness results to HTTP 503.
  - `deploy-api-to-azure.yml` now probes `/health/ready` instead of `/swagger`, preserving the existing cold-start wait, retry count, retry delay, and timeout behavior.

Representative readiness mapping:

```csharp
var readinessHealthCheckOptions = new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready"),
    ResultStatusCodes =
    {
        [HealthStatus.Healthy] = StatusCodes.Status200OK,
        [HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
        [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
    }
};

app.MapHealthChecks("/health/ready", readinessHealthCheckOptions);
app.MapHealthChecks("/health", readinessHealthCheckOptions);
```

Representative workflow probe:

```powershell
$readinessUrl = "$apiUrl/health/ready"
$readinessResponse = Invoke-WebRequest -Uri $readinessUrl -Method Get -TimeoutSec 60 -ErrorAction Stop
```

**3. Commands run and observed outputs**

Build and regression commands run during the close-out:

```powershell
dotnet build .\XYDataLabs.OrderProcessingSystem.sln /property:GenerateFullPaths=true "/consoleloggerparameters:NoSummary;ForceNoAlign"
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Application.Tests\XYDataLabs.OrderProcessingSystem.Application.Tests.csproj --no-build --logger "console;verbosity=minimal"
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --logger "console;verbosity=minimal"
```

Verified outcomes:

```text
Build succeeded
Passed!  - Failed: 0, Passed: 37, Skipped: 0, Total: 37
Passed!  - Failed: 0, Passed: 29, Skipped: 0, Total: 29
```

**4. Key gotchas discovered**

- `IParsable<T>` was required for controller route binding once typed IDs were pushed to action parameters; otherwise the change would compile but route binding would remain primitive-only.
- The first integration rerun after adding a new test used `--no-build`; that was corrected before closing so the new test was actually compiled and executed.
- Readiness probes must fail closed. `/health/ready` with default ASP.NET Core status-code mapping is not a safe deployment gate if degraded dependencies should block traffic.

**5. What this enables next**

- Phase 7 reached a stable verification freeze with tenant enforcement, audit trail, aggregate hardening, value object adoption (`Money`), strongly typed IDs, typed contract boundaries, and correct deployment readiness semantics all verified.
- `Address` remains intentionally deferred until a concrete customer, billing, or shipping boundary exists.
- Broader optimistic concurrency remains intentionally deferred until another aggregate shows real competing-writer risk.
- The custom OTel metrics slice is now implemented in the shared meter and emitted from tenant enforcement, API ProblemDetails handling, and payment execution.
- Order-level concurrency surfacing is also intentionally deferred for now: the `RowVersion` guard stays in place, but explicit `DbUpdateConcurrencyException` -> stable API conflict mapping waits until the order write surface has a real multi-writer path that justifies freezing a public contract.
- The next safe architecture slice is Phase 8a: define domain/integration event primitives and the transactional seam that writes aggregate changes and outbox rows in the same database transaction.

---

## Day 43 Freeze Validation: Cross-Runtime Payment Proof + Azure Bootstrap (April 10, 2026)

Phase 7 was not treated as closed solely because unit and integration tests passed. The final freeze validation proved the current baseline on all three runtime paths plus the Azure control-plane setup that the next phase depends on.

**1. Azure Initial Setup and bootstrap were proven end-to-end**

- `Azure Initial Setup` succeeded with Phase 1a + 1b on the latest workflow code.
- The run confirmed all six federated credentials (branch + environment subjects), wrote environment-scoped `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, and `AZUREAPPSERVICE_SUBSCRIPTIONID` to `dev`, `staging`, and `prod`, and stored `OIDC_SP_OBJECT_ID` as a repo secret.
- `Azure Bootstrap & Deploy` then succeeded for `dev`, proving the full control-plane path from initial setup → infra bootstrap → API deploy → UI deploy.

Observed deployed endpoints:

```text
API: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
UI:  https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net
```

**2. Payment verification was re-run against all supported runtime paths**

Commands executed:

```powershell
.\scripts\verify-payment-run-physical.ps1 -Runtime local -Environment dev -Profile http
.\scripts\verify-payment-run-physical.ps1 -Runtime docker -Environment dev -Profile http
.\scripts\verify-payment-run-azure.ps1 -Environment dev
```

All three executions converged on the same logical payment run prefix:

```text
RunPrefix: OR-3-9thApr
```

All three executions finished with the same verifier contract result:

```text
Pass/fail summary: 13/13 PASS
```

**3. Important runtime-specific finding**

- The verifier did not assume the same tenant has 3DS enabled on every runtime.
- `local` dev showed TenantA as the 3DS tenant.
- `docker` dev and `azure` dev showed TenantB as the 3DS tenant.
- This difference is acceptable because the verifier reads `PaymentProviders.Use3DSecure` from the actual target database before asserting expected callback/history counts.
- The important invariant is that each runtime remained internally consistent: API evidence, UI callback evidence, and DB rows all matched for the same charge IDs.

**4. SQL access verification for Azure dev**

Temporary local firewall access to Azure SQL was opened using the repo-owned script:

```powershell
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment dev
```

This confirmed the dev SQL server/FQDN and supported direct SSMS or `sqlcmd` validation against:

```text
orderprocessing-sql-dev.database.windows.net
OrderProcessingSystem_Dev
OrderProcessingSystem_TenantC_Dev
```

**5. What this freeze enables next**

- Phase 7 now has current runtime proof on local, Docker, and Azure, not just code-level tests.
- Azure OIDC setup, GitHub environment secret automation, and bootstrap deployment are proven on the latest workflow design.
- The next engineering slice can move to Phase 8 (event-driven foundation) without carrying uncertainty about the frozen Phase 7 baseline, but the newly added custom OTel metrics slice should still be revalidated across local, Docker, and Azure before the Phase 8 runtime surface grows materially.

### Phase 7 Final Operational Closeout Gate

The next strict target is not another feature. It is a pass/fail operational proof gate for the already-implemented Phase 7 surface.

Phase 7 is finally closed only when all of the following are true:

- Local dev: `orderprocessing.payments.completed` and `orderprocessing.payments.duration` can be observed after a representative payment run.
- Docker dev: the same payment metric families can be observed without changing emitted dimensions or cardinality.
- Azure dev: the same payment metric families arrive in the production-like telemetry path and remain operationally useful.
- Health contract: `/health/live` and `/health/ready` remain healthy under the expected baseline and readiness continues to fail closed when dependencies degrade.
- Payment verification: `verify-payment-run-physical.ps1` passes for local and Docker, and `verify-payment-run-azure.ps1` passes for Azure after the metrics slice.
- CI/CD: `ci.yml` remains green for frontend validation, solution build, Domain/Application/API/Architecture tests, and tracked-artifact validation.
- Focused regression coverage exists for the tenant-validation and ProblemDetails metric emission points added in Phase 7 closeout.
- Documentation can be moved from "implemented, pending runtime revalidation" to "verified and closed" without caveat.

Important proof split:

- `orderprocessing.tenant_context.failures` is primarily regression-proved through `TenantValidationBehaviorTests`, not standard HTTP runtime probing, because public requests with missing, unknown, or blocked tenant context are intentionally rejected earlier by `TenantMiddleware`.
- `orderprocessing.api.problem_responses` is primarily regression-proved through `ErrorHandlingMiddlewareTests`, because the closeout gate should not depend on synthetic unhandled-exception traffic against Azure dev.
- The exact command sequence for the Phase 7 closeout proof lives in `docs/reference/quick-command-reference.md` under **Phase 7 Operational Proof Commands**.

### April 28, 2026 Revalidation Snapshot

- Focused regression coverage passed for the two non-runtime metric paths: `TenantValidationBehaviorTests` and `ErrorHandlingMiddlewareTests` both passed after a shared test-helper constructor mismatch was corrected in the Application test base.
- Focused `MeterListener` coverage now also proves that `BusinessMetrics` emits the expected in-process measurements for tenant-validation failure, ProblemDetails responses, and payment outcome plus duration.
- Local proof passed at the payment-verification layer after running the repo-owned browser automation target `local-http` for `TenantA`; `verify-payment-run-physical.ps1` passed for run prefix `OR-1777318139-28Apr`.
- Docker dev proof passed at the payment-verification layer after running the repo-owned browser automation target `docker-dev-http` for `TenantA`; `verify-payment-run-physical.ps1` passed for run prefix `OR-1777318429-28Apr`.
- Azure dev proof passed at the payment-verification layer for `TenantA`; the repo-owned automation wrapper reached a transient Azure SQL firewall timing failure during its embedded verification step, but the direct rerun of `verify-payment-run-azure.ps1` passed for run prefix `OR-1777318480-28Apr` once firewall access had taken effect.
- Azure trace evidence is present in Application Insights for the April 28 Azure proof run, so the deployed runtime is emitting telemetry to the dev App Insights resource.
- After the latest Azure dev deployment, a fresh automation run for `OR-1777369555-28Apr` also passed the direct Azure verifier and the deployed runtime exposed `orderprocessing.payments.completed` plus `orderprocessing.payments.duration` in the dev App Insights `customMetrics` table.
- Local and Docker absence from App Insights is expected unless `APPLICATIONINSIGHTS_CONNECTION_STRING` is present, because the shared Application Insights options bind only from that environment key.
- Under the agreed proof model, the remaining blocker is cleared: payment metrics are now operationally visible on the deployed Azure runtime, while tenant-validation and ProblemDetails metrics remain regression-proved through focused tests.
- Phase 7 strict closeout is therefore verified and can be treated as closed before Phase 8 broadens the runtime surface.
