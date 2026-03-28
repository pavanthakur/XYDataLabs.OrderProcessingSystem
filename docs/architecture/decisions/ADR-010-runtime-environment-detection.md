# ADR-010: Runtime Environment Detection and Feature Gating

**Status:** Accepted

**Date:** 2026-03-27

---

## Context

The application runs in five distinct runtime contexts: local VS, local Docker dev, local Docker
staging, local Docker prod, and Azure App Service (dev / stg / prod). Several features must behave
differently depending on the runtime context — for example, the tenant dropdown must always be
visible in any local Docker run regardless of the `ASPNETCORE_ENVIRONMENT` value, and is also
shown on Azure (the DB contains multiple tenants that are switchable via X-Tenant-Code).

Three environment variables drive all runtime detection:

| Variable | Set by | Value |
|----------|--------|-------|
| `ASPNETCORE_ENVIRONMENT` | Docker Compose, Azure App Service config | `Development` / `Staging` / `Production` |
| `DOTNET_RUNNING_IN_CONTAINER` | Dockerfile `ENV` (line 52 / 70) **and** Azure App Service (natively) | `true` |
| `WEBSITE_SITE_NAME` | Azure App Service only | App Service name (e.g. `pavanthakur-orderprocessing-api-xyapp-dev`) |

**Critical constraint:** `DOTNET_RUNNING_IN_CONTAINER=true` is baked into the Dockerfile, so it is
`true` in both local Docker and Azure App Service containers. It **cannot** be used alone to
distinguish local from Azure.

**Reliable local-vs-Azure discriminator:** `WEBSITE_SITE_NAME` — only injected by Azure App
Service; never present in a local Docker or VS run.

---

## Decision

All environment-conditional feature gates use exactly three derived booleans, resolved at startup:

```csharp
// Both API/Program.cs and UI/Program.cs
var isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";
var azureSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
var isAzure = !string.IsNullOrWhiteSpace(azureSiteName);
// IsDevelopment = ASPNETCORE_ENVIRONMENT == "Development"
```

In the UI, these are also exposed as `ViewData` keys (`IsDocker`, `IsAzure`, `IsDevelopment`) by
`HomeController.PopulateCommonViewData()` for use in Razor views.

---

## Runtime Context Matrix

| Context | `IsDevelopment` | `IsDocker` | `IsAzure` | Notes |
|---------|:---:|:---:|:---:|-------|
| VS F5 local | ✓ | ✗ | ✗ | ASPNETCORE_ENVIRONMENT=Development, no Docker |
| Dev Docker (local) | ✓ | ✓ | ✗ | docker-compose.dev.yml |
| Stg Docker (local) | ✗ | ✓ | ✗ | docker-compose.stg.yml, ASPNETCORE_ENVIRONMENT=Staging |
| Prod Docker (local) | ✗ | ✓ | ✗ | docker-compose.prod.yml, ASPNETCORE_ENVIRONMENT=Production |
| Azure dev App Service | ✓ | ✓ | ✓ | WEBSITE_SITE_NAME set by Azure |
| Azure stg App Service | ✗ | ✓ | ✓ | WEBSITE_SITE_NAME set by Azure |
| Azure prod App Service | ✗ | ✓ | ✓ | WEBSITE_SITE_NAME set by Azure |

---

## Feature Gate Inventory

Every feature that behaves differently per runtime context is listed here. **Update this table
when adding any new environment-conditional logic.**

### UI Features (`_Layout.cshtml` / controllers)

| Feature | Gate condition | VS local | Dev Docker | Stg Docker | Prod Docker | Azure (any) |
|---------|---------------|:---:|:---:|:---:|:---:|:---:|
| Tenant selector dropdown | `IsDevelopment \|\| IsDocker` | ✅ | ✅ | ✅ | ✅ | ✅ |
| "🐳 Docker" badge in banner | `IsDocker` | ❌ | ✅ | ✅ | ✅ | ✅* |
| Developer exception page (UI) | `!IsDevelopment \|\| IsAzure` | ✅ | ✅ | ❌ | ❌ | ❌ |

> *Docker badge shows on Azure too (IsDocker=true). Acceptable — it is informational only.
> If it must be hidden on Azure, apply the same `!IsAzure` gate.

### API Features (`API/Program.cs`)

| Feature | Gate condition | VS local | Dev Docker | Stg Docker | Prod Docker | Azure dev | Azure stg | Azure prod |
|---------|---------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Swagger UI | `environmentName == "dev" \|\| "stg"` | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| Developer exception page (API) | `IsDevelopment && !isAzure` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EF Core auto-migrations | `!isAzureRuntime` (i.e. `!isAzure`) | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| CORS policy | `AllowAll` unless `isAzure && prod` → `AllowProductionUI` | AllowAll | AllowAll | AllowAll | AllowAll | AllowAll | AllowAll | AllowProductionUI |
| Log sink: file `/logs/webapi-{env}-dock-{profile}-.log` | `isDocker` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Log sink: local file `../logs/webapi-{env}-local-{profile}-.log` | `!isDocker` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Swagger server URL | `isAzure` → Azure domain, else sharedsettings | auto | auto | auto | auto | ✅ | ✅ | ✅ |

### Payment / OpenPay

| Feature | Gate condition | VS local | Dev Docker | Stg Docker | Azure (any) |
|---------|---------------|:---:|:---:|:---:|:---:|
| OpenPay sandbox endpoint | Configured via `OpenPayConfig:BaseUrl` (not env-gated in code) | manual | `.env.local` | `.env.local` | Key Vault |
| RedirectUrl | `PostConfigure<OpenPayConfig>` — built from `ApiSettings:UI:{http\|https}:Host/Port` when not set | auto | auto | auto | auto |
| Payment flow (X-Tenant-Code header) | Always sent regardless of environment | ✅ | ✅ | ✅ | ✅ |

---

## Checklist for New Environment-Conditional Features

When writing any code that behaves differently based on runtime context, validate every cell in
the matrix before merging:

```text
[ ] VS F5 local (IsDevelopment=true, IsDocker=false, IsAzure=false)
[ ] Dev Docker  (IsDevelopment=true, IsDocker=true,  IsAzure=false) — docker-compose.dev.yml
[ ] Stg Docker  (IsDevelopment=false, IsDocker=true, IsAzure=false) — docker-compose.stg.yml
[ ] Prod Docker (IsDevelopment=false, IsDocker=true, IsAzure=false) — docker-compose.prod.yml  (rare but possible)
[ ] Azure dev   (IsDevelopment=true,  IsDocker=true, IsAzure=true)
[ ] Azure stg   (IsDevelopment=false, IsDocker=true, IsAzure=true)
[ ] Azure prod  (IsDevelopment=false, IsDocker=true, IsAzure=true)
```

**Common traps:**

| Trap | Wrong gate | Correct gate |
|------|-----------|-------------|
| "Only show in dev" but need stg Docker too | `IsDevelopment` | `!IsAzure && (IsDevelopment \|\| IsDocker)` |
| "Hide on Azure" but also hide on local prod Docker | `!IsDevelopment` | `IsAzure` |
| "Only in Docker" thinking it excludes Azure | `IsDocker` | `IsDocker && !IsAzure` |
| "Detect Azure" | `IsDocker` ← WRONG, it's true locally too | `IsAzure` (WEBSITE_SITE_NAME) |

---

## Adding ViewData Flags to New Controllers

If a new Razor controller needs environment-conditional rendering, add the flags via
`PopulateCommonViewData()` in `HomeController` or reuse the same detection pattern:

```csharp
var isDocker = string.Equals(Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"), "true", StringComparison.Ordinal);
var isAzure = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME"));
ViewData["IsDocker"] = isDocker;
ViewData["IsAzure"] = isAzure;
ViewData["IsDevelopment"] = string.Equals(environmentName, Constants.Environments.Dev, StringComparison.Ordinal);
```

Do NOT re-read `ASPNETCORE_ENVIRONMENT` directly in controllers — go through `ResolveExecutionContext()`.

---

## Consequences

**Positive:**
- Single source of truth for all runtime detection logic.
- Checklist prevents the stg Docker blind spot (the bug that triggered this ADR).
- Feature gate inventory makes auditing straightforward.

**Negative / Trade-offs:**
- `WEBSITE_SITE_NAME` is Azure App Service-specific. If the app is ever deployed to AKS or
  Azure Container Apps, this variable is not set automatically — `isAzure` would be `false` and
  local-only features (e.g. tenant dropdown) would become visible. Must set `WEBSITE_SITE_NAME`
  explicitly in AKS/ACA pod environment, or introduce a new `DEPLOYMENT_TARGET` variable.

**Future obligations:**
- When deploying to AKS/ACA, re-evaluate the `isAzure` detection strategy and update this ADR.
- When adding any new environment-conditional feature, add a row to the Feature Gate Inventory.
- `AllowProductionUI` CORS origin is currently derived from the API site name by replacing `-api-xyapp-` with `-ui-xyapp-`. If that naming convention changes, update `AddCors` in `API/Program.cs` and this ADR.

---

## Audit Log

| Date | Auditor | Finding | Action |
|------|---------|---------|--------|
| 2026-03-27 | Checklist audit | UI developer exception page used `!IsDevelopment` without `!isAzure` — Azure dev would serve raw stack traces | Fixed in `UI/Program.cs` (commit cd02192) |
| 2026-03-27 | Checklist audit | API migrations block re-read `WEBSITE_SITE_NAME` into `isAzureRuntime` instead of reusing top-level `isAzure` | Fixed in `API/Program.cs` (commit cd02192) |
| 2026-03-27 | Checklist audit | CORS `AllowAll` policy active in all environments including Azure prod — `AllowPaymentUI` policy commented out | Known tech debt, pre-existing. Needs origin whitelist before Azure prod hardening |
| 2026-03-27 | Checklist audit | Swagger exposed in Azure prod — `TODO: DISABLE SWAGGER IN PRODUCTION` comment in code | Known tech debt, pre-existing |
| 2026-03-27 | Code review | CORS `AllowAll` applied to Azure prod — `SetIsOriginAllowed(_ => true)` with `AllowCredentials()` is dangerous in prod (OWASP A05) | Fixed: added `AllowProductionUI` policy restricting origin to UI App Service domain; applied via `corsPolicy` variable at runtime |
| 2026-03-27 | Code review | Swagger still enabled in Azure prod despite `TODO` comment; `environment == "prod"` block unconditionally called `app.UseSwagger()` | Fixed: prod branch now uses exception handler + HSTS only; `TODO` comment removed |
| 2026-03-27 | Code review | `#if RELEASE` block appended after `public partial class Program { }` — top-level statements illegal after type declarations (`CS8803`); throw would crash every prod startup | Fixed: block removed entirely |
| 2026-03-27 | Checklist audit | `MyApiClient` registered with `http://api:{port}` (Docker hostname) — wrong in Azure since `isDocker=true` there. Never consumed by any controller — dead registration | Low risk (unused). Remove when doing HttpClient cleanup |
| 2026-03-27 | Checklist audit | Log file sink `/logs/webapi-.log` and `/logs/ui-.log` write to ephemeral Azure App Service filesystem | Low risk — App Insights covers Azure logs when connection string present |
| 2026-03-28 | Code review | `local dotnet run` and `docker dev http` both wrote `webapi-dev-http-{date}.log` — file lock conflict when running both simultaneously | Fixed: added `runtimeSuffix` (`dock`/`local`) as third segment. New pattern: `{app}-{env}-{runtime}-{profile}-{date}.log`. Updated `API/Program.cs`, `UI/Program.cs`. |

## Related

- `XYDataLabs.OrderProcessingSystem.UI/Controllers/HomeController.cs` — `PopulateCommonViewData()`
- `XYDataLabs.OrderProcessingSystem.UI/Views/Home/_Layout.cshtml` — tenant dropdown gate
- `XYDataLabs.OrderProcessingSystem.API/Program.cs` — all API-side gates
- `XYDataLabs.OrderProcessingSystem.UI/Dockerfile` — `ENV DOTNET_RUNNING_IN_CONTAINER=true`
- ADR-007: Hybrid multi-tenant model
- ADR-009: Tenant isolation hardening
