# Local Development Commands

**Part of:** [quick-command-reference.md](./quick-command-reference.md)  
**Last Updated:** April 11, 2026

---

## 🔨 Build & Test

```powershell
# Clean build
dotnet clean
dotnet build XYDataLabs.OrderProcessingSystem.sln

# Release build
dotnet build XYDataLabs.OrderProcessingSystem.sln --configuration Release

# Restore NuGet packages
dotnet restore

# Run all unit tests
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/

# Run tests with detailed output
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/ --verbosity detailed

# Run specific test
dotnet test --filter "FullyQualifiedName~TestMethodName"

# Generate test coverage report
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

### **Focused verification used for Phase 7 closure**

```powershell
# Full solution build with CI-style path output
dotnet build .\XYDataLabs.OrderProcessingSystem.sln /property:GenerateFullPaths=true "/consoleloggerparameters:NoSummary;ForceNoAlign"

# Application-layer regression pass
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Application.Tests\XYDataLabs.OrderProcessingSystem.Application.Tests.csproj --no-build --logger "console;verbosity=minimal"

# SQL Server-backed integration verification
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --logger "console;verbosity=minimal"
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --no-build --logger "console;verbosity=minimal"
```

### **Gateway groundwork verification (Phase 9 baseline)**

```powershell
# Build and test the gateway in isolation
dotnet build .\XYDataLabs.OrderProcessingSystem.Gateway\XYDataLabs.OrderProcessingSystem.Gateway.csproj
dotnet test .\tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj --logger "console;verbosity=minimal"
```

Notes:
- Use this focused slice whenever the YARP gateway host or its proxy rules change.
- The current regression suite covers unsupported-host rejection, payload-limit rejection, `/health/alive`, and correlation propagation on a proxied route.

### **Payment verification — physical logs + DB correlation**

```powershell
# Local dev runtime
.\scripts\verify-payment-run-physical.ps1 -Runtime local -Environment dev -Profile http

# Docker dev runtime
.\scripts\verify-payment-run-physical.ps1 -Runtime docker -Environment dev -Profile http
```

Notes:
- Add `-RunPrefix <OR-prefix>` when more than one payment run exists for the day.
- The verifier proves API log -> UI telemetry -> DB for the same charge IDs and is the preferred path over manually rebuilding the log/SQL correlation flow.

---

## 🚀 Run Applications Locally

```powershell
# Run API
cd XYDataLabs.OrderProcessingSystem.API
dotnet run --launch-profile http

# Run React web frontend
npm --prefix .\frontend run dev:web

# Run the gateway baseline (expects API on 5010 and UI on 5173)
dotnet run --project .\XYDataLabs.OrderProcessingSystem.Gateway\XYDataLabs.OrderProcessingSystem.Gateway.csproj --launch-profile http

# Run with specific environment
dotnet run --environment Development
dotnet run --environment Staging
dotnet run --environment Production

# Explicit environment variable + run
$env:ASPNETCORE_ENVIRONMENT = "Development"
dotnet run
```

> **Visual Studio (recommended for API debugging):** Press F5 for the API, then run `npm --prefix .\frontend run dev:web` for the React frontend.  
> **VS Code:** Set `"env": { "ASPNETCORE_ENVIRONMENT": "Development" }` in `launch.json`.
> **Workspace standard:** Keep `XYDataLabs.OrderProcessingSystem.sln` focused on .NET projects, tests, infrastructure, and repo-owned assets. Run the React UI from the separate `frontend/` workspace with `npm --prefix .\frontend run dev:web`; do not add the React workspace to the Visual Studio solution unless a deliberate tooling requirement justifies it.

### **Gateway baseline local flow**

```powershell
# Terminal 1
dotnet run --project .\XYDataLabs.OrderProcessingSystem.API\XYDataLabs.OrderProcessingSystem.API.csproj --launch-profile http

# Terminal 2
npm --prefix .\frontend run dev:web

# Terminal 3
dotnet run --project .\XYDataLabs.OrderProcessingSystem.Gateway\XYDataLabs.OrderProcessingSystem.Gateway.csproj --launch-profile http
```

Automation shortcuts:
- VS Code task: `1 Run: 06 Gateway Baseline Http`
- Direct gateway launcher: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-gateway-profile.ps1 -Profile http`
- Stop all local HTTP processes, including the gateway: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-dev-sessions.ps1 -Profile http`

Docker-targeted gateway profiles:
- Dev Docker gateway: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-gateway-profile.ps1 -Profile docker-dev-http`
- Staging Docker gateway: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-gateway-profile.ps1 -Profile docker-stg-http`
- Production Docker gateway: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-gateway-profile.ps1 -Profile docker-prod-http`
- VS Code tasks: `1 Run: 13 Gateway over Docker Dev Http`, `1 Run: 23 Gateway over Docker Stg Http`, `1 Run: 33 Gateway over Docker Prod Http`

Current VS Code validation paths:
- The existing 5-task `docker-dev-http` sequence is the canonical full Docker validation lane.
- Use the Docker lane when you want the full Phase 10 verification path: start profile, wait ready, Playwright smoke, integration suite, payment matrix, and full validation.
- The local Phase 10 lane stays the faster developer loop and focuses on profile start plus smoke.
- Phase 10 split-service validation has its own local container-app lane because it introduces separate gateway, Orders, Inventory, Notifications, and UI containers.
- The new Phase 10-friendly aliases are `Phase 10: Local Container Stack 01 Start`, `Phase 10: Local Container Stack 01 Start (Reuse Existing)`, `Phase 10: Local Container Stack 02 Smoke`, `Phase 10: Local Container Stack 03 Full Validation`, and `Phase 10: Local Container Stack Cleanup`.
- Use the local Phase 10 aliases when you want the newer split-service local validation path without changing the older task contract.

Local HTTP clean vs reuse commands:

- Clean start: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/start-phase10-local-profile.ps1 -Profile http`
- Reuse an already-running local HTTP stack: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/start-phase10-local-profile.ps1 -Profile http -ReuseExistingStack`
- Reuse only, without auto-start: add `-SkipStartIfNeeded` to the reuse command
- Stop local HTTP processes: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-dev-sessions.ps1 -Profile http`
- VS Code task labels:
  - `1 Run: Phase 10 Local HTTP 00 Start Profile (Clean)`
  - `1 Run: Phase 10 Local HTTP 00 Start Profile (Reuse Existing)`
  - `1 Run: Phase 10 Local HTTP 01 Wait Ready + Keycloak`
  - `1 Run: Phase 10 Local Container Stack 00 Start Stack Only (Clean)`
  - `1 Run: Phase 10 Local Container Stack 00 Start Stack Only (Reuse Existing)`

Preferred Phase 10 Docker E2E references:
- Terminal run-hook: `npm --prefix automation run xydatalabs-test-docker-local-e2e-dev`
- VS Code task: `1 Run: xydatalabs-test-docker-local-e2e-dev (Docker Dev HTTP E2E)`
- Direct script equivalent: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-phase10-docker-dev-e2e-hook.ps1 -StabilizationDelaySeconds 60`
- Use this when you want one command that recreates the stack in clean Azure-parity mode, applies EF migrations, verifies SQL/Redis/payment-provider baseline readiness, runs ready/smoke/integration/matrix/full validation, writes the log trail, and cleans up the local stack.
- Use `-ReuseExistingStack` on the direct script only when you intentionally want a faster debugging pass against the current local containers and database state.
- Clean Docker run: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-phase10-docker-dev-e2e-hook.ps1 -StabilizationDelaySeconds 60`
- Reuse Docker stack: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-phase10-docker-dev-e2e-hook.ps1 -StabilizationDelaySeconds 60 -ReuseExistingStack`
- Reuse Docker stack without auto-start: add `-SkipStartIfNeeded`

Shared local/Azure contract:
- Service names follow the same `appname-env` shape wherever we control them: local Docker service names, Azure Container App names, and cleanup targets all use the environment suffix so the deploy and teardown steps stay symmetrical.
- Phase 10 local Docker and Azure Container Apps both use the same `orderprocessing-*` service image family, which keeps image creation and deployment inputs aligned across hosts.
- The runtime payload is service-specific in both places: gateway, Orders, Inventory, Notifications, and UI each get their own image or container artifact rather than a single shared image.
- The clean local Phase 10 hook is the pre-Azure parity gate: if migrations, TenantC dedicated DB, payment-provider baseline, tenant payment routing, or Redis readiness are broken locally, do not run Azure `01` yet.
- For the local container-stack and Docker Dev HTTP lanes, the recommended operating pattern is: make `00` the clean setup/start step, then let `01` through `05` reuse that same running stack. Use the explicit reuse variants only when you are intentionally debugging startup or want to skip the teardown/rebuild cycle.
- Azure keeps the public ingress hostnames platform-generated unless a friendly alias is explicitly bound. That means the operator flow is still the same even though the public URL is different: deploy, verify outputs, smoke, then promote or alias.
- The preferred automation rule is the same across both platforms: keep the compute names deterministic, keep the environment suffix explicit, and keep cleanup keyed off the exact names created by the deployment.

Access paths:
- Gateway health: `http://localhost:5080/health`
- Gateway home: `http://localhost:5080/`
- React UI: `http://localhost:5022/customers`
- Orders service: `http://localhost:5081/health`
- Inventory service: `http://localhost:5082/health`
- Notifications service: `http://localhost:5083/health`
- The local Phase 10 container stack uses service-name routing inside Docker so the gateway can talk to Orders, Inventory, Notifications, and UI as separate containers.

### **Phase 9 closeout run order**

Use this tracked sequence when you want to re-run or verify the local/Docker closeout flow without relying on generated artifacts:

| Lane | Purpose | Steps |
|---|---|---|
| Local Phase 10 quick loop | Fast developer validation | `01 Wait Ready + Keycloak`, `02 Playwright Smoke` |
| Docker Dev HTTP full validation | Full Phase 10 verification | Clean or reuse profile start, then `01 Wait Ready + Keycloak`, `02 Playwright Smoke`, `03 Integration Suite`, `04 Payment Matrix`, `05 Full Validation` |

1. Local HTTP: `1 Run: Local HTTP 01 Env Ready`
2. Local HTTP: `1 Run: Local HTTP 02 Playwright Smoke`
3. Local HTTP: `1 Run: Local HTTP 03 Matrix Sanity (1 Tenant, Local HTTP)`
4. Local HTTP: `1 Run: Local HTTP 04 Integration Suite (Local SQL, No Docker)`
5. Local HTTP: `1 Run: Local HTTP 05 Full Validation (All Tenants + Providers, Local HTTP)`
6. Docker Dev HTTP: `1 Run: Docker Dev HTTP 01 Profile (Clean)` or `1 Run: Docker Dev HTTP 01 Profile (Reuse Existing)`
7. Docker Dev HTTP: `1 Run: Docker Dev HTTP 01 Env Ready + Keycloak (Clean, Docker Dev HTTP)` or `1 Run: Docker Dev HTTP 01 Env Ready + Keycloak (Reuse Existing, Docker Dev HTTP)`
8. Docker Dev HTTP: `1 Run: Docker Dev HTTP 02 Playwright Smoke`
9. Docker Dev HTTP: `1 Run: Docker Dev HTTP 03 Integration Suite`
10. Docker Dev HTTP: `1 Run: Docker Dev HTTP 04 Payment Matrix`
11. Docker Dev HTTP: `1 Run: Docker Dev HTTP 05 Full Validation`

Notes:
- The canonical evidence folders remain `TestResults\Integration`, `TestResults\PaymentMatrix`, and `TestResults\Playwright`.
- Runtime-generated folders under `automation/dist/` and `frontend/apps/web/test-results/` stay untracked.
- Any env or Keycloak seed files should be reviewed before commit because they may contain secret-like material.
- `Resources/Keycloak/realm-export.json` stays as a checked-in template only; the real values must come from `.NET user-secrets` for local HTTP, `Resources/Docker/.env.local` for Docker dev HTTP, GitHub secrets in CI, and Key Vault in Azure.

### **Port Allocations**
| Mode | API | Web |
|------|-----|-----|
| Local API + Vite | http://localhost:5010 | http://localhost:5173 |
| Local Gateway baseline | http://localhost:5080 | Proxies API/UI |
| Docker dev | http://localhost:5020 | http://localhost:5022 |
| Docker stg | http://localhost:5030 | http://localhost:5032 |

---

## 🔍 EF Core SQL Logging — Local Dev Only

> **Why logging only fires locally:**  
> Azure App Service has `ASPNETCORE_ENVIRONMENT=dev` (lowercase). `IsDevelopment()` checks for the exact  
> string `"Development"` — so it returns **false** on Azure → SQL logging is intentionally OFF.  
> This prevents SQL parameter values (which may contain sensitive data) from appearing in production logs.  
> Locally (Visual Studio F5 / `dotnet run --environment Development`), `IsDevelopment()` = **true** → logging fires.

**Expected console output when running locally:**
```
[03:23:48 INF] [dev] [Local] Request: GET /api/Customer/GetAllCustomersByName
                              ?name=at&pageNumber=1&pageSize=10  Body:

info: 20-03-2026 03:23:48.503 RelationalEventId.CommandExecuted[20101]
      (Microsoft.EntityFrameworkCore.Database.Command)
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
      SELECT [c].[CustomerId], [c].[CreatedBy], [c].[CreatedDate], [c].[Email],
             [c].[Name], [c].[OpenpayCustomerId], [c].[UpdatedBy], [c].[UpdatedDate]
      FROM [Customers] AS [c]

[03:23:48 INF] [dev] [Local] Response: 200 Body: [{"customerId":2,"name":"Katelyn Reynolds",...}]
[03:23:48 INF] [dev] [Local] HTTP GET /api/Customer/GetAllCustomersByName responded 200 in 587.2204 ms
```

| Log line | What it tells you |
|---|---|
| `[dev] [Local] Request:` | Request logging middleware — env tag + machine tag |
| `Executed DbCommand (20ms)` | EF Core SQL logging via `LogTo(Console.WriteLine)` |
| `SELECT FROM [Customers]` | Actual SQL sent to the database |
| `[dev] [Local] Response: 200` | Response middleware with status + JSON body |
| `responded 200 in 587ms` | ASP.NET Core built-in request timing |

**Code location:** `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs`
```csharp
if (builder.Environment.IsDevelopment())
{
    options.LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()
           .EnableDetailedErrors();
}
```

---

## 🐳 Docker Commands

### **Project Docker Scripts (preferred)**
```powershell
# Start — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Start — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

### **Docker Container Management**
```powershell
# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Start/Stop containers
docker start container-name
docker stop container-name

# View logs
docker logs container-name
docker logs container-name --follow       # Follow logs in real-time

# Remove container
docker rm container-name
docker rm -f container-name               # Force remove running container
```

### **Docker Image Management**
```powershell
# List images
docker images

# Build image
docker build -t app-name:tag .

# Remove image
docker rmi image-name:tag

# Clean up unused images
docker image prune -a
```

### **Docker Compose**
```powershell
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs
docker-compose logs -f service-name

# Rebuild and start
docker-compose up -d --build
```
