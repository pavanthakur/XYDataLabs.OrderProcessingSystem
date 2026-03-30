# XYDataLabs Order Processing System

> A production-grade, multi-tenant order and payment processing platform built with Clean Architecture, .NET 8, and Azure.

[![CI](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/ci.yml/badge.svg)](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/ci.yml)
[![Deploy API to Azure](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/deploy-api-to-azure.yml/badge.svg?branch=dev)](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/deploy-api-to-azure.yml)
[![Deploy UI to Azure](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/deploy-ui-to-azure.yml/badge.svg?branch=dev)](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/deploy-ui-to-azure.yml)
[![Docker Health](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/docker-health.yml/badge.svg)](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/docker-health.yml)

**Live dev environment:**
- API (Swagger): https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- UI: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## What This Is

A backend system for processing customer orders and payments across multiple tenants. Each tenant can operate on a shared database pool or a fully isolated dedicated database. The system handles the full payment lifecycle including 3D Secure authentication, card transaction tracking, and provider callback reconciliation.

This is not a tutorial project — it is built to the constraints of real SaaS systems: tenant isolation, PCI DSS card data rules, architecture-enforced contracts, and Azure-deployed infrastructure.

---

## Architecture

Clean Architecture with four layers, dependencies pointing strictly inward. The domain has no external references. Infrastructure depends on Application interfaces, never the reverse.

```
XYDataLabs.OrderProcessingSystem
|
+-- Domain          -> Entities, value objects, domain rules (zero external deps)
+-- Application     -> CQRS command/query handlers, DTOs, FluentValidation behaviors
+-- Infrastructure  -> EF Core, DbContext, migrations, Key Vault, DI wiring
+-- API             -> ASP.NET Core controllers, TenantMiddleware, Swagger
+-- SharedKernel    -> Result<T>, ITenantProvider, ActivitySources, base entities
|
+-- OpenPayAdapter  -> Payment provider adapter (IOpenPayAdapterService)
+-- UI              -> ASP.NET Core MVC frontend
```

Layer dependency rules are enforced by [ArchitectureTests.cs](tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/ArchitectureTests.cs) — any violation fails the build.

---

## Key Design Decisions

### Multi-tenancy

Every inbound request carries an `X-Tenant-Code` header. `TenantMiddleware` resolves this to a tenant context before the request reaches any controller. Missing or unknown codes return HTTP 400. Suspended or decommissioned tenants return HTTP 403.

Two isolation models are supported:

| Model | How it works |
|-------|-------------|
| **Shared Pool** | All shared-pool tenants use one database, isolated by EF Core global query filters scoped to `TenantId` |
| **Dedicated** | Tenant gets its own database. Connection string stored per-tenant in Key Vault. `DbInitializer` migrates and seeds dedicated DBs independently |

`ITenantProvider` is the single source of tenant context for all downstream code. No ambient or static state.

`Tenant` table itself has no global query filter — this avoids bootstrap recursion when resolving the tenant from an incoming code.

### Payment Identifier Model

Three distinct identifiers, each with strict surface rules:

| Identifier | Purpose | Visible in |
|------------|---------|------------|
| `CustomerOrderId` | Business-visible order reference | UI, customer-facing API responses |
| `AttemptOrderId` | Per-attempt provider reference | Provider calls, callback reconciliation only |
| `PaymentTraceId` | Internal correlation | Structured logs and telemetry only — never in API responses |

This separation prevents leaking internal tracking IDs to customers and makes debugging across provider callbacks deterministic. Architecture tests enforce these surface rules at CI time.

### Payment Provider (OpenPayAdapter)

The payment provider is wrapped behind `IOpenPayAdapterService`. The application layer calls the interface; the adapter handles the OpenPay-specific protocol. Swapping providers does not touch domain or application code.

3D Secure is configured per-tenant via `PaymentProvider.Use3DSecure` — it is a business rule per tenant, not a global configuration flag.

### PCI DSS Compliance

- Raw PAN and CVV are never stored
- `CardTransaction` stores only masked card data (BIN + masked middle + last 4)
- Architecture tests enforce these constraints at build time — violations fail CI

### CQRS (Hand-rolled)

`ICommand`/`IQuery`/`IDispatcher` pattern with FluentValidation pipeline behaviors. No MediatR dependency — the dispatcher is explicit and owned. All handlers return `Result<T>` — no exceptions thrown from business logic; all errors are typed.

---

## Tech Stack

| Concern | Technology |
|---------|-----------|
| Runtime | .NET 8 / ASP.NET Core 8 |
| ORM | Entity Framework Core 8.0.13 (SQL Server) |
| Database | Azure SQL / SQL Server (Testcontainers for integration tests) |
| CQRS | Hand-rolled (`ICommand`/`IQuery`/`IDispatcher`) |
| Validation | FluentValidation 11.x |
| Mapping | Manual extension methods (`Mappings/`) |
| Logging | Serilog 4.x (Console + File + Application Insights) |
| Tracing | OpenTelemetry 1.10 -> Azure Monitor |
| Payment gateway | OpenPay (`Openpay` NuGet 1.0.25) via adapter pattern |
| Caching | Redis (`IDistributedCache` — provider-agnostic; backed by StackExchange.Redis in production) |
| Rate limiting | `Microsoft.AspNetCore.RateLimiting` (built-in) — per-tenant fixed window; 20 req/min (payments), 200 req/min (orders + customers) |
| Resilience | `Microsoft.Extensions.Resilience` (Polly v8) — retry 3× + circuit breaker on OpenPay SDK calls |
| Health checks | `/health/live` (liveness) · `/health/ready` (SQL + Redis) — `AspNetCore.HealthChecks.SqlServer` + `AspNetCore.HealthChecks.Redis` |
| Architecture tests | NetArchTest.Rules 1.3.2 |
| Integration tests | Testcontainers.MsSql 4.3 + `WebApplicationFactory` |
| Unit tests | xUnit + Moq + FluentAssertions + Bogus |
| Code analysis | SonarAnalyzer + Meziantou.Analyzer + Roslynator |
| IaC | Azure Bicep (subscription + resource group scope) |
| Hosting | Azure App Service (API + UI) — dev/staging/prod |
| Secrets | Azure Key Vault + Managed Identity (`DefaultAzureCredential`) |
| CI/CD | GitHub Actions (9 workflows) + OIDC (passwordless) |
| Containers | Docker (multi-stage) + docker-compose per environment |

---

## API Endpoints

All business endpoints require header: `X-Tenant-Code: <tenant-code>`

### Tenant Header Reference

```
X-Tenant-Code: TenantA          -> resolves to shared-pool tenant
X-Tenant-Code: TenantC          -> resolves to dedicated-DB tenant

Missing X-Tenant-Code            -> HTTP 400
Unknown X-Tenant-Code            -> HTTP 400
Suspended/Decommissioned tenant  -> HTTP 403
```

### Orders

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/Order` | Create an order for a customer with specified products |
| `GET` | `/api/v1/Order/{id}` | Get order details including products and total price |

**Create Order — Request / Response**
```json
POST /api/v1/Order
X-Tenant-Code: TenantA

{ "customerId": 1, "productIds": [10, 11, 12] }
```
```json
HTTP 201 Created
{
  "orderId": 42,
  "customerId": 1,
  "orderDate": "2025-03-26T10:00:00Z",
  "totalPrice": 149.97,
  "isFulfilled": false,
  "products": [
    { "productId": 10, "name": "Widget A", "price": 49.99, "quantity": 1 },
    { "productId": 11, "name": "Widget B", "price": 49.99, "quantity": 2 }
  ]
}
```

### Customers

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/Customer/GetAllCustomers` | List all customers |
| `GET` | `/api/v1/Customer/GetAllCustomersByName?name=Alice&pageNumber=1&pageSize=10` | Paginated search by name |
| `GET` | `/api/v1/Customer/{id}` | Get customer with full order history |
| `POST` | `/api/v1/Customer` | Create new customer |
| `PUT` | `/api/v1/Customer/{id}` | Update customer details |
| `DELETE` | `/api/v1/Customer/{id}` | Delete customer |

### Payments

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/Payments/ProcessPayment` | Tokenize card and process payment (atomic) |
| `POST` | `/api/v1/Payments/{paymentId}/confirm-status` | Confirm payment status from OpenPay webhook |

**Process Payment — Request / Response**
```json
POST /api/v1/Payments/ProcessPayment
X-Tenant-Code: TenantA

{
  "name": "Alice Smith",
  "email": "alice@example.com",
  "deviceSessionId": "kR_LxnObgi55FnqLOFuKOg",
  "cardNumber": "4111111111111111",
  "expirationYear": "26",
  "expirationMonth": "12",
  "cvv2": "110",
  "customerOrderId": "ORD-2025-00042"
}
```
```json
HTTP 200 OK
{
  "customerOrderId": "ORD-2025-00042",
  "transactionId": "trxfkzjdxecotuqtv5tf",
  "status": "completed"
}
```

> `PaymentTraceId` is an internal correlation ID — it appears in structured logs only, never in API responses.

### Info

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/Info/environment` | Runtime metadata — environment, Docker/Azure context, active tenant. No `X-Tenant-Code` required. |

---

## Data Model

```
Tenant --< PaymentProvider --< PaymentMethod --< BillingCustomer --< CardTransaction
                                                               |         |
                                                               |         +--< TransactionStatusHistory
                                                               +--< PayinLog
                                               BillingCustomer --< BillingCustomerKeyInfo

Customer --< Order --< OrderProduct >-- Product
```

All payment entities inherit `BaseAuditableEntity { TenantId, CreatedBy, CreatedDate, UpdatedBy, UpdatedDate }` and are auto-filtered by EF Core global query filters scoped to the active tenant.

| Entity | Purpose |
|--------|---------|
| `Tenant` | Root multi-tenant aggregate — no global query filter |
| `Customer` / `Product` / `Order` / `OrderProduct` | Core order domain |
| `PaymentProvider` | Tenant-specific OpenPay configuration (URL, 3DS flag) |
| `PaymentMethod` | Tokenized card via OpenPay |
| `BillingCustomer` | Wraps OpenPay customer; tenant-scoped |
| `CardTransaction` | Payment attempt record; indexed on `(TenantId, CustomerOrderId)` and `(TenantId, AttemptOrderId)` |
| `PayinLog` | Reconciliation bridge between internal order IDs and OpenPay charge IDs |
| `TransactionStatusHistory` | Audit trail of all transaction state transitions |

---

## Payment Flow

```
POST /api/v1/Payments/ProcessPayment
    |
    v
ProcessPaymentCommandHandler
    +-- 1. Resolve TenantId (X-Tenant-Code header)
    +-- 2. Create BillingCustomer record
    +-- 3. OpenPayAdapter.CreateCustomerAsync()      --> OpenPay API
    +-- 4. OpenPayAdapter.CreateCardTokenAsync()     --> OpenPay API
    +-- 5. OpenPayAdapter.CreateChargeAsync()        --> OpenPay API
    +-- 6. Persist CardTransaction (status, masked card, AttemptOrderId)
    +-- 7. Persist PayinLog (reconciliation)
    +-- 8. Return PaymentDto { CustomerOrderId, TransactionId, Status }

POST /api/v1/Payments/{id}/confirm-status  <-- OpenPay webhook callback
    +-- 1. Look up CardTransaction by paymentId
    +-- 2. Update CardTransaction.TransactionStatus
    +-- 3. Append TransactionStatusHistory (audit)
    +-- 4. Return PaymentStatusDetailsDto
```

---

## How to Run Locally

### Option 1: Visual Studio (recommended for debugging)

1. Clone the repo
2. Configure `Resources/Configuration/sharedsettings.local.json` with your SQL Server connection string
3. Press **F5** — API at `http://localhost:5010/swagger`, UI at `http://localhost:5012`

### Option 2: Docker

**Prerequisites:** Docker Desktop running

```powershell
# HTTP profile (API + UI)
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Reset
```

| Service | URL |
|---------|-----|
| API (Swagger) | `http://localhost:5020/swagger` |
| UI | `http://localhost:5022` |

**Connection string config:** `Resources/Configuration/sharedsettings.dev.json`

```json
{
  "OrderProcessingSystemDbConnection": "Server=host.docker.internal,1433;Database=OrderProcessingDB;..."
}
```

---

## Running Tests

```bash
# All tests
dotnet test

# Architecture tests (layer boundaries, EF drift, identifier surface rules, PCI constraints)
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/

# Integration tests (requires Docker Desktop for Testcontainers SQL Server)
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/
```

Architecture tests will fail if:
- Any layer imports a dependency it must not have
- An EF migration has drifted from the current model
- Required composite indexes on tenant-scoped entities are missing
- A banned payment identifier name is introduced in a DTO surface
- Card data (PAN/CVV) storage constraints are violated

| Project | What it tests |
|---------|--------------|
| `Domain.Tests` | Entity logic, domain rules |
| `Application.Tests` | CQRS handler unit tests (Moq + Bogus) |
| `API.Tests` | Controller unit tests |
| `Integration.Tests` | Full HTTP round-trips; dedicated tenant DB isolation; payment flows (Testcontainers) |
| `Architecture.Tests` | Layer boundaries + EF migration drift + multi-tenant schema + PCI constraints |

---

## CI/CD & Azure Deployment

9 GitHub Actions workflows enforce quality gates before every deployment. Authentication uses passwordless OIDC — no client secrets stored anywhere; each workflow run exchanges a short-lived GitHub OIDC token for an Azure AD federated credential. This is the production-standard alternative to storing service principal secrets in GitHub.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `azure-initial-setup.yml` | Manual (once) | OIDC App Registration + GitHub secrets |
| `azure-bootstrap.yml` | Manual | Provision Azure resources (App Service, SQL, Key Vault) |
| `deploy-api-to-azure.yml` | Push to dev/staging/main | Build -> test -> deploy API |
| `deploy-ui-to-azure.yml` | Push to dev/staging/main | Build -> test -> deploy UI |
| `infra-deploy.yml` | Manual | Bicep what-if + deploy |
| `validate-deployment.yml` | Reusable | Bicep what-if, OIDC verification |
| `deploy-and-verify.yml` | Push / manual | Full end-to-end: infra + apps + health checks |
| `docker-health.yml` | Push to main / PR | Docker startup smoke test |

**Branch to environment mapping:**

| Branch | Environment | Azure suffix |
|--------|-------------|-------------|
| `dev` | dev | `-dev` |
| `staging` | staging | `-stg` |
| `main` | prod | `-prod` |

Workflow guardrails still enforce this mapping explicitly in GitHub Actions.
Azure deployment scripts now read the same default mapping from `Resources/Azure-Deployment/branch-policy.json`.

See [.github/workflows/README.md](.github/workflows/README.md) for first-time setup.

---

## Architecture Governance

[ARCHITECTURE.md](ARCHITECTURE.md) is the binding standard for this codebase. It defines:
- Tenant model and resolution rules
- Payment identifier vocabulary and surface rules
- Banned identifier names
- Entity and DTO checklists
- Migration rules
- Required test coverage matrix

Any deviation from ARCHITECTURE.md requires an Architecture Decision Record (ADR) under [docs/architecture/decisions/](docs/architecture/decisions/).

---

## Project Structure

```
/
+-- XYDataLabs.OrderProcessingSystem.API/
+-- XYDataLabs.OrderProcessingSystem.Application/
+-- XYDataLabs.OrderProcessingSystem.Domain/
+-- XYDataLabs.OrderProcessingSystem.Infrastructure/
+-- XYDataLabs.OrderProcessingSystem.SharedKernel/
+-- XYDataLabs.OrderProcessingSystem.UI/
+-- XYDataLabs.OpenPayAdapter/
|
+-- tests/
|   +-- Architecture.Tests/     -> layer boundaries, EF drift, PCI constraints, identifier surface
|   +-- Integration.Tests/      -> dedicated tenant isolation, payment flows (Testcontainers)
|   +-- Application.Tests/      -> CQRS handler unit tests
|   +-- Domain.Tests/           -> entity logic
|   +-- API.Tests/              -> controller tests
|
+-- infra/                      -> Bicep IaC (subscription scope)
+-- bicep/                      -> Bicep IaC (resource group scope)
+-- Resources/
|   +-- Azure-Deployment/       -> 27 PowerShell provisioning scripts
|   +-- Configuration/          -> sharedsettings.{dev,stg,prod,local}.json
|   +-- Docker/                 -> start-docker.ps1 + docker-compose per environment
+-- scripts/                    -> GitHub App setup, OIDC secrets, bootstrap scripts
+-- docs/
|   +-- architecture/decisions/ -> ADRs (ADR-001 through ADR-006)
|   +-- runbooks/
|
+-- ARCHITECTURE.md             <- binding standard -- read before contributing
+-- ARCHITECTURE-EVOLUTION.md
+-- TROUBLESHOOTING-INDEX.md
```

---

## Documentation Index

| Document | Location |
|----------|----------|
| **Architecture standard** (binding) | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Architecture evolution (14-phase roadmap) | [ARCHITECTURE-EVOLUTION.md](ARCHITECTURE-EVOLUTION.md) |
| Architecture Decision Records | [docs/architecture/decisions/](docs/architecture/decisions/) |
| Azure deployment guide | [Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md](Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md) |
| Quick start (bootstrap) | [Documentation/QUICK-START-AZURE-BOOTSTRAP.md](Documentation/QUICK-START-AZURE-BOOTSTRAP.md) |
| CI/CD workflow guide | [.github/workflows/README.md](.github/workflows/README.md) |
| PowerShell scripts reference | [Resources/Azure-Deployment/README.md](Resources/Azure-Deployment/README.md) |
| Troubleshooting | [TROUBLESHOOTING-INDEX.md](TROUBLESHOOTING-INDEX.md) |

---

## License

[MIT](LICENSE)
