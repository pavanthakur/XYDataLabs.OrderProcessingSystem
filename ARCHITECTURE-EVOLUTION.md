# Architecture Evolution: Monolith to Enterprise Microservices

**Last Updated:** July 1, 2026
**Current Status:** Phase 8 Closeout Matrix Validation Passed ✅ | Track U U5 Complete ✅ | Phase 8.5 Complete ✅ | Phase 8.6 Complete ✅ | Phase 8.7 Complete ✅ | Phase 9 closeout complete for extraction/tasking ✅ | Phase 9.5 identity portability wiring implemented and runtime verified in local HTTP and Docker Dev HTTP ✅ | Phase 10.1 local baseline reconciliation complete ✅ | Phases 10, 11, 11.5, 12-14 Planned 📅 | Post-14 Horizons captured 📘

---

## 📊 Architecture Evolution Overview

This document tracks the architectural evolution of the XYDataLabs Order Processing System across
**14 core phases** plus post-14 horizons — from a monolithic application deployed on Azure App Service to a production-grade,
event-driven microservices platform with YARP gateway, Azure Container Apps, .NET Aspire
orchestration, Azure Service Bus messaging, multi-tenancy, and CQRS read/write separation
with MongoDB.

---

## 🛡️ Mandatory Phase Closeout Quality Gate

Before marking **any** architectural phase as complete, the following end-to-end success criteria must be met and verified:
1. **Docker Containerization Validation:** All modified or newly introduced services must successfully build, launch, and run correctly via the mapped Docker environment profiles (`dev`, `stg`, `prod`) with Docker SQL as the only valid runtime path.
2. **Integration Test Verification:** The backend integration test suite must pass against the active Docker validation slice, confirming database access and domain logic constraints are met.
3. **End-to-End Automation Coverage:** Playwright E2E automation (in the `automation/` workspace) must successfully navigate the full frontend-to-backend-to-payment cycle against the running containers without errors.

Every phase and sub-phase closure must also follow the repository-wide phase closure standard in `local models/zoocode/phase-closure-standard.md`, including the requirement to:
- keep the testcase matrix in the run transcript
- fail fast on missing infrastructure
- clean up orphan containers before sign-off
- document the restart commands and log file locations

If Phase 9 Docker bootstrap or SQL restore behavior regresses while running the closeout path, start with `docs/reference/docker-bootstrap-troubleshooting.md` before rerunning the phase bundle.

For phases that touch Docker runtime orchestration, payment automation runtime targets, or phase-closeout workflow surfaces, the closeout evidence must now be captured with the generated Docker validation bundle:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http
```

The bundle is written under `automation/reports/docker-validation/<bundleId>/` and must include `summary.md`, `summary.json`, raw test logs, target startup logs, and the referenced automation report path for the closeout session.

Any phase missing confirmed verifiable passes on these three metrics cannot be formally closed.

**Snapshot pair at major architectural seams.** Phase 7, 8, 11, 13, and 14 closeouts also cut a tag + backup branch pair per [ADR-018](docs/architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md) and [docs/internal/branch-and-blueprint-strategy.md](docs/internal/branch-and-blueprint-strategy.md). Tags use the format `v-YYYYMMDD-phase<N>-<slug>`; backup branches use `dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>`. The same strategy doc covers the two-layer reusable template (Layer 1 `dotnet new` NuGet template + Layer 2 GitHub template repo) that is extracted at Phase 14 closeout for side-project bootstrap.

---

## Baseline: Monolith on Azure App Service ✅ DEPLOYED

Historical note: the diagram below captures the original phase-1 baseline. The same UI App Service
now serves the React frontend after Track U U5; the MVC web host is retained here only as
historical context for the migration path.

### Timeline
- **Duration:** Weeks 1-4 (Days 1-31)
- **Completed:** January 26, 2026
- **Learning Focus:** Azure fundamentals, deployment, CI/CD, Infrastructure as Code

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    AZURE CLOUD                               │
│                                                              │
│  ┌──────────────────────┐         ┌──────────────────────┐  │
│  │   API App Service    │         │   UI App Service     │  │
│  │  (Monolith)          │         │   (MVC Web App)      │  │
│  │                      │         │                      │  │
│  │  • Orders            │◄────────┤  • Customer Views    │  │
│  │  • Customers         │         │  • Order Views       │  │
│  │  • Payments          │         │  • Payment UI        │  │
│  │  • OpenPay Adapter   │         │                      │  │
│  └──────────┬───────────┘         └──────────────────────┘  │
│             │                                                │
│             │                                                │
│  ┌──────────▼───────────┐         ┌──────────────────────┐  │
│  │  Azure SQL Database  │         │  Application         │  │
│  │  OrderProcessingDB   │         │  Insights            │  │
│  └──────────────────────┘         └──────────────────────┘  │
│                                                              │
│  ┌──────────────────────┐         ┌──────────────────────┐  │
│  │   Key Vault          │         │  GitHub Actions      │  │
│  │   (kv-orderprocessing) │       │  CI/CD + OIDC        │  │
│  └──────────────────────┘         └──────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Solution Structure (7 Projects)

```
XYDataLabs.OrderProcessingSystem.sln
├── XYDataLabs.OrderProcessingSystem.API          (Composition Root)
│   ├── Controllers/                              (Thin — IDispatcher only)
│   ├── Extensions/ResultExtensions.cs            (Result<T> → ActionResult)
│   ├── Middleware/
│   └── Program.cs
├── XYDataLabs.OrderProcessingSystem.Application  (Use Cases — CQRS)
│   ├── Abstractions/IAppDbContext.cs
│   ├── CQRS/                                     (Dispatcher, Behaviors)
│   ├── Features/Customers/                       (Commands + Queries)
│   ├── Features/Orders/                           (Commands + Queries)
│   ├── Features/Payments/                         (Commands)
│   ├── DTO/
│   └── Validators/
├── XYDataLabs.OrderProcessingSystem.Domain       (Entities — zero deps)
├── XYDataLabs.OrderProcessingSystem.Infrastructure (EF Core, DbContext)
├── XYDataLabs.OrderProcessingSystem.SharedKernel  (Result<T>, ApiResponse<T>)
├── frontend/apps/web                            (React Web App)
└── XYDataLabs.OpenPayAdapter                     (Payment Integration)
```

### Characteristics

✅ **Advantages:**
- Simple deployment (2 App Services)
- Easy debugging (single process)
- Straightforward development
- Direct database access
- No network latency between components
- Azure-native monitoring with App Insights

⚠️ **Limitations:**
- Tight coupling between business domains
- Scaling issues (must scale entire app)
- Deployment risk (one change affects all)
- Technology stack locked (all .NET)
- Difficult to parallelize development
- Database contention possible

### Production Status

| Component | Resource Name | Status |
|-----------|---------------|--------|
| **API** | `pavanthakur-orderprocessing-api-xyapp-dev` | ✅ Running |
| **Web** | `pavanthakur-orderprocessing-ui-xyapp-dev` | ✅ Running |
| **Database** | `orderprocessing-sql-dev / OrderProcessingSystem_Dev` | ✅ Active |
| **Monitoring** | `ai-orderprocessing-dev` | ✅ Active |
| **Secrets** | `kv-orderprocessing-dev` | ⚠️ Created (needs access config) |
| **CI/CD** | GitHub Actions (OIDC) | ✅ Working |

### URLs

- **API Swagger:** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **Web (React):** https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## Architecture Roadmap (14 Phases)

| # | Phase | Focus | Status |
|---|-------|-------|--------|
| **1** | Structural Foundation | SharedKernel, `Result<T>`, `IAppDbContext`, layer decoupling | ✅ **COMPLETE** |
| **2** | Hand-Rolled CQRS | Dispatcher, pipeline behaviors, 12 handlers, controller refactoring | ✅ **COMPLETE** |
| **3** | Observability (OpenTelemetry) | Auto-instrumentation, App Insights + OTLP, custom ActivitySource, correlation | ✅ **COMPLETE** |
| **4** | Multi-Tenancy Skeleton | `ITenantProvider`, EF global query filters, `X-Tenant-Code` header | ✅ **COMPLETE** |
| **5** | Test Project Restructure | Domain.Tests, Application.Tests, API.Tests, Integration.Tests (Testcontainers) | ✅ **COMPLETE** |
| **6** | Polish & Hardening | CachingBehavior, Redis, API versioning `/api/v1/`, health checks, CancellationToken, TimeProvider | ✅ **COMPLETE** |
| **7** | Tenant Enforcement & Ops | TenantValidationBehavior, AuditLog, security headers, liveness/readiness checks | ✅ **COMPLETE** |
| **8** | Event-Driven Foundation | Domain events, integration events, Outbox pattern, background publisher | ✅ **COMPLETE** |
| **8.5** | Secondary Payment Provider Architecture | Provider-neutral routing, per-tenant provider selection, `HttpClient`-based resilience, provider-aware idempotency and reconciliation | ✅ **COMPLETE** |
| **8.6** | Central Tenant Registry & Separation of Duties | `ITenantRegistry`, `Tenant.PaymentProviderCode` as sole routing authority, ops-owned DB, ADR-019 | ✅ **COMPLETE** |
| **8.7** | Provider Webhook Receiver & Async Payment Lifecycle | Signed webhooks, inbox idempotency, Outbox bridge, `payment.captured`/`payment.failed` handlers, tenant-aware async payment convergence | ✅ **COMPLETE** |
| **9** | YARP Microservices (Local) | Gateway, Orders/Inventory/Notifications APIs, Docker Compose, event-based communication | 📅 Planned |
| **9.5** | Cloud-Portable Identity Showcase | Local Keycloak portability proof for the JWT/OIDC pipeline without changing the Azure production identity model | ✅ Wiring implemented and runtime verified |
| **10** | Azure Container Apps | Real service hosts, ACA/ACR, Service Bus, DLQ Functions, Entra ID + JWT, managed transport identity, rollback/evidence | 🚧 In progress |
| **11** | Data Ownership & Autonomy | Database per service, remove shared DbContext, eventual consistency | 📅 Planned |
| **11.5** | Polyglot Persistence Showcase | Notifications module PostgreSQL pilot proving provider portability while Orders/Payments stay on Azure SQL | 📅 Planned |
| **12** | Platform Engineering & Operability | Private cloud edge/network, Blob/Event Grid, SQL managed identity, App Configuration, .NET 10 assessment, CI/CD, observability and resilience | 📅 Planned |
| **13** | Aspire & Final Maturity | Aspire AppHost deepening, distributed app testing, service discovery, manifest / `azd` evaluation, blue-green/canary deployment strategy | 📅 Planned |
| **14** | CQRS Read Model (MongoDB) | Separate read/write models, projection handlers, Hangfire, tenant-scoped documents | 📅 Planned |

---

## Post-Phase-9 Execution Ladder

After Phase 9 and 9.5, the architecture sequence is intentionally narrowed so each later phase solves one class of risk before the next one starts.

### Phase 10 - Azure Transport And Messaging Operations

Primary objective:
- Move the split architecture onto Azure transport primitives without changing the business semantics already proven in the local and Docker validation lanes.

Tooling prerequisite:
- Before Phase 10 implementation or validation changes, use [Phase 10 Tool Prerequisites](docs/guides/development/phase10-tool-prerequisites.md) as the canonical developer-machine setup and readiness gate. Docker Compose remains the canonical local runtime, Aspire remains optional, and Azure remains the deployment-validation environment.

Broad checklist:
- Replace Orders, Payments, Inventory, and Notifications compatibility stubs with real module behavior and authoritative persistence.
- Lock Service Bus topology, delivery semantics, DLQ ownership, replay limits, and observable failure categories.
- Connect committed outbox publication to real Inventory and Notifications consumers protected by inbox/idempotency.
- Deploy separate DLQ intake and approval/replay Functions and prove their actual Azure invocation.
- Keep database migrations and demo seeding out of API startup; use a dedicated migrator or deployment-time startup step.
- Apply Entra JWT authorization, tenant claim/header consistency, Service Bus managed identity/RBAC, and Key Vault secret resolution.
- Prove correlation continuity through gateway calls, brokered messages, Functions, and business persistence.
- Use immutable artifacts, retained healthy revisions, expand/contract migrations, and an executed rollback path.
- Close through the graduated local, Docker, CI, and Azure lifecycle with machine-readable and operator evidence.
- Keep APIM/private ingress, private networking, Service Bus Premium/Private Link, Blob/Event Grid, SQL managed identity, and Front Door/WAF in Phase 12 under ADR-025.

Execution lanes:
- 10.2: real service migration.
- 10.3: real Service Bus processing.
- 10.4: DLQ and deployed Functions.
- 10.5: identity and secretless transport.
- 10.6: operations and non-functional proof.
- 10.7: acceptance and closeout.

Exit intent:
- The system can run on Azure transport with observable, replayable, idempotent message handling.

### Phase 11 - Saga Orchestration And Data Ownership

Primary objective:
- Turn the split modules into genuinely autonomous services with explicit orchestration and service-owned persistence.

Broad checklist:
- Enforce database-per-service and remove remaining shared-schema assumptions.
- ADR the saga style: Durable Functions versus custom process manager.
- Implement the fulfillment flow with compensation, timeout handling, and replay-safe steps.
- Define authoritative ownership for every externally visible business field.
- Add reconciliation logic and drift detection between service state and projections.
- Keep migrations and data evolution independent per service.

Execution lanes:
- Lane 1: service-owned stores and shared-schema removal.
- Lane 2: saga orchestration choice, compensation flow, and timeout handling.
- Lane 3: reconciliation and drift detection between operational state and read surfaces.
- Lane 4: migration ownership and service-local data evolution.

Exit intent:
- Cross-service consistency is event-driven, compensations are tested, and service autonomy is real.

### Phase 11.5 - PostgreSQL Portability Proof

Primary objective:
- Prove bounded RDBMS portability without changing the platform-wide Azure SQL production posture.

Broad checklist:
- Limit PostgreSQL to the Notifications pilot.
- Validate migration, observability, and operational parity for the pilot slice.
- Record the trade-offs clearly without allowing the pilot to become a hidden second standard.

Execution lanes:
- Lane 1: Notifications-only provider swap and module boundary validation.
- Lane 2: provider-specific migrations, schema behavior, and local Docker support.
- Lane 3: operational parity checks for logging, metrics, and deployment flow.
- Lane 4: trade-off documentation so the pilot never becomes a silent default.

### Phase 12 - Platform Engineering And Operability

Primary objective:
- Raise the system from technically functional to operationally dependable.

Broad checklist:
- Consolidate App Configuration, Key Vault, options validation, and rollout safety.
- Make exception handling explicit: global exception middleware, `ProblemDetails`, and clean business-vs-infrastructure error boundaries.
- Standardize structured logging and correlation: Serilog, `CorrelationId`, request metadata, and trace-friendly log enrichment.
- Add validation as a first-class boundary concern: FluentValidation, pipeline behaviors, and request-shape enforcement before handlers.
- Add feature flags with environment and tenant-aware rollout discipline.
- Standardize cache policy, tenant-safe keys, and invalidation discipline.
- Keep resilience explicit: retries, timeout, circuit breaker, and fallback policy decisions should be documented rather than scattered.
- Carry API versioning and deprecation posture as a platform concern, not an ad hoc controller tweak.
- Maintain health checks for database, cache, storage, and transport dependencies as an operational contract.
- Standardize rate-limiting and tenant-aware quota policy as operational guardrails, not one-off endpoint tweaks.
- Mature per-service CI/CD, rollback, and image-scanning flows.
- Add supply-chain guardrails: SBOM generation, vulnerability scanning, registry retention, and evidence retention for release artifacts.
- Harden API consumer experience: error contracts, versioning posture, generated-client expectations, and documentation quality.
- Improve API consumer experience deliberately: stable OpenAPI surface, stronger docs UX, and explicit contract governance for frontend and operator tooling.
- Add the required runbooks, Azure Monitor dashboards, Application Insights workbooks, alert rules, and cost/performance operating guidance.
- Establish a background-job lane for replay, rebuild, cleanup, and maintenance work where these tasks do not belong in request handlers.
- Finish the .NET 10 assessment and keep the runtime-upgrade decision evidence-based.

Execution lanes:
- Lane 1: configuration, Key Vault, and rollout safety.
- Lane 2: validation, error handling, structured logging, and health checks.
- Lane 3: feature flags, rate limiting, quotas, and cache conventions.
- Lane 4: consumer experience, OpenAPI quality, API versioning, and contract governance.
- Lane 5: CI/CD, rollback, image scanning, and operator runbooks.
- Lane 6: background jobs and the .NET 10 evidence gate.

Exit intent:
- Deployment, rollback, configuration rollout, and incident response are all repeatable and documented.

### Phase 13 - Aspire Deepening And Orchestration Quality

Primary objective:
- Improve inner-loop and orchestration quality after transport and autonomy are already stable.

Broad checklist:
- Validate AppHost as a genuine developer-experience improvement while Docker remains the strict baseline.
- Assess generated manifests and `azd` only with explicit evidence and ADR-backed decisions.
- Keep this phase focused on orchestration maturity, not on reopening earlier service-boundary decisions.

Execution lanes:
- Lane 1: AppHost and local orchestration quality.
- Lane 2: distributed app testing against the live Aspire graph.
- Lane 3: manifest and `azd` evaluation for deployment packaging.
- Lane 4: trace and resource-composition refinements only after the deployment story is evidence-backed.

### Phase 14 - CQRS Read Model Maturity

Primary objective:
- Add projection-driven read autonomy only after service autonomy and transport operations are already trustworthy.

Broad checklist:
- Separate read models where scale, reporting, or UX needs justify them.
- Build projection replay, rebuild, and repair operations as first-class support paths.
- Keep eventual consistency windows explicit in both backend and frontend design.

Execution lanes:
- Lane 1: projection handlers and event-to-document translation.
- Lane 2: read-store shape, partitioning, and query optimization.
- Lane 3: rebuild and backfill jobs for operational maintenance.
- Lane 4: tenant-safe read isolation and replay-friendly projection discipline.

Exit intent:
- Read-side autonomy improves system capability without reducing operational clarity.

### Cross-Phase Decision Rules

- Hosting decisions must stay explicit: App Service, Azure Functions, ACA, or later AKS each need an ADR-backed reason.
- Service Bus, Event Grid, and direct sync calls must be chosen by delivery semantics, not convenience.
- Security defaults remain managed identity, RBAC, Key Vault, and claims-based boundaries.
- Every phase must preserve distributed tracing, idempotency, and executable closeout proof.

---

## Enterprise Alignment Rules For Phases 8.5-14

The Julio Casal bootcamp stack is being used here as an **enterprise capability benchmark**, not as a blanket instruction to replace every Azure-first production choice already made in this repository.

### Adopt the pattern, not accidental vendor churn

- **Adopt as first-class roadmap work:** production engineering mindset, observability depth, worker services, async messaging, resilience, configuration management, API consumer experience, integration testing, troubleshooting, performance, cloud networking, modern local orchestration, and repeatable deployment operations.
- **Keep production-authoritative choices:** Azure SQL remains the main transactional store; Entra ID plus managed identity remains the production identity path; React remains the active frontend track.
- **Use isolated portability proofs where they add architect-level credibility:** Keycloak in Phase 9.5 and PostgreSQL in Phase 11.5.
- **Do not force premature platform churn:** .NET 10 and deeper Aspire adoption stay gated behind the planned upgrade window in Phases 12-13.

### Capability-to-phase mapping

| Capability area | Where it is made explicit in the roadmap |
|---|---|
| API consumer experience, contract quality, generated client expectations, consistent error design | Track U carry-forward + Phase 8.5 + Phase 9 + Phase 12 |
| Worker services, outbox/inbox, webhook/event convergence, DLQ and replay operations | Phase 8 + Phase 8.7 + Phase 10 |
| OpenTelemetry depth, distributed tracing, dependency graphs, service-level observability | Phase 3 baseline + Phase 9 + Phase 10 + Phase 13 |
| Configuration management, Options Pattern discipline, App Configuration, secret rollout safety | Phase 10 + Phase 12 |
| Cloud networking, ingress, gateway, CORS, TLS, Front Door / APIM concerns | Phase 10 + Phase 12 |
| Integration and distributed testing, including containerized and orchestration-aware validation | Phase 9 + Phase 13 |
| Container registry ownership, image retention, SBOM, scanning, and supply-chain evidence | Phase 10 ACR cutover + Phase 12 |
| Performance, caching, cost optimization, production troubleshooting and diagnostics | Phase 12 + Phase 13 |
| Optional Kubernetes or Kafka adoption | Post-14 assessment only, unless a concrete platform requirement appears earlier |
| AI-assisted product capabilities: Azure AI Search, Azure OpenAI, AI agents, and summarization | Post-14 horizons only, unless a product requirement promotes them |
| Modern local development and orchestration | Phase 9 (Aspire-Lite) + Phase 13 |

### Explicit non-goals for the current production path

- Do **not** replace Azure SQL platform-wide with PostgreSQL; keep PostgreSQL isolated to the Phase 11.5 Notifications pilot.
- Do **not** replace Entra ID in production with Keycloak; keep Keycloak as the local-only Phase 9.5 portability showcase.
- Do **not** add a separate Blazor implementation phase unless a product-specific need appears.

### Enterprise Standardization Backlog

The external starter-kit benchmark is useful as an enterprise guide, but we are **adopting patterns selectively** rather than copying it wholesale. This backlog maps the most relevant enterprise patterns into the existing phase plan so the roadmap stays consistent with the current architecture and with the Azure production posture already chosen in this repo.

| Pattern area | Decision | Phase | Notes |
|---|---|---|---|
| One-command inner-loop orchestration | Adopt | Phase 9 + Phase 13 | Aspire AppHost enters in Phase 9 as the local orchestration seam; Phase 13 deepens it with distributed app testing and manifest/`azd` evaluation. |
| Shared service defaults, health checks, service discovery, resilient `HttpClient` setup | Adopt | Phase 9 | Standardize common host wiring through `ServiceDefaults` instead of repeating it in each service. |
| Gateway edge validation, request filtering, and consistent ProblemDetails responses | Adopt | Phase 9 + Phase 10 | Keep YARP boundary behavior explicit before cloud transport rollout. |
| Module contracts, architecture tests, and per-module persistence boundaries | Adopt | Phase 9 + Phase 11 | Preserve the current Clean Architecture boundaries; do not replace them with a wholesale vertical-slice rewrite. |
| Dedicated module contract assemblies / versioned DTO packages | Adopt | Phase 9 + Phase 11 | Use explicit module contracts where cross-module compilation is needed; do not leak internals between modules. |
| Centralized configuration, secret hygiene, and per-environment rollout safety | Adopt | Phase 10 + Phase 12 | Use App Configuration, Key Vault, and environment-scoped secrets only after the platform transport is stable. |
| Validation, ProblemDetails, structured logging, and health checks | Adopt | Phase 12 | Treat these as foundational platform behaviors, not per-endpoint extras. |
| Resilience policy, retry, timeout, and circuit-breaker standards | Adopt | Phase 9 + Phase 12 | Keep Polly and failure semantics explicit across services and outbound integrations. |
| One-shot migrator and seeder flow | Adopt | Phase 10 | Prefer deployment-time or startup orchestration for repeatable migrations and seed data instead of ad hoc manual setup. |
| Dedicated migrator / no API-startup migrations | Adopt | Phase 10 | Keep schema upgrades and demo seeding as explicit operational steps so startup failures and runtime side effects stay predictable. |
| Idempotency key support at external write boundaries | Adopt | Phase 10 + Phase 12 | Apply to replay-sensitive commands and public write endpoints where duplicate submission is a real risk. |
| Observability depth, dashboards, and production troubleshooting runbooks | Adopt | Phase 12 | Treat this as platform engineering, not feature work. |
| Feature flags with tenant-aware rollout | Adopt | Phase 12 | Use for controlled activation and safer rollout, not as a substitute for architecture decisions. |
| API documentation and consumer experience | Adopt | Phase 12 + Track U | Keep OpenAPI / Scalar-style docs, generated clients, and clear consumer guidance as a first-class product surface. |
| Frontend runtime config and typed API client | Adopt | Track U + Phase 12 | Keep environment-specific configuration out of rebuilds; prefer a typed client surface over ad hoc fetch calls. |
| Data ownership, service autonomy, and eventual consistency | Adopt | Phase 11 | Split databases after the transport and boundary work is proven. |
| Polyglot persistence pilot | Adapt | Phase 11.5 | Keep PostgreSQL isolated to the Notifications module proof; do not change the primary Azure SQL posture. |
| Source-generated CQRS engine modernization | Assess first, then decide | Phase 13 assessment | Keep the current hand-rolled CQRS as the active baseline; revisit source-generated Mediator only if maintenance cost or feature throughput makes the change worthwhile. |
| Permission catalog and policy registry | Adopt | Phase 10 + Phase 12 | Keep coarse and fine-grained authorization rules explicit even though the production IdP stays Entra-based. |
| Tenant provisioning, migrations, and seeding | Adopt | Phase 10 + Phase 11 | Make tenant onboarding explicit: provisioning, per-tenant upgrades, and seed data should be repeatable and environment-aware. |
| One-shot migrator and demo seeder policy | Adopt | Phase 10 | Keep migrations and demo seeding out of API startup; run them through a dedicated startup or deployment step. |
| Soft-delete and audit interceptors | Adopt | Phase 11 + Phase 12 | Add explicit soft-delete and audit policy only where module behavior and compliance needs justify it. |
| Cache policy conventions | Adopt | Phase 12 | Keep Redis as the baseline cache, but standardize TTLs, invalidation, and tenant-safe cache keys instead of ad hoc caching. |
| Background worker lane for maintenance / rebuild / replay tasks | Adopt | Phase 12 + Phase 14 | Treat scheduled jobs, rebuilds, and replay operations as first-class operational code, not ad hoc scripts. |
| Tenant-aware quota, idempotency, and rate-limit controls | Adopt | Phase 9 + Phase 10 | Keep operational guardrails explicit at the gateway and cloud edge. |
| File/storage ingestion and attachment flow | Adopt | Phase 10 | Keep Blob-backed attachment handling, upload abstraction, and downstream processing in the cloud transport phase, not as a local-only helper. |
| Mailing / notification dispatch | Adopt | Phase 11 + Phase 12 | Keep outbound mail or async notification delivery under the Notifications module instead of scattering providers across features. |
| CQRS read models, projections, and snapshot/rebuild jobs | Adopt | Phase 14 | These belong after service autonomy and orchestration maturity are in place. |
| Azure Container Registry, runtime image ownership, and image retention | Adopt | Phase 10 + Phase 12 | ACR is the enterprise runtime-image target; cleanup, SBOM, and scan evidence must travel with the cutover instead of becoming a later afterthought. |
| Single execution packet: `runId`, one run folder, one summary, and one uploaded artifact bundle | Adopt | Phase 10 + Phase 12 | Phase 10 keeps the transport/operator validation packet consistent; Phase 12 generalizes the pattern across CI, coverage, release evidence, and retention. |
| Workflow summary contract with resource links, endpoint links, status, and next operator action | Adopt | Phase 10 + Phase 12 | Phase 10 wrappers and smoke workflows already need this for Azure validation; Phase 12 makes it a repo-wide CI/CD standard. |
| SQL credential hardening with managed identity | Defer until platform baseline is stable | Phase 12 | Phase 10 may bootstrap SQL with generated credentials stored through controlled secret paths; managed identity for SQL becomes the hardening target after Azure parity is proven. |
| Structured logs enriched with `runId` plus component, timestamp, and level | Adopt | Phase 10 + Phase 12 | Phase 10 starts with validation hooks and operator summaries; Phase 12 standardizes service/runtime logging policy. |
| OpenTelemetry trace/span expansion over the run packet | Assess after baseline | Phase 13+ | Keep the current correlation and App Insights proof intact. Add deeper trace/span mapping only when distributed app testing and orchestration maturity justify the extra complexity. |
| Observability dashboards, alert workbooks, and dependency maps | Adopt | Phase 12 + Phase 13 | Move beyond raw traces by creating operator-facing dashboards for gateway, transport, ACA revisions, DLQ, latency, and dependency health. |
| AKS / Kubernetes platform adoption | Assess only | Post-14 / platform need | ACA remains the current default. Promote AKS only if the system needs cluster-level control, custom operators, service mesh depth, or enterprise platform standardization. |
| Kafka / streaming platform adoption | Assess only | Post-14 / product need | Service Bus remains the work-distribution and enterprise messaging default. Promote Kafka only for high-throughput event streams, replayable logs, or cross-domain analytics needs that Service Bus/Event Grid do not satisfy. |
| Azure AI Search, Azure OpenAI, and AI agent capabilities | Defer to product horizon | Horizon 16+ | Keep AI features out of the core platform unless a real support, search, summarization, or automation use case appears. |
| Alternate identity provider parity proof | Defer to local-only proof | Phase 9.5 | Keycloak remains a portability showcase; Azure production continues to use Microsoft Entra ID. |
| SignalR / SSE real-time UI streams | Defer unless product need appears | Phase 13+ / product need | Keep real-time UI channels out of the base roadmap until a concrete user journey requires them. |
| Admin impersonation / delegated support workflows | Defer unless product need appears | Phase 12+ / product need | Only add delegated support flows if the product genuinely needs staff-level troubleshooting or customer support impersonation. |
| Multi-frontend expansion beyond the current web client | Defer unless product need appears | Phase 13+ / product need | The repo already has one active React web client; a second client or admin console should be justified by product scope, not architecture fashion. |
| Template / CLI packaging of the repo as a starter kit | Defer to productization track | Phase 14+ / separate track | Useful only if we intentionally decide to publish the architecture as a reusable template. |
| ASP.NET Identity / session-based app auth | Reject for production path | N/A | Production auth is claims-based Entra/Keycloak OIDC; do not introduce a second auth stack unless a product requirement forces it. |
| .NET 10 runtime migration from .NET 8 | Assess first, then decide | Phase 12 assessment, Phase 13 gate | This is **not** a Phase 10 deliverable. Phase 12 owns compatibility evidence and upgrade readiness; Phase 13 is the explicit go/no-go gate if the upgrade is still justified. |
| Path-scoped CI, warnings-as-errors, and full automated test matrix | Adopt | Phase 12 + Phase 13 | Keep backend, frontend, integration, and Playwright coverage split by path so failures are visible without running the whole world every time. |
| Wholesale rewrite to a different starter-kit architecture | Reject | N/A | Keep the current repo’s Clean Architecture, eventing model, and Azure-first production choices. Use the starter-kit guidance for pattern ideas only. |

#### Practical rule for roadmap reading

- If the item changes the cloud transport, gateway, or service split, it belongs in Phase 10 or 11.
- If the item changes build/deploy/runtime governance, it belongs in Phase 12.
- If the item changes developer experience or orchestration quality, it belongs in Phase 13.
- If the item changes read-model shape or reporting strategy, it belongs in Phase 14.
- If the item is only a portability or learning proof, keep it isolated like Phase 9.5 and do not promote it into production planning.
- If the item is a second auth stack, alternate platform rewrite, or unrelated technology swap, reject it unless a product requirement forces it.

#### Planning labels

- **Planned** means the item is still intended work and belongs in the numbered roadmap.
- **Assessment** means the item needs evidence, compatibility checks, or an ADR-backed decision before implementation is allowed.
- **Deferred** means the item is intentionally out of scope for the current phase and must stay in deferred-work tracking until a new business need appears.

## Parallel Track U — UI Modernization Program 📅

Track U is a parallel UI replacement program and does **not** renumber backend Phases 8-14.

**Status:** React web now owns the active runtime and deployment path; backend Phase 8 is no longer blocked by the MVC retirement gate.

**Purpose:** Replace the MVC UI with React web first, remove MVC from the active runtime, and
then enable React Native / mobile on the same API contract.

### Track U Phases

- **U1** — contract freeze and migration rules
- **U2** — React web foundation (`frontend/`, generated SDK, tenant bootstrap)
- **U3** — feature-slice replacement of MVC browser journeys
- **U4** — API rehoming of MVC-owned server endpoints (`/payment/callback`, `/payment/client-event`)
- **U5** — MVC cutover and removal from the active deployment model
- **U6** — mobile enablement on the stabilized web contract

### Track U Gate

Backend Phase 8 remains the next backend phase, but its implementation starts only after Track U
Phase U5 is complete.

The local HTTP path, Docker web profiles, and Azure deployment path now target the React frontend.
`XYDataLabs.OrderProcessingSystem.UI` has been removed from the active runtime and solution graph.

**Canonical references:**

- `docs/guides/development/api-contract-audit.md`
- `docs/guides/development/ui-modernization-plan.md`
- `docs/guides/development/payment-journey-automation-blueprint.md`

## Companion Payment Automation Blueprint

Before backend Phase 8 implementation expands the payment surface further, the separate browser
automation plan is frozen in `docs/guides/development/payment-journey-automation-blueprint.md`.

Pointer precedence for this companion plan is intentional:

1. `ARCHITECTURE-EVOLUTION.md` is the primary roadmap pointer.
2. `README.md` and `docs/DEVELOPER-OPERATING-MODEL.md` are discovery surfaces.
3. `docs/guides/development/ui-modernization-plan.md` is the sibling planning surface.
4. `docs/internal/AZURE-PROGRESS-EVALUATION.md` records status only.

---

## Phase 1 — Structural Foundation ✅
- Renamed `Utilities` project → `SharedKernel` (project, .csproj refs, namespaces, .sln)
- Added `Result<T>` + `Error` types in `SharedKernel/Results/`
- Added `ApiResponse<T>` standard envelope
- Added `IAppDbContext` interface in `Application/Abstractions/`
- `OrderProcessingSystemDbContext` implements `IAppDbContext`
- Changed all services: concrete DbContext → `IAppDbContext`
- Removed Application → Infrastructure project reference
- Moved DI wiring to API composition root
- **Roslyn analyzers** — `Roslynator.Analyzers`, `Meziantou.Analyzer`, `SonarAnalyzer.CSharp` in `Directory.Build.props` (global, build-time only); enforces code quality, security patterns, and anti-pattern detection at build time

## Phase 2 — Hand-Rolled CQRS ✅
- CQRS abstractions: `ICommand<T>`, `IQuery<T>`, `ICommandHandler`, `IQueryHandler`, `IPipelineBehavior`, `IDispatcher`
- `Dispatcher` — resolves handlers from DI, chains pipeline behaviors
- `ValidationBehavior` — runs FluentValidation, returns `Result<T>.Failure` on errors
- `LoggingBehavior` — structured logging with duration tracking
- `CqrsServiceExtensions.AddCqrs()` — assembly-scanning auto-registration
- 12 handlers: 7 Customer (Create, GetAll, GetById, GetByName, GetWithOrders, Update, Delete), 2 Order (CreateOrder, GetOrderDetails), 1 Payment (ProcessPayment), + info endpoint unchanged
- All controllers refactored to thin `IDispatcher`-only delegates
- `ResultExtensions` maps `Result<T>` → `ApiResponse<T>` → HTTP status codes
- Old service layer deleted (ICustomerService, IOrderService, IOpenPayService, CustomerService, OrderService, OpenPayService, CustomerValidator, OrderValidator)
- All 31 unit tests rewritten and passing
- **Committed:** `85fdd46` on `dev` branch (March 21, 2026)

## Phase 3 — Observability (OpenTelemetry) ✅
- Added 8 NuGet packages to SharedKernel (7 OpenTelemetry + Serilog)
- Created `AddObservability(serviceName, configuration, activitySourceNames)` extension in `SharedKernel/Observability/`
- Auto-instrumentation: ASP.NET Core, HttpClient, SqlClient, Runtime metrics
- Azure Monitor exporter (App Insights) + conditional OTLP exporter (Jaeger/Aspire)
- Created 3 `ActivitySource` classes: `OrderProcessing.Orders`, `.Customers`, `.Payments`
- Added activity spans to `CreateOrderCommandHandler` and `ProcessPaymentCommandHandler`
- Created `CorrelationMiddleware` in SharedKernel — extracts `Activity.TraceId`, enriches Serilog `LogContext`, adds `X-Trace-Id` response header
- Updated Serilog output templates: `{CorrelationId}` → `[{TraceId}]` in all 4 sharedsettings files
- Wired API + UI `Program.cs` with `AddObservability()` and `CorrelationMiddleware`
- Bumped `Microsoft.Extensions.DependencyInjection` + `Options.ConfigurationExtensions` to 9.0.0
- Build: 0 errors, 31/31 tests passing

## Phase 4 — Multi-Tenancy Skeleton ✅
- `ITenantProvider` interface in `SharedKernel/Multitenancy/` (cross-cutting, avoids circular dependency)
- `TenantId` property added to both `BaseAuditableEntity` and `BaseAuditableCreateEntity` — covers all 13 entities
- EF Global Query Filters on all 13 entity `DbSet`s with `_tenantProvider == null ||` guard for design-time/test compat
- `SaveChangesAsync` override auto-stamps `TenantId` on Added entities (both base classes)
- `TenantMiddleware` extracts `X-Tenant-Code` header, stores in `HttpContext.Items`, enriches Serilog `LogContext`
- `HeaderTenantProvider` reads tenant from `HttpContext.Items` at DI scope resolution
- AppMasterData is scoped (per-request) — reads from tenant-routed DbContext, respects query filter (ADR-009)
- Wired in API + UI `Program.cs` (Scoped DI, middleware before `CorrelationMiddleware`)
- Build: 0 errors, 31/31 tests passing

## Phase 5 — Test Project Restructure ✅
- Created 4 test projects under `tests/` solution folder:
  - `Domain.Tests` — 8 entity tests (Customer defaults, Order defaults, OrderProduct computed price, tenant inheritance)
  - `Application.Tests` — 17 handler tests migrated (OrderHandlerTests, CustomerHandlerTests) + 4 TestBase classes
  - `API.Tests` — 15 controller tests migrated (OrderControllerTests, CustomersControllerTests)
  - `Integration.Tests` — 4 end-to-end scenario tests (Testcontainers SQL Server + WebApplicationFactory)
- Added `public partial class Program { }` to API for WebApplicationFactory<Program> access
- `SqlServerFixture` — Testcontainers `MsSqlContainer` with shared `[Collection("SqlServer")]`
- `IntegrationTestWebAppFactory` — replaces DbContext with Testcontainers connection string
- Removed old `XYDataLabs.OrderProcessingSystem.UnitTest` project from solution
- **Architecture tests** (`NetArchTest.Rules`) — compile-time enforcement of layer boundaries: Domain has zero dependencies, Application never references Infrastructure, no circular references between projects
- Build: 0 errors, 39/39 unit tests passing (integration tests require Docker)

## Phase 6 — Polish & Hardening ✅
- `CancellationToken` propagated through all 10 controller actions → Dispatcher → handlers
- `TimeProvider` abstraction replaces `DateTime.UtcNow` (InfoController, ProcessPaymentCommandHandler); registered as `TimeProvider.System` singleton
- `ICacheable` interface + `CachingBehavior<TRequest,TResult>` pipeline behavior (outermost, before logging)
- `IDistributedCache`: Redis via `StackExchangeRedisCache` when connection string present, `DistributedMemoryCache` fallback
- `GetAllCustomersQuery` implements `ICacheable` (5-min cache, key `customers:all`)
- `[JsonConstructor]` on `Result<T>` and `Error` for cache serialization round-trip
- `/health` endpoint with SQL Server health check (`AspNetCore.HealthChecks.SqlServer`)
- API versioning: `Asp.Versioning.Mvc` — URL segment `/api/v1/[controller]`, `[ApiVersion("1.0")]` on all controllers
- Swagger configured with `SubstituteApiVersionInUrl`, versioned group `'v'VVV`
- 3 new CachingBehavior unit tests (cache miss, cache hit, non-cacheable passthrough)
- All integration test routes updated to `/api/v1/` paths
- **Central Package Management (CPM)** — `ManagePackageVersionsCentrally=true` in `Directory.Packages.props`; all `Version=""` attributes removed from individual `.csproj` files; single source of truth for all NuGet package versions across the solution
- Build: 0 errors, 42/42 unit tests passing

---

## Phase 7 — Tenant Enforcement & Operational Discipline ✅

- **Completed:** April 5, 2026
- **Verification freeze:** April 10, 2026 — latest Phase 7 baseline validated on local, Docker, and Azure; Azure Initial Setup and dev bootstrap both completed successfully.

**Focus:** Make the system secure, tenant-safe, and production-ready.

### Key Deliverables

- `TenantValidationBehavior<TRequest, TResult>` — CQRS pipeline behavior enforcing tenant consistency across all requests
- `AuditLog` table (tenant-scoped) with structured entries for create/update/delete operations
- Structured logging enrichment: `TenantId`, `TraceId`, request name on every log line
- **Problem Details (RFC 9457)** — standardized error responses (`type`, `title`, `status`, `detail`, `traceId`, `tenantId`) on all endpoints
- **Global exception middleware** — catch-all that converts unhandled exceptions → `ProblemDetails` (no stack traces in production)
- **Order aggregate hardening** — `Order` now uses a private constructor, `Create()` factory, explicit status transitions, and optimistic concurrency token
- Security headers middleware:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security` (HSTS)
- OpenTelemetry baseline in Phase 7 now includes a focused custom business-metrics slice for tenant-validation rejection, ProblemDetails responses, and payment outcome plus latency; cross-runtime verification of those metrics remains part of final closeout before Phase 8 broadens the runtime surface
- Split health checks into `/health/live` (liveness) and `/health/ready` (readiness with SQL + Redis)

### DDD Tactical Patterns

- **Aggregate root** — `Order` entity with private constructor, `Create()` factory method returning a domain-local `DomainResult<Order>` so Domain keeps zero project references
- **State machine** — `Order` status transitions: `Created → Paid → Shipped → Delivered → Cancelled` with explicit transition methods (`Pay()`, `Ship()`, `Deliver()`, `Cancel()`) returning a domain-local result; invalid transitions return failure, never throw
- **Value objects** — `Money` is implemented as an immutable value object with explicit validation; `Address` is intentionally deferred until a concrete customer, billing, or shipping boundary needs a first-class model
- **Strongly-typed IDs** — `OrderId`, `CustomerId`, `ProductId` as `readonly record struct` wrappers around `Guid`; eliminates parameter-swap bugs (`Guid orderId, Guid customerId` → `OrderId orderId, CustomerId customerId`); EF Core value converters for transparent persistence
- **Optimistic concurrency** — `RowVersion` (`byte[]` / `[Timestamp]`) is now applied to `Order`; broader rollout to other aggregates stays deferred until another aggregate shows real competing-writer risk
- **Domain invariants** — enforced inside aggregate methods (e.g. cannot ship an unpaid order), returning `Result<T>.Failure` with descriptive `Error` — no exceptions for business rules
- **Aggregate boundary rule** — aggregates enforce only their own transactional invariants and do not depend on injected infrastructure services. External collaboration (payment gateways, inventory lookups, messaging, persistence orchestration) remains in application handlers, process managers, or domain policies — keeps aggregate behavior focused and predictable

### Builds On

- Phase 4 (multi-tenancy skeleton — `ITenantProvider`, EF global filters)
- Phase 6 (basic `/health` endpoint, CachingBehavior pipeline)

### Outcome

Secure, observable, tenant-enforced system with rich domain model, standardized error handling — ready for event-driven decoupling.

### Known Risk (resolved in Phase 8)

The current `ProcessPaymentCommandHandler` makes three sequential OpenPay API calls (`CreateCustomerAsync` → `CreateCardTokenAsync` → `CreateChargeAsync`) followed by two DB writes (`CardTransaction` + `PayinLog`) in a single handler. If the process crashes or the DB transaction fails after the charge is successfully created at OpenPay, the charge is real but unrecorded — no reconciliation is possible without manually querying OpenPay by `AttemptOrderId`.

The Outbox Pattern in Phase 8 resolves this: write an `OutboxMessage` (with the charge result) in the same DB transaction as `CardTransaction`. The background publisher then confirms/reconciles asynchronously. Until Phase 8 ships, `AttemptOrderId` in `PayinLog` is the manual reconciliation key — queries to OpenPay's charge API can recover the charge state by that ID.

### Phase 7 Final Operational Closeout Gate

Phase 7 verification freeze passed on April 10, 2026. The final strict closeout gate was satisfied on April 28, 2026 before Phase 8 expanded the implementation surface:

- The implemented custom OpenTelemetry metrics slice was revalidated through local, Docker dev, and Azure proof runs, with `orderprocessing.payments.completed` and `orderprocessing.payments.duration` visible on the deployed Azure dev runtime and low-cardinality dimensions preserved
- Keep order-level concurrency surfacing deferred for now; retain the `Order.RowVersion` guard, but wait to freeze a client-facing conflict contract until a real multi-writer order update path exists
- Keep broader concurrency rollout deferred until another aggregate shows real competing-writer risk, and keep `Address` deferred until a concrete customer, billing, or shipping boundary exists
- Development validation was rerun on local dev, Docker dev, and Azure dev, including `/health/live`, `/health/ready`, `verify-payment-run-physical.ps1`, and `verify-payment-run-azure.ps1`
- Focused unit and API tests now cover the metrics slice, including in-process `MeterListener` proof for the shared business meter
- Integration tests remain a local or manual gate until a Linux Docker-capable CI runner is added; re-run the integration slice locally before another verification freeze

---

## Phase 8 — Event-Driven Foundation ✅

**Focus:** Freeze event contracts inside the monolith, make business state changes recoverable,
and keep transport in-process until Phase 10.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    EVENT-DRIVEN FLOW                              │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────────────────────┐   │
│  │  Command  │───►│  Handler │───►│  SQL Database             │   │
│  │  (API)    │    │          │    │  ┌────────┐ ┌──────────┐ │   │
│  └──────────┘    └────┬─────┘    │  │ Entity │ │ Outbox   │ │   │
│                       │          │  │ Tables │ │ Messages │ │   │
│                       │          │  └────────┘ └─────┬────┘ │   │
│                       │          └───────────────────┼──────┘   │
│                       │                              │          │
│                       │          ┌───────────────────▼────────┐ │
│                       │          │  Background Publisher       │ │
│                       │          │  (polls OutboxMessages)     │ │
│                       │          └───────────────────┬────────┘ │
│                       │                              │          │
│                       │          ┌───────────────────▼────────┐ │
│                       │          │  Event Dispatcher            │ │
│                       │          │  (in-memory, pluggable for   │ │
│                       │          │   Service Bus in Phase 10)   │ │
│                       │          └──┬──────────┬──────────┬───┘ │
│                       │             │          │          │      │
│              ┌────────▼──┐  ┌──────▼───┐ ┌────▼────┐ ┌──▼────┐ │
│              │ Domain     │  │Inventory │ │Notific- │ │Audit  │ │
│              │ Event      │  │Reserved  │ │ation    │ │Log    │ │
│              │ Handler    │  │Handler   │ │Handler  │ │Handler│ │
│              └───────────┘  └──────────┘ └─────────┘ └───────┘ │
│                                                                  │
│  Domain Events:              Integration Events:                 │
│  • OrderCreatedDomainEvent   • OrderCreatedIntegrationEvent      │
│  • PaymentProcessedEvent     • InventoryReservedIntegrationEvent │
│                              • NotificationRequestedEvent        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- **Event contracts in Application** — `IDomainEvent`, `IIntegrationEvent`, `EventEnvelope`, `IEventHandler<T>`, `IEventPublisher`, `IIdempotencyGuard`, and `DeliveryFailureCategory` live above Infrastructure. Domain remains free of messaging and transport vocabulary.
- **Aggregate event collection** — aggregate roots accumulate domain events internally and clear them only after successful persistence.
- **Explicit mapper layer** — `IDomainEventToIntegrationEventMapper<TDomain, TIntegration>` lives in Application. Domain raises events, Application maps them, Infrastructure persists integration event envelopes. Raw domain events are never written to the Outbox.
- **Payment recovery model** — `PaymentAttempt` is persisted before the provider call. `AttemptOrderId` becomes deterministic (`OrderId + AttemptNumber`) and drives a five-state lifecycle: `PendingProviderCall`, `ProviderAccepted`, `Succeeded`, `Failed`, `UnknownNeedsReconciliation`.
- **Persistence primitives** — `OutboxMessages`, `InboxMessages`, and `PaymentAttempts` live in the same database in Phase 8 with indexes defined up front.
- **DbContext save hook** — extract domain events, map them to integration events, and write `OutboxMessages` in the same SQL transaction as the business change.
- **Separate workers** — `OutboxPublisherWorker` owns event dispatch; `PaymentReconciliationWorker` owns recovery of payment outcomes. They are separate operational concerns and must not be merged.
- **In-memory dispatcher** — `IEventPublisher` is backed by an in-process dispatcher only. Azure Service Bus is explicitly deferred to Phase 10.
- **Initial event flows** — wire `OrderCreated`, `PaymentProcessed`, `InventoryReservationRequested`, `NotificationRequested`, and payment reconciliation outcome flows first.
- **Phase 8 test bar** — rollback leaves no outbox row; duplicate message is harmless; parallel handlers remain independent; publisher restart replays rows; reconciliation resolves `UnknownNeedsReconciliation`; cross-tenant isolation is preserved.

### Rules

- Events are **immutable** value objects — never modified after creation
- Outbox writes in the **same transaction** as the domain change (no dual-write)
- Background publisher is **idempotent** — Inbox table deduplicates by `MessageId` before handler execution
- **Event schema changes** must be backward-compatible (additive fields only; breaking changes = new version)
- **Parallel dispatch** — all handlers for a given event execute concurrently; failures are aggregated, not swallowed
- **Layering rule** — no Infrastructure type may be referenced from Domain or Application; architecture tests must enforce this before Phase 9 begins.
- **Transport rule** — no Service Bus publisher, receiver, processor, or DLQ concept is introduced in Phase 8 code.

### Entry Gate To Phase 9

- Event envelope fields and mapper strategy are frozen in writing before code begins.
- `PaymentAttempt` lifecycle and deterministic `AttemptOrderId` generation are frozen.
- Outbox and inbox work end-to-end.
- `OutboxPublisherWorker` and `PaymentReconciliationWorker` both run reliably.
- No Infrastructure type is referenced from Domain or Application.
- Architecture tests enforcing the boundary above are green.
- All six Phase 8 test categories pass.

### Current Closeout Status

Phase 8 closeout is now verified on the current branch. The explicit closeout evidence is green for all six required categories:

- rollback leaves no outbox row
- duplicate message is harmless
- parallel handlers remain independent
- publisher restart replays previously unprocessed rows
- reconciliation resolves `UnknownNeedsReconciliation`
- cross-tenant isolation is preserved
- architecture boundary tests are green

Future phase freezes that touch Docker runtime orchestration or payment automation must record the real Docker proof run with `scripts/generate-docker-validation-bundle.ps1` under `automation/reports/docker-validation/`; the dry-run automation matrix remains a separate governance gate for shared automation asset changes.

### Outcome

Loose coupling, recoverable payment workflows, idempotent delivery, and a transport-agnostic event backbone that can be swapped to Azure Service Bus later without redesigning contracts.

---

## Phase 8.5 — Secondary Payment Provider Architecture ✅

**Focus:** Keep OpenPay operational while finishing a provider-neutral payment boundary that can host a second provider selected for business fit, India viability, and testability. Runtime provider selection stays tenant-driven; no provider assumptions are allowed above the adapter boundary.

### Why This Phase Exists

The repository already has the right long-term seam: `PaymentProvider.ProviderType`, tenant-specific payment configuration, and a generic payment gateway contract. The remaining work is to finish that seam cleanly so the system can support OpenPay plus one additional provider without leaking provider-specific types or retry rules into Application or Domain.

### Per-Tenant Provider Selection

The `PaymentProvider` entity already owns `Use3DSecure`, `IsActive`, and `ProviderType`. The runtime rule is simple: each tenant resolves its active provider from data, and the composition root wires the matching gateway implementation.

This remains a runtime configuration decision. Switching a tenant's processor is a data change in `PaymentProvider`, not a code change or redeploy.

### Resilience And Reconciliation Rules

Each provider keeps its own adapter and its own transport strategy, but retry classification stays above the adapter boundary.

- **Retry scope is explicit** — automatic retries are allowed only for transient pre-accept failures such as connection drops, transport timeouts, or provider throttling with bounded backoff.
- **Provider-accepted responses are never blindly retried** — once the provider may have accepted the request, the attempt moves to reconciliation instead of issuing a second charge call.
- **Customer-action failures are not retried** — insufficient funds, expired cards, authentication-required outcomes, and hard declines remain terminal attempt results.
- **Attempt identity is stable** — one `AttemptOrderId` maps to one external attempt identity and one append-only attempt history.
- **Retry budget is bounded** — retry count, backoff window, and escalation path are configuration-driven and observable.
- **Unknown outcomes reconcile first** — the attempt transitions to `UnknownNeedsReconciliation` until the provider state is confirmed.
- **Append-only history is mandatory** — payment-attempt transitions and external observations remain immutable audit history.
- **Provider portability is preserved** — provider-specific idempotency features are used where available without forcing unsafe assumptions on providers that do not offer them natively.

### What Gets Added

- Provider-neutral request defaults and composition-root wiring for payment gateways
- Tenant-driven provider resolution with gateway/provider consistency checks
- Secondary-provider adapter once the provider is selected and legally testable
- Provider-aware retry classification and reconciliation rules on `PaymentAttempt`
- Webhook receiver scaffolding for asynchronous provider events (implemented in Phase 8.7)

### Builds On

- Phase 4 (multi-tenancy — `PaymentProvider` entity per tenant)
- Phase 7 (OpenPay resilience pipeline — retained for OpenPay tenants)
- Phase 8 (Outbox and Inbox patterns for durable payment-attempt persistence and reconciliation)

### Outcome

The payment runtime is provider-neutral above the adapter boundary. OpenPay remains the current live provider. Razorpay is implemented as the secondary provider with keyed DI, Polly resilience, and seed data per tenant (`IsActive = false` until a tenant explicitly enables it). Provider-aware retry classification is live: customer-action failures (`PaymentProviderCustomerActionException`) mark the attempt `Failed` (terminal); all other exceptions trigger `UnknownNeedsReconciliation` for reconciliation-worker recovery. Architecture boundary tests assert the Application layer has no dependency on either adapter assembly.

### Completed Items (Phase 8.5)

- `XYDataLabs.RazorpayAdapter` — full adapter project (SDK, Polly, config validation, keyed DI)
- `IPaymentProviderGateway` keyed registration for both OpenPay and Razorpay; Application `StartupHelper` factory resolves per-tenant at runtime
- `PaymentProviderCustomerActionException` in SharedKernel — cross-cutting typed exception for terminal declines
- `ProcessPaymentCommandHandler` catch differentiation — customer-action → `Failed`; transient/unknown → `UnknownNeedsReconciliation`
- `OpenPayPaymentGateway` — classifies HTTP 402/422 `OpenpayException` as customer-action
- `RazorpayPaymentGateway` — classifies `BadRequestError` as customer-action
- `IsProduction` flag on both `OpenPayConfig` and `RazorpayConfig`; default `false` in all environments (dev, stg, prod, local); startup logs `"TEST mode"` or `"LIVE mode"` for each adapter on initialisation
- `RazorpayConfigValidator` key-prefix cross-check: `rzp_live_*` key with `IsProduction=false` fails at startup; `rzp_test_*` key with `IsProduction=true` fails at startup; prevents misconfigured live keys silently charging real customers
- Seed data, config sections, and docker-compose env vars for Razorpay across all environments
- Unit tests: `RazorpayOptionsValidationTests`, `RazorpayPaymentGatewayTests`, `RazorpayConfigValidatorTests` (key-prefix vs mode cross-validation — 9 tests), retry classification tests in `ProcessPaymentHandlerTests`
- Architecture tests: `Application_Should_Not_Depend_On_OpenPayAdapter`, `Application_Should_Not_Depend_On_RazorpayAdapter`

---

## Phase 8.6 — Central Tenant Registry & Separation of Duties ✅

**Focus:** Extract tenant identity and per-tenant business configuration from application code and shared config files into a dedicated, ops-owned database. Developers have code access; they have no access to the Registry DB in any non-local environment.

### Why This Phase Is Required

The current `DbInitializer.SeedProviderAssignments` dictionary is an explicit, PR-reviewed placeholder — correct for this stage. But it has two compliance-level problems that block production readiness:

- **Developer visibility:** Any developer with repo access sees which real tenants exist and which payment provider each uses. In a regulated or multi-client context this breaks separation of duties.
- **Change path:** Changing a tenant's active provider requires a code change + PR + deploy. In production, this is an operational decision made by the business/ops team — not a code change.

The Central Tenant Registry moves tenant identity and provider assignment out of code and into a DB that the app reads via Managed Identity only, and that developer accounts cannot reach.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                   SEPARATION OF DUTIES                               │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Central Tenant Registry DB                      │   │
│  │          (ops/security team access only)                     │   │
│  │                                                              │   │
│  │  • Tenant master records (code, name, tier, status)          │   │
│  │  • Per-tenant payment provider assignment                    │   │
│  │  • Feature flags per tenant                                  │   │
│  │  • Tier limits and entitlements                              │   │
│  │                                                              │   │
│  │  Access: App Managed Identity (read-only) only               │   │
│  │          Developer accounts: DENIED in staging/prod          │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                         │  read-only at runtime                      │
│                         ▼                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Application Layer                               │   │
│  │  ITenantRegistry interface (Application — zero DB coupling)  │   │
│  │  SqlTenantRegistry (Infrastructure — reads Registry DB)      │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                         │                                            │
│  ┌──────────────────────▼───────────────────────────────────────┐   │
│  │  Shared-pool DB + Dedicated tenant DBs                       │   │
│  │  (orders, customers, payments — no tenant config here)       │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- **`ITenantRegistry` interface** — Application layer, zero DB coupling. Methods: `FindByCodeAsync`, `GetActiveTenantsAsync`
- **`SqlTenantRegistry` implementation** — Infrastructure layer. Separate `TenantRegistryDbContext` backed by the Registry DB. Connection string from Key Vault only, never from config files.
- **Registry DB schema** — `Tenants` table: `Id`, `Code`, `Name`, `Tier`, `IsActive`, `PaymentProviderCode`, `CreatedAt`, `ModifiedAt`
- **Remove `DbInitializer.SeedProviderAssignments` dictionary** — tenants are no longer seeded from code. The Registry DB is populated by ops tooling (migration + admin script), not by application startup.
- **Access control** — staging/prod Registry DB: Managed Identity connection only. No developer connection strings exist. No dev tooling is provided to browse the Registry in non-local environments.
- **Local dev exception** — local Registry DB seeded by a migration with the standard test tenants. Developers can see and modify local data freely; this is the only environment with developer DB access.
- **`ADR-019`** — documents the Central Registry decision, access model, schema versioning strategy, and ops change process.

### Security Rules (Non-Negotiable)

- Registry DB connection string is stored in Key Vault and injected at runtime via Managed Identity. It must never appear in any config file or source-controlled secret.
- Developer accounts are explicitly denied Registry DB access in staging and production via Azure SQL firewall + Entra ID RBAC. No exceptions.
- `ITenantRegistry` must be read-only. No application code may write to the Registry; writes are ops-only via controlled migration scripts.
- Audit log every read of the Registry that resolves a provider assignment in a financial operation.

### Closure Trigger

This phase is closed when:
1. `ITenantRegistry` + `SqlTenantRegistry` replace all `SeedProviderAssignments` lookups at runtime
2. `DbInitializer` has no knowledge of tenant-to-provider mappings
3. Staging Registry DB is access-controlled (developer connection denied, validated)
4. ADR-019 is merged and status is `Accepted`

### Completed Items (Phase 8.6)

- `ITenantRegistry` interface in Application layer — `FindByCodeAsync`, `GetActiveTenantsAsync`, `FindByCode` (sync)
- `TenantRegistryService` implementation in Infrastructure — reads `Tenant.PaymentProviderCode` from `TenantRegistryDbContext`
- `TenantRegistryDbContext` — separate EF Core context backed by the shared/central registry DB; always reads from the central DB regardless of tenant tier
- `AddTenantPaymentProviderCode` migration — idempotent seed: TenantA → Razorpay, TenantB → Razorpay, TenantC → OpenPay
- `DbInitializer` updated — all `PaymentProviders.IsActive = false`; no tenant-to-provider mapping knowledge remains in seed code
- `set-tenant-payment-provider.ps1` fixed — `Get-DatabaseName` always targets registry/central DB; TenantC dedicated DB (`OrderProcessingSystem_TenantC_{env}`) is for business ops only, never for registry lookups
- `ProcessPaymentCommandHandler` fixed — removed `IsActive` filter when resolving `PaymentProvider` FK; added guard for missing row
- `ADR-019` — merged and status `Accepted`; documents Central Registry decision, access model, `Tenant.PaymentProviderCode` as sole routing authority
- `deploy-api-to-azure.yml` — `Validate TenantC Dedicated Database Contract` step asserts `PaymentProviderCode IS NOT NULL` in both shared registry DB and dedicated DB
- **E2E provider matrix verified — Docker dev + Azure dev + Azure staging (all three environments):** 4/6 pass on every target; 2 expected failures (TenantB/Razorpay + TenantC/Razorpay) are an external Razorpay S2S account restriction, not a code issue
- Architecture tests, unit tests (53 Application, 88 API, 42 Architecture, 14 Domain), and secret scan all green
- Docker validation bundle generated (`scripts/generate-docker-validation-bundle.ps1 -Environment dev -Profile http`)

---

## Phase 8.7 — Provider Webhook Receiver & Event-Driven Payment Lifecycle ✅

**Focus:** Process asynchronous payment lifecycle events from the selected secondary provider securely and idempotently. This phase decouples local payment state from synchronous adapter polling whenever the provider supports authoritative webhook delivery.

### Why This Phase Is Required

Real-world payment systems cannot rely on synchronous response data alone. Asynchronous outcomes such as 3DS challenge completion, delayed bank authorisation, refunds, chargebacks, and dispute lifecycle changes arrive **after** the original request has returned. Without a webhook pipeline:
- 3DS-authorised payments stay marked `UnknownNeedsReconciliation` indefinitely
- Refunds or reversals initiated outside the original request path never reach our domain model
- Chargebacks/disputes are missed until manual finance reconciliation

### Key Deliverables

- **Webhook endpoint** — provider-scoped endpoint with raw-body buffering required for HMAC validation when the provider signs the raw payload
- **Signature validation** — provider-specific HMAC or signature verification before business deserialization
- **Webhook secret per environment** — stored in Key Vault and rotated independently from API keys
- **Inbox idempotency** — every provider event must map to a stable external event identity; Inbox deduplicates webhook deliveries
- **Event-to-domain mapping** — typed handlers per external event category (`payment succeeded`, `refund`, `dispute`, and similar lifecycle signals)
- **Outbox bridge** — webhook-derived state transitions emit domain events through the Outbox so internal subscribers (notifications, fulfilment) see them through the same pipeline as locally-originated events
- **Tenant resolution from metadata** — outgoing provider requests must stamp enough tenant metadata for webhook restoration before any DB access
- **Replay endpoint** (admin-only) — re-process a specific provider event when reconciliation is needed
- **Local development** — use the selected provider's sandbox and local forwarding toolchain if a public callback endpoint is required
- **Failure isolation** — webhook returns 2xx as soon as the event is durably persisted to Inbox; downstream processing happens asynchronously so a slow handler does not cause provider retries

### Absorbed Deferred Items (from Phase 8 backlog)

**DW-002 — Optimistic concurrency on webhook-mutated aggregates (medium risk)**

Phase 8.7 webhook handlers will write state transitions to `PaymentAttempt` and potentially other aggregates. Without row-version protection, a rapid duplicate webhook delivery that passes Inbox deduplication (e.g. a redelivery before the first write commits) can silently overwrite. The Phase 8 outbox already proved the pattern on `Order`. This phase extends `RowVersion` / `ConcurrencyToken` to every aggregate that a webhook handler mutates — at minimum `PaymentAttempt`. Architecture tests must enforce the property is present on all affected aggregates before Phase 8.7 closes.

**DW-003 — OpenTelemetry business metrics for webhook and inbox paths (low–medium)**

The webhook receiver is the natural place to instrument: HMAC validation failures (security signal), inbox deduplication hits (operational signal), handler latency per event type, and unresolvable-tenant rejections at the webhook boundary. These metrics are added as part of the webhook endpoint implementation using the existing OpenTelemetry baseline from Phase 7. No separate observability phase needed.

### Security Rules (Non-Negotiable)

- **Never trust webhook payload without signature validation** — drop the request before any business deserialization if signature check fails
- **Replay attack mitigation** — reject stale signed events according to the provider's timestamp tolerance; legitimate retries must preserve the same event identity so Inbox can deduplicate them
- **Tenant isolation in webhook** — handler must resolve tenant from `metadata.tenantId` and apply tenant context filters before any DB access; never trust customer ID alone
- **Webhook secret rotation** — support overlap windows and dual-secret validation when the provider supports staged rotation

### Connection to Phase 10

When Service Bus replaces the in-memory event bus in Phase 10, webhook-derived events flow through the same `order-events`/`payment-events` topics as locally-originated events. The webhook receiver remains a stateless Container App with public ingress; downstream handlers continue consuming from Service Bus subscriptions. No handler code changes between phases.

### Builds On

- Phase 8 (Inbox pattern for idempotency, Outbox for downstream propagation)
- Phase 8.5 (secondary-provider integration and tenant metadata convention)
- Phase 8.6 (tenant registry as the authoritative resolver — webhook tenant resolution uses `ITenantRegistry`)

### Completed Items (Phase 8.7)

- `WebhookController` — provider-scoped endpoint with raw-body buffering and HMAC validation before any business deserialization; returns 202 immediately after durable Inbox persist
- `IWebhookSignatureValidator` / `WebhookSignatureValidator` — HMAC-SHA256: Razorpay (hex uppercase, `X-Razorpay-Signature`), OpenPay (Base64, `X-OpenPay-Signature`); timing-safe via `CryptographicOperations.FixedTimeEquals`
- Webhook secrets per environment — config key `Webhooks:{Provider}:Secret`; local values managed by `setup-local.ps1` through gitignored `.env.local` plus dotnet user-secrets; Docker receives `Webhooks__{Provider}__Secret` from `.env.local`; Azure receives `Webhooks--{Provider}--Secret` from GitHub environment secrets via bootstrap/deploy Key Vault population
- `RecordWebhookEventCommand` / `RecordWebhookEventCommandHandler` — writes `InboxMessage` row with `Status=Received`; catches `DbUpdateException` on duplicate key → returns `Success(0)` (202 still returned)
- `InboxProcessorWorker` — `BackgroundService` (5 s poll); dispatches to `IWebhookEventHandler` dictionary keyed on `EventType` (case-insensitive); catches `DbUpdateConcurrencyException` → resets to Received and retries; marks unhandled event types as Processed without retry
- `PaymentCapturedHandler` — handles `payment.captured`; calls `attempt.MarkAsSucceeded(providerName)` → raises `PaymentAttemptSucceededDomainEvent` → DbContext harvests event and writes `OutboxMessage` atomically (Outbox bridge active)
- `PaymentFailedHandler` — handles `payment.failed`; calls `attempt.MarkAsFailed(providerName, errorReason)` → raises `PaymentAttemptFailedDomainEvent` → same Outbox bridge
- `PaymentAttemptSucceededDomainEvent` + `PaymentAttemptFailedDomainEvent` — domain events in Domain layer
- `PaymentAttemptSucceededV1` + `PaymentAttemptFailedV1` — integration event DTOs; `PaymentAttemptSucceededDomainEventMapper` + `PaymentAttemptFailedDomainEventMapper` auto-registered by `CqrsServiceExtensions` assembly scan
- `PaymentAttempt.MarkAsSucceeded()` + `PaymentAttempt.MarkAsFailed()` — idempotent entity methods; idempotency guard prevents re-raising domain events on repeated transitions
- DB-level Inbox dedup — unique filtered index `IX_InboxMessages_TenantId_ProviderEventId` on both `OrderProcessingSystem_Local` and `OrderProcessingSystem_TenantC`; migration `Phase_8_7_InboxDedup_UniqueProviderEventId` applied
- `RowVersion` optimistic concurrency on `PaymentAttempt` (DW-002 absorbed) — Architecture test enforces presence on all webhook-mutated aggregates
- OTel business metrics (DW-003 absorbed) — `WebhookHmacFailure`, `InboxDedupHit`, `InboxProcessed`, `InboxProcessingDuration` counters/histograms in `BusinessMetrics`
- `ADR-020` — documents the webhook receiver design, HMAC contract, Inbox/Outbox bridge, and deferred items
- **Tests/closeout gates** — total **287 tests all green** after hosted-checkout seed guardrail correction (API 95, Integration 72); strict build passed with known `NU1701` Openpay warnings only; docs links, secret hygiene, AI customization, and payment automation dry-run matrices passed before Phase 9
- **E2E: 25/25 pass** — 13 send scenarios + 12 verify checks; S13 (payment.failed → 202), V11 (PA.Status=Failed), V12 (OutboxMessages row for PaymentAttemptSucceededV1)
- DW-012 to DW-015 logged in `docs/internal/DEFERRED-WORK-LOG.md` (replay endpoint, refund/dispute handlers, timestamp replay-attack mitigation, Key Vault secret operational task)

---

## Phase 9 — YARP Microservices Architecture (Local) 📅

**Focus:** Create extractable module boundaries and local deployability without changing the
event semantics frozen in Phase 8.

**Why this phase exists:** Phase 9 is the structural proof point. It isolates module boundaries, gateway routing, and local orchestration so the repo can prove service shape before any Azure transport, database split, or workflow expansion is introduced.

### Module Isolation (First Step — Before Extraction)

Before extracting to separate deployables, restructure the monolith into isolated modules:

- **Per-module project structure** — split shared `Application`, `Domain`, `Infrastructure` into per-module libraries:
  - `Orders.Domain`, `Orders.Features`, `Orders.Infrastructure`
  - `Inventory.Domain`, `Inventory.Features`, `Inventory.Infrastructure`
  - `Notifications.Domain`, `Notifications.Features`, `Notifications.Infrastructure`
-  - `Payments.Domain`, `Payments.Features`, `Payments.Infrastructure`
- **API contracts** — `IOrderModuleApi`, `IInventoryModuleApi` interfaces in dedicated `*.API` projects with strongly-typed request/response records. Modules depend ONLY on each other's API — never internal Domain/Features/Infrastructure
- **Per-module DB schemas** — each module owns its own SQL schema (`orders`, `inventory`, `notifications`, `payments`) within the shared database. Phase 11's "split databases" then becomes a connection string change, not a data migration
- **Per-module database migrators** — `IModuleDatabaseMigrator` interface; each module owns its `DbContext` and independent migration history. Startup runs all migrators sequentially

### Webhook Subscription Expansion Rule

Provider dashboard event selection follows backend capability. Phase 8.7 enables only Razorpay/OpenPay `payment.captured` and `payment.failed`, because those are the only event types with implemented handlers, idempotent state transitions, and tests. Future events must not be enabled in provider dashboards until the corresponding domain model, Inbox handler, tenant resolution path, replay behavior, and Azure smoke test exist.

Candidate expansion order:

- **Refund lifecycle** — add `refund.created`, `refund.processed`, and `refund.failed` only after the Payments module owns refund state/schema and idempotent refund handlers.
- **Dispute lifecycle** — add `payment.dispute.created`, `payment.dispute.under_review`, `payment.dispute.action_required`, `payment.dispute.won`, `payment.dispute.lost`, and `payment.dispute.closed` only after a dispute state machine exists.
- **Provider-owned order/invoice/subscription events** — add `order.*`, `invoice.*`, or `subscription.*` only if the product deliberately adopts those Razorpay/OpenPay provider constructs instead of the current internal order-processing model.
- **Operational/provider account events** — keep `payment.downtime.*`, `settlement.*`, `fund_account.*`, `payment_link.*`, and `account.*` disabled unless a concrete operational runbook and handler owner are defined.
- **Module self-registration** — `AddOrdersModule()`, `AddInventoryModule()`, `AddNotificationsModule()`, and `AddPaymentsModule()` chain API registration, infrastructure setup, and assembly scanning. `Program.cs` stays clean as project count grows
- **`AssemblyReference.cs` markers** — static class per project exposing `Assembly` for reliable handler discovery, endpoint registration, and architecture test scanning
- **Bounded-context and subdomain mapping** — before extraction, explicitly model Orders, Inventory, Notifications, and Payments as business contexts with clear responsibilities, upstream/downstream relationships, and published contracts. Payments is elevated because reconciliation and recovery logic must not remain in a shared blob.
- **Architecture tests updated** — `NetArchTest.Rules` (from Phase 5) now enforces inter-module boundaries: modules cannot reference each other's internals, only API contracts
- **Specification pattern** — composable query objects (`OrderByStatusSpec`, `ActiveCustomersSpec`) encapsulating EF Core `Where`/`Include`/`OrderBy` logic; reusable across handlers within a module. Introduced alongside per-module repositories — specifications replace scattered inline LINQ with testable, named query definitions

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LOCAL DEVELOPMENT ENVIRONMENT                     │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    YARP GATEWAY (Port 8080)                    │  │
│  │             http://gateway.localhost:8080                      │  │
│  │                                                                │  │
│  │  Routing Rules:                                                │  │
│  │  • orders.localhost      → Orders API                          │  │
│  │  • inventory.localhost   → Inventory API                       │  │
│  │  • notifications.localhost → Notifications API                 │  │
│  │  • ui.localhost          → UI                                  │  │
│  └────────┬──────────┬──────────┬──────────┬──────────────────────┘  │
│           │          │          │          │                         │
│  ┌────────▼─────┐ ┌──▼─────────┐ ┌────────▼────────┐ ┌──────▼─────┐│
│  │   Orders     │ │ Inventory  │ │ Notifications   │ │     UI     ││
│  │     API      │ │    API     │ │      API        │ │  (MVC App) ││
│  │              │ │            │ │                 │ │            ││
│  │  • Orders    │ │  • Stock   │ │  • Email        │ │  • Views   ││
│  │  • Customers │ │  • Reserve │ │  • SMS          │ │  • Forms   ││
│  │  • Payments  │ │  • Release │ │  • Templates    │ │            ││
│  └──────┬───────┘ └─────┬──────┘ └────────┬────────┘ └────────────┘│
│         │               │                 │                         │
│         └───────────────┼─────────────────┘                         │
│                         │                                            │
│         ┌───────────────▼──────────────────────┐                    │
│         │         Event Bus (in-memory)          │                    │
│         │  OrderCreated → InventoryReserved →    │                    │
│         │  NotificationRequested                 │                    │
│         └───────────────┬──────────────────────┘                    │
│                         │                                            │
│              ┌──────────▼──────────┐                                 │
│              │   SQL Database      │                                 │
│              │   (Shared — temp)   │                                 │
│              └─────────────────────┘                                 │
│                                                                      │
│  Managed by Docker Compose (7 containers)                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Representative Solution Structure (Expanded)

```
XYDataLabs.OrderProcessingSystem.sln
├── XYDataLabs.OrderProcessingSystem.Gateway          (NEW - YARP Proxy)
│   ├── appsettings.json (routing configuration)
│   └── Program.cs
├── XYDataLabs.OrderProcessingSystem.API              (Refactored - Orders only)
│   └── Controllers/
│       ├── OrderController.cs
│       └── CustomerController.cs
├── XYDataLabs.OrderProcessingSystem.InventoryAPI     (NEW - Stock Management)
│   └── Controllers/
│       └── InventoryController.cs
├── XYDataLabs.OrderProcessingSystem.NotificationsAPI (NEW - Notifications)
│   └── Controllers/
│       └── NotificationController.cs
├── XYDataLabs.OrderProcessingSystem.Contracts        (NEW - Shared event schemas + API DTOs)
├── XYDataLabs.OrderProcessingSystem.Orders.API  (NEW - IOrderModuleApi + request/response records)
├── XYDataLabs.OrderProcessingSystem.Inventory.API (NEW - IInventoryModuleApi + contracts)
├── XYDataLabs.OrderProcessingSystem.Notifications.API (NEW - INotificationModuleApi + contracts)
├── XYDataLabs.OrderProcessingSystem.Payments.API (NEW - IPaymentModuleApi + contracts)
├── frontend/apps/web                                 (React SPA)
├── XYDataLabs.OrderProcessingSystem.Orders.Domain     (Split from shared Domain)
├── XYDataLabs.OrderProcessingSystem.Orders.Features   (Split from shared Application)
├── XYDataLabs.OrderProcessingSystem.Orders.Infrastructure (Split from shared Infrastructure)
├── XYDataLabs.OrderProcessingSystem.Inventory.Domain  (NEW)
├── XYDataLabs.OrderProcessingSystem.Inventory.Features (NEW)
├── XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Domain (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Features (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure (NEW)
├── XYDataLabs.OrderProcessingSystem.Payments.Domain (NEW)
├── XYDataLabs.OrderProcessingSystem.Payments.Features (NEW)
├── XYDataLabs.OrderProcessingSystem.Payments.Infrastructure (NEW)
├── frontend/apps/web                                 (React SPA)
├── XYDataLabs.OrderProcessingSystem.SharedKernel     (Shared)
└── XYDataLabs.OpenPayAdapter                         (Shared)
```

### Docker Compose Configuration

```yaml
# docker-compose.microservices.yml
services:
  gateway:
    image: orderprocessing-gateway:dev
    ports:
      - "8080:8080"
    depends_on:
      - orders-api
      - inventory-api
      - notifications-api
      - ui

  orders-api:
    image: orderprocessing-orders-api:dev
    # No exposed ports - accessed via gateway

  inventory-api:
    image: orderprocessing-inventory-api:dev
    # No exposed ports - accessed via gateway

  notifications-api:
    image: orderprocessing-notifications-api:dev
    # No exposed ports - accessed via gateway

  ui:
    image: orderprocessing-ui:dev
    # No exposed ports - accessed via gateway

  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    ports:
      - "1433:1433"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

### Communication Rules (Critical)

| Communication Type | Pattern | Example |
|--------------------|---------|---------|
| **Queries** (read) | Synchronous HTTP | UI → Gateway → Orders API `GET /api/v1/Order/{id}` |
| **Workflows** (write) | Asynchronous Events | `OrderCreated` → Event Bus → Inventory reserves stock |
| **Shared DB** | Per-module schemas | `orders.*`, `inventory.*`, `notifications.*` schemas in shared DB; split to separate DBs in Phase 11 |
| **Module isolation** | Per-module projects | Each module owns Domain/Features/Infrastructure; cross-module communication via API contracts only |

### Characteristics

✅ **Advantages:**
- Service isolation — independent deployment and scaling
- Clean URLs via YARP — no port management (`orders.localhost`, `inventory.localhost`)
- Event-driven workflows — services communicate via events, not direct HTTP calls
- Fault isolation — one service failure doesn't crash entire system
- Production pattern — same as Azure Container Apps architecture
- Service-level observability — per-service metrics and tracing
- Resilient inter-service communication via Polly from day one

⚠️ **Challenges:**
- Increased complexity (7 containers vs 2, including Redis)
- Network latency between services
- Distributed transactions complexity
- Docker Compose orchestration required

### Gateway Cross-Cutting Concerns

- **CORS** — policy per downstream service, configured in YARP
- **Rate limiting** — `System.Threading.RateLimiting` per tenant/client at gateway level
- **Request validation** — reject malformed host/header/path combinations and oversized payloads before they reach downstream services
- **Contributor-friendly ingress parity** — preserve both host-based routes (`orders.localhost`) and path-based fallback routes (`/api`, `/app`) for local and Docker validation so contributors and CI do not depend on hosts-file edits; Aspire later replaces destination resolution, not the single-entry-point contract
- **Authentication boundary** — Phase 9 gateway validates transport-level auth prerequisites, forwards normalized identity context, and never becomes the sole authorization enforcement point; downstream services still validate tokens and policies
- **Request/response logging** — structured audit trail at gateway entry point
- **Request size limits** — prevent oversized payloads reaching downstream services
- **Service discovery + health-aware routing** — YARP destinations resolve through Aspire service discovery in the inner loop and fall back to explicit Docker Compose routes in CI; unhealthy destinations are removed from rotation
- **Protocol support** — HTTP/1.1, HTTP/2, gRPC, and WebSocket pass-through are part of the gateway acceptance bar so the platform does not lock itself into REST-only transport assumptions
- **Safe response caching** — only for explicitly approved idempotent read endpoints, keyed by tenant-aware cache policy to avoid cross-tenant leakage
- **Standardized gateway errors** — gateway-generated failures return ProblemDetails-compatible responses with correlation metadata so edge failures are diagnosable without divergent error shapes
- **Observability** — gateway emits structured logs, metrics, and traces with `traceparent`, `CorrelationId`, `TenantId`, and destination metadata attached

### Deliberate Phase 9 Scope Boundary

Phase 9 uses YARP to prove the internal gateway pattern and developer experience, not to recreate the full external API management plane.

- **Owned by YARP in Phase 9** — local single entry point, internal routing, host/path transforms, tenant-safe caching for approved reads, rate limiting, health-aware destination selection, protocol pass-through, correlation/logging/tracing
- **Deferred to APIM in Phase 10** — subscription keys, public developer portal, consumer products/plans, external analytics, public API policy governance, and internet-facing API onboarding
- **Still owned by downstream services** — domain authorization, business invariants, tenant enforcement, and final JWT/policy validation

### Resilience (Polly v8 Basics)

- `HttpClientFactory` with named/typed clients for inter-service HTTP calls
- **Retry** — exponential backoff for transient HTTP failures
- **Circuit breaker** — prevent cascade failures when a downstream service is unhealthy
- **Timeout** — per-request timeout to avoid hanging calls

### Operational Concerns

- **Graceful shutdown** — `IHostApplicationLifetime` to drain in-flight requests before container stops
- **Structured concurrency** — `Task.WhenAll` for parallel scatter-gather queries through gateway
- **Monorepo CI guardrail** — while services still live in one solution, gateway- or module-only changes must trigger the shared CI workflow and execute the focused gateway regression suite so extraction work cannot bypass validation just because API/UI paths were untouched
- **Testcontainers snapshots** — pre-seeded Docker images for integration tests: build a custom SQL Server image with migrations + seed data baked in, so each test run skips migration/seed overhead; apply when test suite runtime becomes a CI bottleneck across multiple per-module DBs

### Entry Gate To Phase 10

- Orders, Inventory, Notifications, and Payments compile independently.
- API boundaries are enforced by architecture tests.
- Local end-to-end flow works through the YARP gateway.
- The gateway rejects invalid host/header/payload combinations, removes unhealthy destinations from routing, and returns standardized ProblemDetails-style failures for gateway-generated errors.
- At least one traced request path demonstrates tenant-aware routing plus correlation propagation from gateway to downstream services without losing `traceparent` or domain correlation metadata.
- One request flowing Orders → Inventory → Notifications produces one trace in Application Insights with all module spans present and the envelope `CorrelationId` attached to each span.
- Event envelope, handler signatures, and retry semantics are identical to Phase 8 — no drift during extraction.

### Aspire-Lite — Local Orchestration Track (Parallel)

.NET Aspire `AppHost` is introduced **alongside** Docker Compose in Phase 9, not deferred to Phase 13. Both orchestrators target the same containerized service set:

- **Aspire AppHost** — `XYDataLabs.OrderProcessingSystem.AppHost` project added; `builder.AddProject<Orders>()`, `builder.AddProject<Inventory>()`, `builder.AddSqlServer()`, `builder.AddRedis()`
- **Service discovery** — Aspire-managed; eliminates hardcoded URLs in inter-service `HttpClient` registrations
- **Aspire dashboard** — used as the primary local observability surface; complements (does not replace) App Insights for cloud environments
- **Docker Compose retained** — covers strict CI scenarios, the Playwright matrix bundle, and contributors who do not yet have the Aspire workload installed
- **Phase 13 then deepens** — `DistributedApplicationTestingBuilder` integration tests, Aspire manifest → ACA deployment, advanced resource composition

This ordering matches modern cloud-native developer experience expectations: Aspire is the inner-loop orchestrator the moment services exist, not an end-state luxury.

### Cross-Cutting Modernization (Aligned with .NET 10 Aspire Blueprint)

Reviewed against the canonical Microsoft `dotnet-backend-blueprint-v-10` reference template (Aspire 13 + ACA + Keycloak + PostgreSQL). The following tactical refinements are adopted as Phase 9 deliverables — they support the microservice extraction without altering domain behaviour:

- **`XYDataLabs.OrderProcessingSystem.ServiceDefaults` project** — new shared project referenced by every service host. Houses the canonical extension chain `AddServiceDefaults()` → `ConfigureOpenTelemetry()` + `AddDefaultHealthChecks()` + `AddServiceDiscovery()` + `ConfigureHttpClientDefaults(http => http.AddStandardResilienceHandler())`. Today these concerns are split between `SharedKernel` and individual `Program.cs` files; consolidating them is a prerequisite for clean per-service composition. Reinforces ADR-012 (OpenTelemetry dual export).
- **`MapDefaultEndpoints()` extension** — standardizes `/health/ready` (full readiness, gates traffic) and `/health/alive` (liveness only) across every service host. Aligns with ADR-015 (deployment readiness probes) and removes duplicated health endpoint registration in each service.
- **`IConfigureNamedOptions<JwtBearerOptions>` setup pattern** — replaces inline JWT wiring in `Program.cs` with a dedicated `JwtBearerOptionsSetup` registered via `ConfigureOptions<>()`. Required mechanism for Phase 9.5 (Keycloak portability) and not yet present in the current runtime wiring; it will add a second JWT scheme via `AddPolicyScheme`.
- **`IExceptionHandler` + `AddProblemDetails` + `UseExceptionHandler`** — confirm or migrate to the .NET 8+ idiomatic exception pipeline producing RFC 7807 ProblemDetails. This is the contract provider webhooks (Phase 8.7) and external partners expect; it must be in place before microservices accept inbound traffic from a gateway.
- **EF Core `UseAsyncSeeding` for reference data** — EF 9 idiomatic seeding hook on `DbContextOptionsBuilder`. Replaces ad-hoc startup seed code; particularly useful before Phase 11.5's PostgreSQL pilot which re-seeds the Notifications module on a different RDBMS provider.

**Deliberately not adopted from the blueprint:** vertical-slice replacement of Clean Architecture (ADR-011 enforces our domain boundaries), Keycloak as production IdP (Entra ID + Managed Identity remain authoritative — Phase 9.5 only proves portability), PostgreSQL as primary RDBMS (Phase 11.5 pilots one module only), single-workflow CI/CD (our split workflow is intentional per `architect-patterns.md`).

### Outcome

Module-isolated, locally deployable services with proven API boundaries, a first-class Payments module, dual orchestration (Docker Compose for CI + Aspire AppHost for inner-loop), a shared `ServiceDefaults` project, and unchanged event semantics ready for the Phase 10 transport swap.

---

## Phase 9.5 — Cloud-Portable Identity Showcase (Keycloak Local) ✅

**Focus:** Demonstrate identity-provider portability by running Keycloak locally as a drop-in OIDC provider, validating that JWT auth works against any compliant IdP — not only Entra ID.

**Why this phase is separate:** Phase 9.5 is intentionally narrow. It proves the auth pipeline is IdP-agnostic without changing the production identity model, and it depends on the local Docker topology already proven in Phase 9.

### Why This Phase Is Required

Enterprise architecture must avoid lock-in to a single identity provider. Phase 10 wires Entra ID + JWT for cloud deployment, but the **same `JwtBearerOptions` configuration must accept tokens from Keycloak with only `Authority` and `Audience` changes**. This phase proves that portability with a runnable local demo.

Keycloak remains a local-only Phase 9.5 portability proof for learning and validation; Azure production must continue to use Microsoft Entra ID, and any Azure-side Keycloak parity or migration testing should remain deferred work rather than a numbered roadmap phase.

### Key Deliverables

- **Local Keycloak container** — added to Docker Compose `dev` profile (port 8080); pre-seeded realm `orderprocessing-dev` with three test tenants and roles (`admin`, `operator`, `customer`)
- **OIDC discovery configuration** — `JwtBearerOptions.Authority = http://keycloak:8080/realms/orderprocessing-dev`; same `JwtBearerHandler`, no custom token validation code
- **Multi-IdP runtime selection** — `AuthenticationScheme` per IdP (`KeycloakBearer`, `EntraBearer`); policy-based scheme selection via `AddPolicyScheme` for environment-aware routing
- **Claims transformation parity** — `ITenantClaimsTransformation` extracts `tenantId` from either Keycloak `realm_access.attributes.tenantId` or Entra `extension_TenantId` claim; downstream code sees the same `ClaimsPrincipal` shape
- **Frontend integration** — React SPA's auth provider configured to use Keycloak in local docker, Entra in cloud; same `oidc-client-ts` library, only the discovery URL changes
- **Documentation deliverable** — `docs/architecture/identity-portability.md` proving the configuration delta between Entra ID and Keycloak is < 10 lines

### Phase 9.5 Status Table

| Area | Status | Next Step | Phase |
|---|---|---|---|
| Local Keycloak portability proof | Runtime verified | Run the local HTTP and Docker Dev HTTP flows against the seeded realm | Phase 9.5 |
| JWT / OIDC scheme switching | Runtime verified | Confirm bearer validation against the local issuer in live runs | Phase 9.5 |
| Claims transformation parity | Runtime verified | Verify the tenant claim shape end to end during browser and API runs | Phase 9.5 |
| React auth-provider switch | Runtime verified | Confirm the SPA requests a token from the local issuer in the live flow | Phase 9.5 |
| Identity portability documentation | Complete | Keep the portability delta documented and reviewable | Phase 9.5 |
| Cloud identity rollout | Not part of Phase 9.5 | Use Entra ID + JWT in Phase 10 | Phase 10 |
| Keycloak as managed cloud IdP | Explicitly deferred | Do not move Keycloak into Azure production | Phase 10+ / deferred |
| Federation between Keycloak and Entra | Explicitly deferred | Revisit only if a later business need appears | Phase 12+ / deferred |

### What This Phase Does NOT Do

- Does **not** replace Entra ID in cloud environments — Entra remains the authoritative IdP for `staging` and `prod`
- Does **not** introduce Keycloak as a managed Azure service — Keycloak runs locally only; cloud deployments continue with Entra ID
- Does **not** federate Keycloak ↔ Entra — federation is a Phase 12+ topic if business requirements emerge

### Builds On

- Phase 9 (Docker Compose infrastructure for local Keycloak container)
- Phase 10 (JWT validation pipeline already in place — this phase swaps the IdP, not the auth model)

### Outcome

Identity-provider portability is now wired into the repo with a runnable local demo path. The team has the Keycloak flow staged for live verification without compromising the production Entra ID strategy. The architecture's auth pipeline is now positioned to be demonstrably IdP-agnostic once the local and Docker Dev HTTP runs are completed.

---

## Phase 10 — Azure Container Apps Migration 📅

**Focus:** Complete real independently deployable services, durable Azure transport, governed DLQ operations, portable OIDC authorization, and evidence-backed ACA delivery without changing the contracts frozen in Phase 8.

**Why this phase is separate:** Phase 10 is the service-migration, cloud-transport, and delivery-safety phase. It exists only after the local module and identity proofs are stable, because real workload extraction, Azure resources, failure drills, and security wiring must be proven together.

> The diagram below is the broader Azure target spanning Phases 10 and 12. The Phase 10 completion boundary is ACA/ACR, YARP, Service Bus Standard with Entra/RBAC, real service consumers, DLQ Functions, Key Vault, SQL/Redis, and observability. APIM/private ingress, VNet/private endpoints, Service Bus Premium/Private Link, Blob/Event Grid, SQL managed identity, and Front Door/WAF are formal Phase 12 deferrals governed by ADR-025.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE CLOUD                                  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │           Azure Container Apps Environment                      │ │
│  │                                                                 │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │              YARP Gateway Container App                   │  │ │
│  │  │         (Internal - JWT validation + routing)             │  │ │
│  │  └────────┬──────────┬──────────┬──────────┬────────────────┘  │ │
│  │           │          │          │          │                    │ │
│  │  ┌────────▼─────┐ ┌──▼─────────┐ ┌────────▼────────┐ ┌───▼───┐│ │
│  │  │  Orders App  │ │Inventory   │ │ Notifications   │ │ UI    ││ │
│  │  │  (Internal)  │ │   App      │ │      App        │ │  App  ││ │
│  │  │              │ │(Internal)  │ │   (Internal)    │ │(Public)│ │
│  │  └──────┬───────┘ └─────┬──────┘ └───────┬─────────┘ └───────┘│ │
│  │         │               │                │                      │ │
│  │         └───────────────┼────────────────┘                      │ │
│  │                         │                                       │ │
│  │           ┌─────────────▼─────────────────┐                     │ │
│  │           │  Azure Service Bus             │                     │ │
│  │           │  (Topics + Subscriptions)      │                     │ │
│  │           │  Replaces in-memory event bus  │                     │ │
│  │           └───────────────────────────────┘                     │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure SQL Database  │         │  Application         │          │
│  │  (Private Endpoint)  │         │  Insights + OTel     │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Container     │         │  Azure Key Vault     │          │
│  │  Registry (ACR)      │         │  (Private Endpoint)  │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Entra ID      │         │  Azure Monitor       │          │
│  │  (JWT + OIDC)        │         │  (Logging & Metrics) │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Cache for     │         │  Azure API           │          │
│  │  Redis (Private EP)  │         │  Management (APIM)   │          │
│  └──────────────────────┘         │  (Public Gateway)    │          │
│                                   └──────────────────────┘          │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Functions     │         │  Azure Event Grid    │          │
│  │  (DLQ reprocessor)   │         │  (Platform events)   │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐                                            │
│  │  Azure Blob Storage  │                                            │
│  │  (Order attachments) │                                            │
│  └──────────────────────┘                                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- Deploy real Orders, Payments, Inventory, Notifications, Gateway, UI, worker, and Functions workloads to **Azure Container Apps / Azure Functions** using immutable artifacts
- **Gateway deployment path** — YARP is packaged and deployed as a first-class workload with its own container image, health probes, configuration surface, and deployment step; it is not piggybacked onto the Orders API or UI artifact
- **Azure Container Registry (ACR)** — build and push container images. Enterprise target: persistent platform/foundation ACR outside the environment app resource group, with a stable pull identity and one-time `AcrPull` assignment owned by platform bootstrap rather than normal app deployment
- **Azure Service Bus** — replace the in-memory event bus behind `IEventPublisher` with committed outbox publication, durable topics/subscriptions, real Inventory/Notifications consumers, and inbox/idempotency; handlers and envelopes remain unchanged
- **Azure Functions** — deploy separate central DLQ intake and guarded approval/replay paths using the isolated worker model; broker-level smoke utilities do not count as deployed Function proof
- **Azure Cache for Redis** — managed Redis replacing local container; used for distributed cache and session state
- **Observability** — App Insights + OpenTelemetry distributed tracing across all services; `traceparent`, `CorrelationId`, `CausationId`, `TenantId`, and `MessageId` propagate through every message so dead-lettered events can be traced back to the originating order and tenant
- **Identity and secrets** — Entra ID JWT authorization, managed identity/RBAC for Service Bus, and Key Vault for provider and bootstrap secrets
- **Delivery safety** — immutable commit-SHA images and Function packages, expand/contract migrations, retained healthy revisions, and an evidence-backed rollback path
- **Cost governance** — workload-appropriate minimum replicas and scaling, retention controls, and Azure Budget alerts per resource group
- **Bicep-only topology** — Azure infrastructure remains Bicep-authored end to end. Service Bus topology is declared in a dedicated `servicebus.bicep` module with per-environment parameters; no portal drift and no Terraform split.
- **Formal Phase 12 deferrals** — APIM/private YARP ingress, VNet/private endpoints, Service Bus Premium/Private Link, Blob attachments/Event Grid, SQL managed identity, and Front Door/WAF remain roadmap requirements but are not Phase 10 exit criteria

### Phase 10.1 - Local Baseline Reconciliation ✅ COMPLETE

Phase 10.1 is the local-first proof that the Phase 10 toolchain, Docker topology, and validation workflow are ready for the Azure transport slice.

Completed proof points:

- Canonical developer-machine tooling is documented and gated in [Phase 10 Tool Prerequisites](docs/guides/development/phase10-tool-prerequisites.md).
- Local setup execution is broken into the explicit `00` to `05` ladder in [Phase 10 Implementation Checklist](docs/internal/phase10-implementation-checklist.md).
- Repository validation, Docker infrastructure validation, integration coverage, and Docker E2E validation all have explicit evidence hooks.
- The local runtime contract is pinned to Docker Compose as the canonical baseline, with Aspire left optional.
- The local identity path is documented as Keycloak for portable debugging, while Azure remains Entra ID for cloud validation.
- The local payment matrix now has a deterministic local-provider path for TenantC/OpenPay so local HTTP validation does not depend on the live OpenPay sandbox.
- The Phase 10 artifact and log layout is documented so evidence can be traced without relying on ad hoc console history.

### Phase 10 Status Table

> Scope note: the refinements below are Phase 10 or later only. Earlier phase decisions stay frozen unless a separate review explicitly reopens them.

| Area | Status | Meaning | Next Step |
|---|---|---|---|
| Local baseline reconciliation | Complete | Local tooling, execution order, artifact layout, and Docker validation lanes are explicitly documented | Keep the Stage 0-6 gates green during implementation |
| Real service migration | Required / in progress | Existing Phase 10 service hosts include compatibility stubs and Payments is not yet a complete independently hosted workload | Complete slice 10.2 and prove authoritative SQL behavior |
| Durable transport and consumers | Required / in progress | Service Bus topology and adapters exist; real module consumers and end-to-end committed effects remain required | Complete slice 10.3 |
| DLQ and deployed Functions | Required / in progress | Function host/scaffolds exist; separate intake/replay ownership, package deployment, and invocation proof remain required | Complete slice 10.4 |
| Cloud hosting outcome | Required / in progress | ACA/ACR is the Phase 10 hosting target | Deploy all real workloads with immutable artifacts and rollback proof |
| Phase 10 ingress | Required / in progress | YARP is the supported ingress for the Phase 10 proof | Enforce Entra JWT and tenant policies through YARP |
| Identity and transport auth | Required / in progress | Entra ID + JWT and Service Bus managed identity/RBAC are the Azure lanes; Keycloak remains local | Complete slice 10.5 and remove Azure Service Bus SAS settings |
| Secrets | Required / in progress | Key Vault owns provider and bootstrap secrets | Verify secret resolution without committed/runtime plaintext |
| Non-functional proof | Required / pending | Failure drills, lower-environment performance, SLI evidence, and rollback remain unproven | Complete slice 10.6 |
| Acceptance evidence | Required / pending | Historical scaffolding/smoke evidence is not the final completion packet | Complete slice 10.7 against one immutable commit |
| APIM/private networking/Blob/Event Grid/SQL MI/Front Door | Deferred to Phase 12 | These remain required roadmap outcomes, not Phase 10 exit criteria | Track through ADR-025 and DW-019 through DW-022 |
| SharedContracts | Deferred / candidate for Phase 10 | Introduce only if Phase 10 transport wiring proves a shared schema package is needed across services | Keep service-local contracts until a real duplication problem appears |
| Phase 9.5 portability proof | Deferred / not Phase 10 | Keep Keycloak local-only in Phase 9.5 | No Azure-side Keycloak parity in this phase |
| Database-per-service split | Not Phase 10 | Database-per-service belongs to Phase 11 | Move this to Phase 11 |
| Aspire deepening / distributed app tests | Not Phase 10 | Distributed app tests and manifest evaluation belong later | Move this to Phase 13 |

### Platform ACR And Image Lifecycle Plan

The normal Phase 10 app deployment should not need to create Azure RBAC assignments once the platform foundation is in place. Azure requires a trusted identity somewhere for `roleAssignments/write`, so the final design moves that responsibility out of the app deployment path.

| Concern | Owner | Phase 10 target |
|---|---|---|
| Platform ACR | Platform foundation | Persistent registry outside `rg-orderprocessing-<env>` |
| Pull identity | Platform foundation | Stable user-assigned managed identity shared by Container Apps |
| `AcrPull` assignment | Platform foundation | Assigned once to the pull identity; not recreated by normal app deploy |
| App environment RG | Phase 10 deploy wrapper | Recreated freely with `cleanupInfra=true` / redeploy |
| ACR image cleanup | Retention cleanup workflow | Scheduled tag pruning that preserves active revision images and release tags |

Implementation order:

1. Create the platform/foundation resource group.
2. Create ACR and the stable pull identity once.
3. Assign `AcrPull` to the pull identity once.
4. Change Phase 10 Bicep and workflow inputs to reference existing ACR and pull identity values.
5. Remove ACR role-assignment creation from normal Phase 10 app deployment.
6. Keep scheduled ACR cleanup separate from app resource-group cleanup.

This keeps app environment cleanup simple while preserving image history, avoiding repeated manual RG-level permission grants, and keeping normal deploy identity scope smaller.

### Phase 10 Done / Pending Checklist

- Done:
  - Phase 10.1 local baseline reconciliation
  - Function App infrastructure module exists: `infra/modules/functions.bicep`
  - Function identity output is wired into Phase 10 Key Vault access plumbing
  - Local Azure Functions worker scaffold exists with startup validation and an initial DLQ intake trigger
  - Service Bus transport smoke proof is documented, but it does not yet prove deployed Azure Functions behavior
- Pending:
  - 10.2 real Orders, Payments, Inventory, and Notifications service migration
  - 10.3 outbox-to-Service-Bus publication, real consumers, inbox/idempotency, and restart/duplicate proof
  - 10.4 separated DLQ intake/quarantine/approval/replay, Function deployment artifact, and invocation smoke
  - 10.5 Entra ID JWT authorization, Service Bus managed identity/RBAC, and Key Vault secret resolution
  - 10.6 NFR, observability, failure-drill, and rollback proof
  - 10.7 local/Docker/CI/Azure acceptance and evidence closeout
- Not in Phase 10:
  - APIM/private YARP ingress, VNet/private endpoints, Service Bus Premium/Private Link, Blob/Event Grid, SQL managed identity, and Front Door/WAF move to Phase 12 under ADR-025
  - Keycloak portability proof stays in Phase 9.5 / deferred
  - Database-per-service split stays in Phase 11
  - Aspire deepening / distributed app tests stay in Phase 13

### Security

- **Identity:** Azure Entra ID (Azure AD) for authentication
- **JWT auth** — Phase 10 validates Entra ID tokens at YARP and service policies and propagates identity downstream. APIM policy validation is added with the Phase 12 private edge.
- **Managed Identity** — Phase 10 uses managed identity for Service Bus and Key Vault; SQL runtime managed identity is Phase 12 work under DW-021.
- **OIDC** — GitHub Actions deploys via federated credentials (existing pattern)
- **WAF / Network Security** — Azure Front Door/WAF, APIM private ingress, ACA VNet integration, private endpoints, and private DNS are Phase 12 work under ADR-025.

### Messaging Backbone

- **Azure Service Bus** replaces the in-memory event dispatcher from Phase 8 without changing envelope or handler contracts
- Topology is authored only in `servicebus.bicep` with per-environment settings for topics, subscriptions, forwarding, TTL, `maxDeliveryCount`, and `deadLetteringOnMessageExpiration`
- Topics: `order-events`, `inventory-events`, `notification-events`
- Each service subscribes to relevant topics
- DLQ forwarding to central intake is enabled where topology supports `forwardDeadLetteredMessagesTo`

### Dead-Letter Queue (DLQ) Handling

- **Expiration handling is explicit** — `deadLetteringOnMessageExpiration = true` is set on every queue and subscription
- **Delivery count is explicit** — `maxDeliveryCount` is parameterised per environment and justified in Bicep comments; no default is accepted silently
- **Application rejections are inspectable** — every `DeadLetterMessageAsync` call sets both `DeadLetterReason` and `DeadLetterErrorDescription`
- **Central intake** — Azure Function consumes the forwarded DLQ stream, maps it to `DeliveryFailureCategory`, and decides whether the message is transient, poison, expired, or rejected. The Function App host is provisioned by infrastructure today; the actual isolated worker project and trigger code are still a Phase 10 implementation item.
- **Poison quarantine** — poison payloads are quarantined for manual review and are never bulk-replayed automatically
- **Operational alerts** — Azure Monitor alerts fire on central DLQ depth and oldest DLQ message age, not just active queue depth
- **Failure drill policy** — subscription failure, DLQ routing, alert firing, operator inspection, transient replay, poison quarantine, and business-flow recovery must all be demonstrated before sign-off

### Advanced Deployment Patterns

- **Blue-green deployments** — zero-downtime with ACA revisions; switch traffic after health check passes
- **Canary releases** — gradual traffic shifting (e.g. 10% → 50% → 100%) with automatic rollback on error-rate spike

> **Operational Detail:** See [docs/guides/deployment/aca-migration-plan.md](./docs/guides/deployment/aca-migration-plan.md) for the 13-phase operational runbook covering governance, identity hardening, ACR setup, canary deployments, and decommissioning.

### Outcome

Secure, scalable cloud-native microservices with durable Azure transport, controlled and observable DLQ operations, Bicep-governed topology, and ingress/security enabled only after transport recovery has been proven.

---

## Phase 11 — Data Ownership & Service Autonomy 📅

**Focus:** True microservice boundaries — each service owns its data.

**Why this phase is separate:** Phase 11 starts only after transport is stable because data ownership, per-service migrations, and eventual consistency are only meaningful once the services already exist as separate operational units.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SERVICE DATA OWNERSHIP                            │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │   Orders API     │  │  Inventory API   │  │ Notifications API│  │
│  │                  │  │                  │  │                  │  │
│  │  Own entities:   │  │  Own entities:   │  │  Own entities:   │  │
│  │  • Order         │  │  • StockItem     │  │  • Notification  │  │
│  │  • Customer      │  │  • Reservation   │  │  • Template      │  │
│  │  • Payment       │  │  • StockMovement │  │  • DeliveryLog   │  │
│  │  Own migrations  │  │  Own migrations  │  │  Own migrations  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│  ┌────────▼─────────┐  ┌───────▼──────────┐  ┌────────▼─────────┐  │
│  │   Orders DB      │  │  Inventory DB    │  │ Notifications DB │  │
│  │   (SQL Server)   │  │  (SQL Server)    │  │  (SQL Server)    │  │
│  └────────┬─────────┘  └───────┬──────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│           └─────────────────────┼──────────────────────┘            │
│                                 │                                    │
│              ┌──────────────────▼──────────────────┐                │
│              │       Azure Service Bus              │                │
│              │   (eventual consistency via events)   │                │
│              │                                      │                │
│              │  No cross-service joins allowed!      │                │
│              │  Data sync = events only              │                │
│              └──────────────────────────────────────┘                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- **Database per service** — Orders DB, Inventory DB, Notifications DB
- Remove shared `DbContext` — each service owns its entities and EF migrations
- Shared projects (`Application`, `Domain`, `Infrastructure`) split into per-service libraries
- **Eventual consistency** — no cross-service joins; data synchronization via events only
- Each service maintains its own read-optimized projections of data it needs from other services
- **`XYDataLabs.OrderProcessingSystem.DurableFunctions`** — separate Azure Functions project (isolated process model) hosting Durable Function orchestrations for cross-service workflows that require compensating actions (see Distributed Workflow Strategy below)

### Phase 11 Status Table

| Area | Status | Next Step | Phase |
|---|---|---|---|
| Database per service | Planned | Split Orders, Inventory, and Notifications into independent stores | Phase 11 |
| Shared DbContext removal | Planned | Remove shared persistence coupling between services | Phase 11 |
| Per-service migrations | Planned | Give each service its own EF Core migration pipeline | Phase 11 |
| Eventual consistency | Planned | Use events and local projections instead of cross-service joins | Phase 11 |
| Durable Functions workflow support | Planned | Add orchestration for compensating workflows that need it | Phase 11 |
| Notifications PostgreSQL pilot | Not Phase 11 core | Move the portability showcase into Phase 11.5 | Phase 11.5 |
| Azure transport / ACA / APIM | Not Phase 11 core | Keep those as Phase 10 platform work | Phase 10 |
| Aspire deepening / distributed testing | Not Phase 11 core | Keep that for Phase 13 | Phase 13 |

### Rules

- No direct database queries across service boundaries
- If Orders needs inventory status, it subscribes to `InventoryUpdated` events and maintains a local projection
- Cross-service reads use lightweight HTTP queries (via gateway) for real-time needs

### Distributed Workflow Strategy

- **Default: Choreography** — services react to events independently (e.g. `OrderCreated` → Inventory reserves → Notification sends)
- **Escalation: Saga / Process Manager** — introduce only when a workflow requires compensating actions across 3+ services (e.g. order fulfilment with payment rollback)
- **Decision criteria:** If a failure in step N requires undoing steps 1…N-1, use a Saga; otherwise choreography is sufficient

### Durable Functions Project (`XYDataLabs.OrderProcessingSystem.DurableFunctions`)

- **Separate project** — Azure Functions (isolated process model) with `Microsoft.Azure.Functions.Worker.Extensions.DurableTask`
- **Orchestrator functions** — `OrderFulfilmentOrchestrator` (payment → inventory → shipping → notification with compensating rollback)
- **Activity functions** — each step is an activity: `ReserveInventoryActivity`, `ProcessPaymentActivity`, `SendNotificationActivity`, `CompensatePaymentActivity`
- **Sub-orchestrations** — complex sub-workflows (e.g. multi-item inventory reservation) composed within parent orchestrators
- **Fan-out/fan-in** — parallel activity execution (e.g. validate all order line items concurrently, await all before proceeding)
- **Durable timers + human interaction** — approval workflows with configurable timeout and escalation
- **Service Bus triggers** — orchestrations started by Service Bus messages (e.g. `OrderCreated` event triggers `OrderFulfilmentOrchestrator`)
- **Observability** — Durable Functions execution history + OpenTelemetry correlation; orchestration status queryable via built-in HTTP API
- **Deployment** — separate ACA container app with its own CI/CD pipeline; scale-to-zero when idle

### Database Migration Strategy

- **EF Core bundles** — `dotnet ef migrations bundle` produces a self-contained executable for each service DB
- **Init containers** — ACA init container runs the migration bundle before the app container starts
- **Rollback** — migration bundles support `--target` for reverting to a specific migration; never use destructive migrations in production

### Performance Conventions

- **`AsNoTracking()`** on all EF Core read queries — enforced as team convention; avoids change-tracker overhead on write-side validation/lookup queries
- **Indexing review** per service DB — cover foreign keys, `TenantId` filters, and common `WHERE` clause columns; use EF Core query logging or SQL Profiler to identify slow queries
- **EF Core 8 `SqlQuery<T>`** for complex/reporting queries — raw SQL returning unmapped DTOs with zero change-tracking overhead; parameterized by default (no SQL injection risk); eliminates need for Dapper while keeping a single `DbContext` connection pool. Use `EF.CompileAsyncQuery` for true hot paths.
- **Bulk operations** — use `EFCore.BulkExtensions` or `ExecuteSqlInterpolated` for batch import/export scenarios (e.g. bulk order ingestion); standard single-entity writes remain via EF Core

### Outcome

Independent, fully decoupled services with clear data ownership, Durable Functions for orchestrated workflows with compensating actions, automated database migrations, and codified performance conventions.

---

## Phase 11.5 — Polyglot Persistence Showcase (PostgreSQL Module) 📅

**Focus:** Demonstrate database-engine portability by migrating one module's persistence layer to PostgreSQL while the rest of the system continues on Azure SQL. Proves the EF Core abstraction holds against a different RDBMS without leaking provider details into Domain or Features.

**Why this phase is separate:** Phase 11.5 is a narrow portability showcase. It is intentionally not a platform rewrite; it proves one isolated module can move to PostgreSQL while Azure SQL remains the default for the rest of the system.

### Why This Phase Is Required

- **Cloud-portability proof** — Azure SQL is excellent but expensive at scale; PostgreSQL on Azure Database for PostgreSQL Flexible Server (or AWS RDS, GCP Cloud SQL) is a common cost-driven alternative
- **Open-source alignment** — PostgreSQL is the dominant OSS RDBMS in modern .NET cloud-native stacks (Julio Casal stack, Aspire integrations, EF Core first-class provider)
- **Skill demonstration** — proves the team can operate heterogeneous persistence without rewriting business logic

### Selected Module: Notifications

`Notifications` is chosen because:
- Its data shape (event log, template store, delivery audit) is naturally PostgreSQL-friendly (JSONB for flexible delivery metadata, full-text search on template content)
- It has the lowest cross-module read coupling — Phase 11 already established it owns its own data
- Failure of this experiment does not affect Orders or Payments revenue paths

### Key Deliverables

- **`Npgsql.EntityFrameworkCore.PostgreSQL` provider** — replaces `Microsoft.EntityFrameworkCore.SqlServer` in the Notifications module's Infrastructure project only
- **Provider-agnostic EF Core abstractions enforced** — architecture test verifies `Notifications.Domain` and `Notifications.Features` reference no provider-specific types (no `SqlServer.*`, no `Npgsql.*` leaks above the Infrastructure layer)
- **JSONB column for delivery metadata** — `NotificationDeliveryLog.ProviderResponse` typed as `JsonDocument` with `HasColumnType("jsonb")` mapping; demonstrates leveraging native PG features without breaking the abstraction
- **PG migrations** — separate `Notifications.Infrastructure.Migrations.Postgres` migration history; existing SQL Server migrations remain untouched
- **Local Docker** — `postgres:16-alpine` added to Docker Compose alongside `mcr.microsoft.com/mssql/server`
- **Cloud target** — Azure Database for PostgreSQL Flexible Server in `staging` and `prod` (separate Bicep module, private endpoint, managed identity auth)
- **Connection string strategy** — same `IConfiguration` key, different connection string per provider; `ServiceCollectionExtensions.AddNotificationsModule()` selects provider via `appsettings`
- **Backup / DR alignment** — PG backup retention parity with Azure SQL configured; restore runbook documented

### Phase 11.5 Status Table

| Area | Status | Next Step | Phase |
|---|---|---|---|
| Notifications PostgreSQL pilot | Planned | Move only Notifications to PostgreSQL end to end | Phase 11.5 |
| EF Core provider swap | Planned | Keep EF Core; change only the provider in Notifications Infrastructure | Phase 11.5 |
| JSONB / PG-native features | Planned | Use native PostgreSQL features where they help the module | Phase 11.5 |
| Separate PG migrations | Planned | Maintain an independent migration history for PostgreSQL | Phase 11.5 |
| Local Docker PG support | Planned | Add PostgreSQL to local Docker Compose for the pilot | Phase 11.5 |
| Azure Flexible Server target | Planned | Use Azure Database for PostgreSQL Flexible Server in cloud environments | Phase 11.5 |
| Platform-wide PostgreSQL replacement | Not allowed | Keep Azure SQL as the default platform store for other modules | Deferred |
| Cross-database transactions | Not part of Phase 11.5 | Keep using Outbox/Inbox instead | Phase 8 / deferred |

### What This Phase Does NOT Do

- Does **not** migrate Orders, Inventory, or Payments — those remain on Azure SQL (revenue-critical, established operational baseline)
- Does **not** introduce a different ORM — EF Core remains the single data-access library; only the provider changes
- Does **not** attempt cross-database transactions — the Outbox/Inbox pattern (Phase 8) already removes that need

### Builds On

- Phase 11 (database-per-service ownership — required precondition; cannot mix providers in a shared schema)
- Phase 6/8 (EF Core abstractions, Outbox pattern, eventual consistency model)

### Outcome

Provider-portability proven with one module running PostgreSQL end-to-end (local Docker → Azure Flexible Server). Architecture tests enforce that the abstraction remains clean. The team has operational PostgreSQL experience (replication, vacuum, JSONB indexing, role/grant model) — the dominant OSS RDBMS skill set in modern .NET cloud-native engineering.

---

## Phase 12 — Platform Engineering & DevOps 📅

**Focus:** Operational excellence — configuration, observability dashboards, and advanced resilience.

**Why this phase is separate:** Phase 12 is about operating the platform well, not expanding the core business model. Configuration, secrets, observability, CI/CD, and resilience conventions matter only after service ownership and cloud transport are already in place.

### Key Deliverables

- **Private cloud edge** — APIM Standard v2 or a then-approved VNet-capable tier fronts private YARP ingress; Azure Front Door/WAF provides the external edge when justified by the production threat model
- **Private networking** — VNet integration, private DNS, and private endpoints for SQL, Key Vault, Redis, Blob Storage, and other supported data services
- **Private messaging** — move Service Bus from the Phase 10 Standard/RBAC baseline to Premium with Private Link as part of the tested private-network topology
- **Order attachments and event routing** — Blob Storage attachment lifecycle and Event Grid triggers land before Document Intelligence enrichment
- **SQL managed identity** — replace Phase 10 Key Vault bootstrap/runtime database credentials with workload managed identity after migration ownership and service boundaries stabilize
- **Central configuration** — Azure App Configuration for feature flags and shared settings
- **Secrets management** — Azure Key Vault with RBAC (migrate from access policies)
- **Observability dashboards** — Azure Monitor workbooks with per-service metrics, SLIs/SLOs
- **Distributed tracing** — full correlation across Service Bus messages and HTTP requests
- **Per-service CI/CD pipelines** — independent build/test/deploy per service
- **Health check gates** — deployment blocked if `/health/ready` fails post-deploy
- **Advanced Polly** — bulkhead isolation + fallback policies (retry + circuit breaker already in Phase 9)
- **Azure AI Document Intelligence** — extract structured data from uploaded invoices/receipts in Blob Storage; Event Grid triggers Function → Document Intelligence API → enriches order metadata. Demonstrates Azure Cognitive Services integration without over-engineering.
- **DR / Business Continuity** — documented RTO/RPO targets per service; Azure SQL geo-replication strategy; Cosmos DB multi-region (mention only); backup/restore runbook
- **Performance / Load Testing** — Azure Load Testing or k6 for baseline performance; SLO validation under realistic load before production
- **.NET 10 upgrade** — treat the move from .NET 8 LTS to .NET 10 LTS as a later runtime upgrade window, not a Phase 10 deliverable. When the window opens, the steps are: update `global.json` TFM, bump package versions in `Directory.Packages.props`, verify Testcontainers + NetArchTest compatibility, update Dockerfiles and CI pipeline `dotnet-version`. No architecture changes are required — this is a runtime upgrade only. .NET 9 (STS, EOL May 2026) is skipped; .NET 8 LTS support runs to November 2026, so the repo can keep shipping on .NET 8 until the later platform window is intentionally opened.

### Outcome

Scalable, manageable production platform with enterprise-grade operations, advanced resilience, AI-powered document processing, DR planning, load-tested SLOs, and current LTS runtime.

---

## Phase 13 — Aspire & Developer Experience 📅

**Focus:** Developer inner-loop experience deepening, on top of the Aspire-Lite track introduced in Phase 9.

**Why this phase is separate:** Phase 13 deepens the orchestration and test harness after the service graph is already stable. It is about proving the live Aspire graph, distributed tests, and deployment packaging choices, not about adding new business capabilities.

### Phase 9 Carry-Forward Notes

Phase 9 establishes the local orchestration seam, but a few Aspire-specific refinements are intentionally deferred so they can be revisited when package availability and the cloud maturity track are stronger:

- **Provider-based Aspire resources** — replace the base container primitives with the dedicated Aspire SQL/Redis resource packages when restore is available in the environment, or when the team standardizes on a package set that supports them cleanly.
- **Distributed application testing** — migrate the current AppHost proof toward `DistributedApplicationTestingBuilder` once the inner-loop orchestration has stabilized and the test harness can consume the live graph reliably.
- **Publish/manifest evaluation** — compare the AppHost resource graph with Aspire-generated manifest output and `azd` flows only when there is a real deployment decision to make, so Phase 9 remains focused on local orchestration and Phase 10 remains the Azure deployment phase.
- **Resource composition refinements** — expand `WithReference()`, `WaitFor()`, and `WithEnvironment()` usage as additional services join the graph, but keep the initial Phase 9 shape intentionally simple.

### Key Deliverables

- **Deepen .NET Aspire adoption** — Aspire-Lite (`AppHost` + service discovery + dashboard) was already introduced in Phase 9; Phase 13 promotes it from "alongside Docker Compose" to the primary inner-loop orchestrator
- **Resource composition refinements** — advanced patterns: `WithReference()`, `WaitFor()`, `WithEnvironment()` ReferenceExpressions, persistent container lifetimes for stateful resources, run-mode vs publish-mode resource graph differences
- **Integration tests** — `DistributedApplicationTestingBuilder` for end-to-end tests against the live Aspire graph; replaces hand-stitched `WebApplicationFactory` compositions where multi-service interaction is under test
- **Full end-to-end trace correlation** across all services via the OTEL pipeline already standardized in the Phase 9 `ServiceDefaults` project
- **Evaluate `azd` + Aspire-generated manifest as an ACA deployment path** — the .NET 10 blueprint reference uses `aspire deploy` / `azd provision` + `azd deploy` driving Aspire-generated Bicep. Compare against our hand-authored `infra/` Bicep on three axes: audit traceability (production), iteration speed (non-prod), and parameterization granularity. **Outcome captured in a new ADR**: either adopt `azd` for non-revenue-critical environments while keeping hand-authored Bicep for production, or remain on hand-authored Bicep across all environments with documented rationale.
- **.NET LTS upgrade window** — if not already done, Phase 13 is the natural moment to evaluate upgrading from .NET 8 to the then-current LTS. Capture it under its own ADR with a compatibility matrix for EF Core, Aspire, and Azure SDK packages; keep it as an evaluation gate rather than a Phase 10 commitment.

### Phase 13 Status Table

| Area | Status | Next Step | Phase |
|---|---|---|---|
| Aspire deepening | Planned | Promote Aspire from parallel helper to primary inner-loop orchestrator | Phase 13 |
| Distributed app testing | Planned | Move to `DistributedApplicationTestingBuilder` against the live Aspire graph | Phase 13 |
| Manifest / `azd` evaluation | Planned | Decide on ACA deployment packaging with an ADR-backed comparison | Phase 13 |
| Resource composition refinements | Planned | Expand `WithReference()`, `WaitFor()`, and `WithEnvironment()` usage | Phase 13 |
| Trace correlation deepening | Planned | Keep full-service correlation aligned with the OTEL pipeline | Phase 13 |
| .NET LTS upgrade | Planned | Evaluate the runtime upgrade window and package compatibility | Phase 13 |
| ACA transport / identity / platform rollout | Not Phase 13 | Keep that as Phase 10 work | Phase 10 |
| Database ownership / polyglot persistence | Not Phase 13 | Keep those as Phase 11 and 11.5 work | Phase 11 / 11.5 |

### Outcome

Enterprise-grade, cloud-native system with excellent developer inner-loop experience, integration-tested service graph, and an explicit recorded decision on `azd`-vs-hand-authored Bicep for ACA deployment.

---

## Phase 14 — CQRS Read Model with Cosmos DB (MongoDB API) 📅

**Focus:** Separate read and write models for performance and scalability.

**Why this phase is separate:** Phase 14 is the final architectural read-model step. It depends on the earlier event flow, service ownership, and operational foundation so the read side can be optimized without reintroducing coupling to the write model.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CQRS READ/WRITE SEPARATION                        │
│                                                                      │
│  WRITE PATH                           READ PATH                     │
│  ─────────                            ─────────                     │
│                                                                      │
│  ┌──────────┐    ┌─────────────┐      ┌──────────┐    ┌──────────┐ │
│  │ Command  │───►│  Handler    │      │  Query   │───►│ Cosmos DB│ │
│  │ (POST/   │    │ (validates, │      │  (GET)   │    │ MongoDB  │ │
│  │  PUT/    │    │  writes)    │      └──────────┘    │ API      │ │
│  │  DELETE) │    └─────────────┘                      │ (fast    │ │
│  └──────────┘          │                          │  reads)  │ │
│                        │                          └──────────┘ │
│                        │                                ▲       │
│               ┌────────▼─────────┐                          │       │
│               │  SQL Server      │                          │       │
│               │  (Source of      │                          │       │
│               │   Truth)         │                          │       │
│               │  ┌────────────┐  │                          │       │
│               │  │ Outbox     │  │                          │       │
│               │  │ Messages   │──┼──────────┐               │       │
│               │  └────────────┘  │          │               │       │
│               └──────────────────┘          │               │       │
│                                             │               │       │
│                                  ┌──────────▼─────────┐     │       │
│                                  │  Event Bus          │     │       │
│                                  │  (Service Bus)      │     │       │
│                                  └──────────┬──────────┘     │       │
│                                             │               │       │
│                                  ┌──────────▼─────────┐     │       │
│                                  │  Projection         │     │       │
│                                  │  Handlers           │─────┘       │
│                                  │  (update MongoDB)   │             │
│                                  └──────────┬──────────┘             │
│                                             │                        │
│                                  ┌──────────▼─────────┐              │
│                                  │  Hangfire Jobs      │              │
│                                  │  • Rebuild projs    │              │
│                                  │  • Fix inconsist.   │              │
│                                  │  • Backfill data    │              │
│                                  └─────────────────────┘              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

**1. Read Models (Azure Cosmos DB for MongoDB API)**
- Denormalized documents: Orders with Customer + Payment info, optimized for UI queries
- `TenantId` as **partition key** — natural fit for multi-tenancy; included in every document; query filters applied per tenant
- Same MongoDB .NET driver — code runs against Cosmos DB for MongoDB API with zero changes
- **RU provisioning** — autoscale with configurable max RU cap per collection

**2. Projection Handlers**
- Consume events: `OrderCreated`, `PaymentProcessed`, `CustomerUpdated`
- Build/update denormalized Cosmos DB documents in near-real-time

**3. Background Jobs (Hangfire)**
- Rebuild projections on demand
- Fix inconsistencies between SQL and Cosmos DB
- Backfill missing data after schema changes
- **Distributed locking (job-specific showcase)** — optional singleton coordination for projection rebuild/backfill jobs when duplicate execution across multiple instances would create operational inconsistency. Keep this as a concrete example (for example, `RebuildOrdersProjectionJob`) rather than introducing a generic lock abstraction; prefer idempotency first

**4. Multi-Tenancy**
- `TenantId` as partition key in every Cosmos DB document
- All read queries filtered by tenant — same pattern as EF global filters

### Rules (Critical)

- **No dual write** — never write to SQL + Cosmos DB in the same request
- **Always:** Write → SQL → Outbox → Event Bus → Projection → Cosmos DB
- **Cosmos DB is NOT the source of truth** — SQL Server is authoritative
- **Eventual consistency** — reads may lag behind writes by seconds

### Read Model Versioning

- Every Cosmos DB document includes a `_schemaVersion` field (integer)
- Projection handlers write the current schema version; older documents coexist with newer ones
- **Backward-compatible projections** — query code handles missing fields with sensible defaults
- On major schema change, a Hangfire job rebuilds the projection from event history, bumping `_schemaVersion`
- **Projection lag metric** — OTel gauge tracking seconds between last SQL write and corresponding Cosmos DB update; alert if > threshold
- **Cosmos DB change feed** — noted as an alternative to Service Bus for driving projections (can be evaluated if latency requirements tighten)

### Outcome

True CQRS with read/write separation, high-performance queries via Cosmos DB (MongoDB API), scalable read layer with `TenantId` partitioning, and eventually consistent system.

---

## Comparison Matrix

| Feature | Baseline (Monolith) | Phase 9 (YARP Local) | Phase 10 (ACA Cloud) | Phase 14 (Core State) |
|---------|--------------------|--------------------|--------------------|-----------------------|
| **Deployment** | 2 App Services | Docker Compose (7 containers) | ACA (auto-scaling) | ACA + Cosmos DB |
| **Communication** | In-process | Events + HTTP | Service Bus + Event Grid + HTTP | Service Bus + Event Grid + HTTP |
| **Data** | Single shared DB | Single shared DB | Single shared DB | DB per service + Cosmos DB |
| **Scaling** | Vertical only | Per-container | Per-service auto-scale | Per-service + read replicas |
| **Identity** | Key Vault (basic) | N/A (local) | Entra ID + JWT + MI | Entra ID + JWT + MI |
| **Observability** | App Insights | OTel + local traces | OTel + Azure Monitor | Full distributed traces |
| **Resilience** | None | Polly basics (retry + CB) | Polly + advanced + DLQ | Polly + dead-letter + retry |
| **API Gateway** | N/A | YARP (local) | APIM (public) + YARP (internal) | APIM + YARP |
| **Dev Experience** | VS F5 | Docker Compose | ACA deploy | .NET Aspire |

---

## Azure Functions Capability Ladder (Assignment Plan) 📅

The assignment set below is folded into the roadmap as a single capability ladder rather than as disconnected exercises. The sequence stays intentional: request/response and storage first, orchestration and background processing next, then configuration and performance work, and only after that the optional search and AI expansions.

| Assignment | Capability | Roadmap Phase | Aspire role |
|---|---|---|---|
| 1 | HTTP Function + Blob Storage persistence | Phase 10 | Use Azurite locally, Storage Account in Azure, and environment-driven connection strings / managed identity |
| 2 | Durable Function orchestration | Phase 11 | Host orchestrator + activity functions for long-running workflows and compensation |
| 3 | HTTP to Service Bus queue | Phase 10 | Model command dispatch and async transport behind the Azure messaging lane |
| 4 | Queue-trigger processing | Phase 10 / 11 | Use queue-triggered workers for background jobs, retries, and structured logging |
| 5 | API with Azure SQL Database | Phase 10 / 11 | Keep Azure SQL as source of truth and harden the data-access boundary |
| 6 | Cache-aside pattern with Redis | Phase 12 | Treat cache policy, TTL, and invalidation as part of platform performance work |
| 7 | Search API with Azure AI Search | Post-14 Horizon 15/16 | Optional search/discovery capability; promote only if the product needs a real search surface |
| 8 | AI summary storage with Azure OpenAI + Blob Storage | Post-14 Horizon 15/16 | Optional AI enrichment lane; keep it isolated from the core architecture closeout |
| 9 | Configuration + feature flags API | Phase 12 | Use Azure App Configuration as the runtime configuration backbone |
| 10 | Secure secret retrieval with Key Vault | Phase 10 / 12 | Use managed identity and Key Vault for secret access without hardcoding |

### Real Project Fit For The Assignment Ladder

Use each assignment as a thin slice of the order-processing platform, not as a separate toy sample:

- Assignment 1 maps to an HTTP Function that persists a lightweight order or user-provisioning artifact in Blob Storage and reads it back safely.
- Assignment 2 maps to payment or fulfillment orchestration where the durable workflow must survive retries, delays, and compensating actions.
- Assignment 3 maps to the API boundary that turns an order-created action into a Service Bus command for downstream processing.
- Assignment 4 maps to background queue processing for notifications, enrichment, or replay support.
- Assignment 5 maps to an Azure SQL-backed API slice that writes authoritative order or customer data and returns a summary result.
- Assignment 6 maps to cache-aside reads for catalog, customer, tenant, or order lookups while SQL remains the source of truth.
- Assignment 7 maps to a search endpoint for order history, support lookup, or product discovery if the domain needs indexed reads.
- Assignment 8 maps to AI-generated summaries for support notes, operational digests, or order-event descriptions stored in Blob Storage.
- Assignment 9 maps to App Configuration and feature-flag control for a new checkout, notification, or operator workflow.
- Assignment 10 maps to secure retrieval of provider keys, webhook secrets, or database credentials through Key Vault and managed identity.

### Roadmap Rules For The Assignment Ladder

- Assignments 1, 3, 4, 5, and 10 belong to the core Azure transport and platform hardening path.
- Assignment 2 belongs to the workflow and orchestration path and must stay deterministic.
- Assignments 6 and 9 belong to the platform engineering and operations path.
- Assignments 7 and 8 are valuable but optional expansions, so they stay in post-14 horizons unless a concrete product need moves them earlier.
- Aspire should host the full environment graph for each phase, but the production technologies should still be introduced only when the roadmap phase asks for them.

### Phase-By-Phase Rationale

This roadmap is intentionally split by dependency shape, not by assignment count. Each phase unlocks the next one and keeps the earlier proof stable.

- **Phase 9** exists first because module boundaries, YARP routing, Docker orchestration, and traced local flows must be proven before cloud transport or workflow changes are worth carrying.
- **Phase 9.5** stays separate because identity portability is a narrow proof: it validates local Keycloak shape without changing the production Entra model.
- **Phase 10** absorbs assignments 1, 3, 4, 5, and 10 because they are the cloud transport and resource-hardening primitives: Blob, Service Bus, SQL, and secret access need Azure-hosted infrastructure and secure wiring.
- **Phase 11** absorbs assignment 2 because Durable Functions and database autonomy are about workflow orchestration and service ownership, which only make sense after the transport layer is stable.
- **Phase 11.5** remains isolated because PostgreSQL is a portability showcase for one module, not a platform-wide store replacement.
- **Phase 12** absorbs assignments 6 and 9 because cache policy and configuration management are cross-cutting operational concerns that only pay off once the service graph and identity/transport backbone are already settled.
- **Phase 13** stays focused on Aspire deepening and distributed app testing because those improvements are about developer experience and live-graph validation, not business capability.
- **Phase 14** is reserved for CQRS read models because Cosmos DB projections only make sense after event flow, service ownership, and operational discipline already exist.
- **Post-14 horizons** keep Azure AI Search and Azure OpenAI separate because they are feature expansion lanes, not prerequisites for the core architecture closeout.

---

## Post-14 Horizons 📅

These lanes are intentionally beyond the core 14-phase architecture. They capture technically important concepts that should be considered if the product grows further, but they do not block the current Phase 14 closeout.

### Horizon 15 — Productization & Supportability

**Focus:** make the platform easier to operate, support, and reuse internally.

### Horizon 15 Candidate Items

- **Source-generated CQRS assessment** — evaluate a source-generated mediator/CQRS engine only if the maintenance cost or feature throughput justifies moving away from the hand-rolled baseline.
- **Tenant lifecycle automation** — explicit provisioning, tenant upgrades, and repeatable seeding so onboarding is a routine operation rather than a manual runbook.
- **Dedicated migrator/seeder lane** — keep migration and seed execution out of request startup and run it through deployment or admin workflows.
- **Soft-delete and audit policy** — standardize audit/interception behavior where compliance or business retention requires it.
- **Cache policy conventions** — define tenant-safe cache keys, TTLs, and invalidation rules instead of ad hoc caching.
- **Notification dispatch** — keep outbound mail and async notification delivery inside a single module boundary.
- **Generated API docs and SDKs** — treat OpenAPI/Scalar-style docs and typed client generation as a first-class consumable surface.
- **Path-scoped CI and test governance** — preserve warnings-as-errors, path-specific pipelines, and the full automated matrix without forcing everything through one giant workflow.
- **Enterprise observability workbooks** — deepen Azure Monitor, Application Insights, dependency maps, SLO views, DLQ dashboards, cost views, and incident triage workbooks after the core platform is stable.
- **Supply-chain evidence maturity** — standardize SBOM retention, vulnerability scan retention, signed-image evidence, and release traceability once ACR is the active registry.

### Horizon 16 — Optional Channels & Expansion

**Focus:** add optional user-facing channels and support workflows only when product need is clear.

### Horizon 16 Candidate Items

- **Real-time UI updates** — SignalR or SSE-style updates for dashboards and live user interactions.
- **Delegated support / impersonation** — staff-grade support workflows for troubleshooting or service operations, only if the business needs them.
- **Multi-frontend expansion** — admin console, mobile client, or additional web surfaces beyond the current React web app.
- **Search and discovery** — add a dedicated search/indexing experience if the domain needs efficient cross-entity lookup.
- **Azure AI Search / Azure OpenAI / AI agents** — add AI-assisted search, summarization, support automation, or operator copilots only when the product has a concrete user journey.
- **Kafka or streaming platform assessment** — evaluate Kafka only if the product needs high-throughput streams, long retention, stream processing, or replayable analytics beyond Service Bus/Event Grid.
- **AKS / Kubernetes platform assessment** — evaluate AKS only if the application needs cluster-level extensibility, custom ingress/service mesh, platform team standardization, or Kubernetes-native operations beyond ACA.
- **Template / CLI packaging** — productize the repo as an internal starter kit or bootstrap template only if reuse becomes a real objective.

### Horizon Rules

- These horizons do **not** change the current Phase 14 closeout criteria.
- They should only be promoted into a numbered phase when the product justifies the investment.
- Keep them out of the active implementation queue until the current roadmap is closed and a new business case appears.

---

## Migration Strategy

### Incremental Approach

The monolith remains operational throughout. Each phase adds capability without breaking production.

```
Baseline (Monolith) ─── ✅ Running on Azure App Service
     │
     ├── Phases 1-6  ─── ✅ Internal modernization (CQRS, OTel, tenancy, caching)
     │
  ├── Phase 7     ─── ✅ Tenant enforcement & security hardening
  │
  ├── Track U     ─── 📅 React web replacement + MVC retirement + mobile follow-on
     │
     ├── Phase 8     ─── 📅 Event-driven core (Outbox + events inside monolith)
     │
    ├── Phase 8.5   ─── ✅ Multi-provider payment (OpenPay + Razorpay, keyed DI, retry classification)
     │
    ├── Phase 8.6   ─── ✅ Central Tenant Registry (separation of duties, ops-only DB)
     │
    ├── Phase 8.7   ─── ✅ Provider webhooks (signed, idempotent, tenant-aware)
     │
     ├── Phase 9     ─── 📅 Extract services locally (YARP + Docker Compose + Aspire-Lite)
     │
     ├── Phase 9.5   ─── ✅ Cloud-portable identity (local Keycloak demo)
     │
     ├── Phase 10    ─── 📅 Deploy to ACA + Service Bus + APIM + Functions
     │
     ├── Phase 11    ─── 📅 Split databases (each service owns its data)
     │
     ├── Phase 11.5  ─── 📅 Polyglot persistence (Notifications module on PostgreSQL)
     │
     ├── Phase 12    ─── 📅 Platform engineering (App Config, CI/CD, dashboards)
     │
     ├── Phase 13    ─── 📅 Aspire deepening (testing, manifest → azd, advanced composition)
     │
     └── Phase 14    ─── 📅 CQRS read model (Cosmos DB) — final architecture
```

### Why This Order?

| Transition | Why it must come first |
|------------|----------------------|
| Phase 7 before 8 | Tenant safety must be enforced before events carry tenant context |
| Phase 8 before 8.5 | Outbox + Inbox required for provider-aware reconciliation and webhook deduplication |
| Phase 8.5 before 8.6 | Per-tenant provider assignments must be stable in the DB before the Registry is extracted into a separate ops-owned DB |
| Phase 8.6 before 8.7 | Webhook handler needs authoritative tenant resolution from the Registry; hardcoded seed data is not a safe source for this |
| Phase 8.7 before 9 | Webhook receiver lives in monolith first; carried unchanged into microservice extraction |
| Phase 8 before 9 | Events must exist before services can communicate asynchronously |
| Phase 9 before 9.5 | Docker Compose infrastructure required to host local Keycloak container |
| Phase 9 before 10 | Validate microservices locally before deploying to cloud |
| Phase 10 before 11 | Cloud infrastructure must exist before splitting databases |
| Phase 11 before 11.5 | Database-per-service ownership required before swapping a single module's RDBMS provider |
| Phase 11 before 12 | Data ownership enables per-service CI/CD pipelines |
| Phase 12 before 13 | Platform foundations needed before Aspire deepening |
| Phase 13 before 14 | Aspire orchestration simplifies MongoDB integration |

---

## Learning Objectives by Phase

### Phases 1-6 ✅ Achieved
- [x] Azure App Service deployment + CI/CD with GitHub Actions
- [x] Infrastructure as Code (Bicep) + Application Insights
- [x] Clean Architecture + CQRS with `Result<T>` pattern
- [x] `IAppDbContext` abstraction + SharedKernel
- [x] OpenTelemetry observability (auto-instrumentation + custom ActivitySources)
- [x] Multi-tenancy skeleton (EF global filters, `X-Tenant-Code` header)
- [x] Structured test projects (Domain, Application, API, Integration)
- [x] Caching pipeline, API versioning `/api/v1/`, health checks, CancellationToken, TimeProvider
- [x] Roslyn analyzers (Roslynator, Meziantou, SonarAnalyzer) — build-time code quality enforcement
- [x] Architecture tests (`NetArchTest.Rules`) — enforcing Clean Architecture layer boundaries
- [x] Central Package Management — `Directory.Packages.props` as single source of truth for all NuGet versions

### Phase 7-8 📅 Hardening & Events
- [x] Tenant enforcement + audit logging
- [x] Security headers + liveness/readiness health checks
- [x] ProblemDetails (RFC 9457) + global exception middleware
- [x] DDD tactical patterns: aggregate root, state machine (`Order` status transitions), `Money`, strongly-typed IDs (`OrderId`, `CustomerId`), and domain invariants via `Result<T>`; `Address` is intentionally deferred until a real aggregate or request boundary exists
- [ ] Optimistic concurrency — `Order` `RowVersion` is implemented; broader rollout stays deferred and explicit concurrency-conflict surfacing remains open only if strict Phase 7 closeout parity is required
- [ ] Domain events + integration events
- [ ] Outbox pattern + background event publisher
- [ ] Inbox pattern (idempotent consumers) + event versioning
- [ ] Parallel event handler execution (`Task.WhenAll` + `AggregateException` aggregation)

### Phase 9-10 📅 Microservices & Cloud
- [x] Module isolation: per-module project structure (Domain/Features/Infrastructure/API per module)
- [x] API contracts (`IOrderModuleApi`, `IInventoryModuleApi`) — inter-module communication via contracts only
- [x] Per-module DB schemas in shared database + `IModuleDatabaseMigrator` per module
- [x] Module self-registration (`AddOrdersModule()`) + `AssemblyReference.cs` markers
- [x] Architecture tests (NetArchTest) enforcing inter-module boundaries
- [x] Specification pattern — composable, testable query objects per module (replaces inline LINQ in handlers)
- [x] YARP reverse proxy + service extraction from isolated modules
- [x] Gateway cross-cutting (CORS, rate limiting, request logging, size limits)
- [ ] SharedContracts project for inter-service event schemas + DTOs
- [x] Docker Compose orchestration (including Redis)
- [x] Polly v8 basics (retry, circuit breaker, timeout) from day one
- [x] Graceful shutdown + structured concurrency
- [ ] Azure Container Apps deployment
- [ ] Azure API Management (APIM) as public gateway (Consumption tier)
- [ ] Azure Service Bus messaging backbone + DLQ handling
- [ ] Azure Event Grid for platform/infrastructure events
- [ ] Azure Functions for DLQ reprocessing (Service Bus trigger, isolated process)

### Phase 9 vs Phase 10 Split

#### Phase 9 closure scope

- Done: module isolation and API boundaries
- Done: per-module schemas in a shared database
- Done: module self-registration and architecture tests
- Done: specification standardization
- Done: YARP gateway and local cross-cutting concerns
- Done: Docker Compose orchestration
- Done: graceful shutdown and local runtime proof
- Done: unit, integration, and Playwright validation of the local gateway/payment flows

#### Phase 10 scope

- Azure Container Apps deployment
- Azure API Management
- Azure Service Bus and DLQ handling
- Azure Event Grid
- Azure Functions for DLQ reprocessing
- Cloud deployment validation and platform hardening

#### Deferred unless Phase 10 needs it

- SharedContracts project for inter-service event schemas + DTOs
- Any new service-contract refactor that exists only to support cloud/event integration

#### SharedContracts implementation plan

If the repo proves that the same event/DTO shape is being duplicated across multiple services during Phase 10 transport work, introduce a small `SharedContracts` project as a thin, versioned package that contains only shared integration-event DTOs and envelope types.

Use it only for:
- cross-service event schemas that genuinely need a stable shared shape
- versioned message contracts that must be consumed by more than one service
- any minimal common envelope metadata that would otherwise drift between services

Do not use it for:
- service-specific request/response models
- domain entities
- gateway-only DTOs
- anything that would weaken module boundaries

Implementation order:
1. Keep Phase 9 clean and do not add new contract refactors there.
2. During Phase 10, only add `SharedContracts` if the transport/workflow code shows real duplication.
3. Keep the package tiny and versioned, with one-way dependency from services to contracts.
4. Revisit Phase 11 only if saga orchestration or service autonomy reveals a stronger need.

#### Phase 9 remaining status

| Item | Status | Notes |
|---|---|---|
| SharedContracts project for inter-service event schemas + DTOs | Deferred / Candidate for Phase 10 | Keep out of Phase 9; promote only if Phase 10 transport work proves real duplication across services |
| Any new service-contract refactor for cloud/event integration | Deferred | Do not reopen Phase 9 boundaries for this work |
| Physical module split, schema ownership, startup wiring, and test coverage | Done | Already reflected as completed in the Phase 9 closeout summary below |
| Local HTTP and Docker Dev HTTP validation alignment | Done | Keep task naming and run order aligned with the labeled flows |

### Phase 9 Closure Reality Check

Phase 9 now has the local gateway proof, API boundary markers, module registration facades, per-module schema ownership, specification standardization, shared-host consolidation, traced multi-service flow proof, and graceful-shutdown proof in place. The only remaining policy decision is the explicit SharedContracts deferral.

**Phase 9 closeout summary**
- **Achieved:** local HTTP and Docker Dev HTTP validation paths are wired and ordered; task naming is normalized across Local, Docker, and Azure; Playwright smoke, matrix sanity, integration, and full-validation entrypoints are exposed consistently in VS Code.
- **Achieved:** the matrix dry-run and runtime wiring now reflect the intended tenant/provider discovery model for local and Docker paths, including the dynamic shared vs dedicated tenant and provider assignment rules.
- **Achieved:** shared host consolidation and traced multi-service flow proof are recorded as complete in the Phase 9 roadmap.
- **Remaining:** record the SharedContracts decision as deferred and keep any new service-contract refactor out of Phase 9.
- **Recommendation:** close Phase 9 as complete for wiring, runtime proof, and label hygiene; keep SharedContracts as an explicit deferred decision and move any future contract-refactor work into the next phase.

**Phase 9.5 status summary**
- **Achieved:** local HTTP and Docker Dev HTTP portability proof is runtime verified.
- **Achieved:** Keycloak remains local-only and the production identity model remains Entra ID.
- **Deferred:** any Azure-side Keycloak parity or migration testing remains outside this phase.
- **Done:** Phase 9.5 is retained as a portability showcase, not as a production identity change.

#### Phase 9 automation and validation rule

Phase 9-local validation must always be exercised in both local HTTP and Docker dev HTTP forms before a phase-closeout judgment is made.

- Local HTTP matrix dry-run must resolve all three tenants and both payment providers.
- Docker dev HTTP matrix dry-run must resolve the same tenant/provider coverage.
- Local HTTP task order must remain:
  1. `1 Run: Local HTTP 01 Env Ready + Keycloak`
  2. `1 Run: Local HTTP 02 Playwright Smoke`
  3. `1 Run: Local HTTP 03 Matrix Sanity (1 Tenant, Local HTTP)`
  4. `1 Run: Local HTTP 04 Integration Suite (Local SQL, No Docker)`
  5. `1 Run: Local HTTP 05 Full Validation (All Tenants + Providers, Local HTTP)`
- Docker dev HTTP task order must remain:
  1. `1 Run: Docker Dev HTTP 01 Env Ready + Keycloak (Docker Dev HTTP)`
  2. `1 Run: Docker Dev HTTP 02 Playwright Smoke (Docker Dev HTTP)`
  3. `1 Run: Docker Dev HTTP 03 Integration Suite (Docker Dev HTTP)`
  4. `1 Run: Docker Dev HTTP 04 Payment Matrix (All Tenants + Providers, Docker Dev HTTP)`
  5. `1 Run: Docker Dev HTTP 05 Full Validation (Profile + Suite + Smoke + Matrix, Docker Dev HTTP)`
- The corresponding log pointers must be written per environment:
  - `TestResults\Playwright\local-http\latest-playwright-smoke.txt`
  - `TestResults\Playwright\local-http\latest-playwright-matrix.txt`
  - `TestResults\Playwright\local-http\latest-playwright-full-validation.txt`
  - `TestResults\Playwright\docker-http\latest-playwright-smoke.txt`
  - `TestResults\Playwright\docker-http\latest-playwright-matrix.txt`
  - `TestResults\Playwright\docker-http\latest-playwright-full-validation.txt`
- The shared live progress log must stay visible during the run:
  - `TestResults\Playwright\local-http\sequence-summary.log`
  - `TestResults\Playwright\docker-http\sequence-summary.log`
- Never mark Phase 9 complete unless the matrix dry-run and the actual local/Docker task paths are aligned with the labels above.

- [x] API seam exists for Orders, Inventory, Notifications, and Payments
- [x] Module registration facades exist for the four modules
- [x] `AssemblyReference.cs` markers exist for the four API projects
- [x] Local build and architecture-test coverage confirms the seam
- [x] Full per-module project split implemented (`*.Domain`, `*.Features`, `*.Infrastructure`)
- [x] Per-module DB schema ownership implemented
- [x] Per-module migrator startup flow implemented
- [x] Specification pattern standardization applied across the split modules

Treat the unchecked items above as the remaining Phase 9 completion work. Do not mark Phase 9 fully complete until the physical module split and schema ownership are real, wired into startup, and covered by tests.
- [ ] Azure Blob Storage for order attachments (invoices, receipts) + Event Grid integration
- [ ] Azure Cache for Redis (managed)
- [ ] Azure Entra ID + JWT authentication
- [ ] Blue-green + canary deployments via ACA revisions
- [ ] Cost governance (scale-to-zero, budget alerts)

### Phase 11-12 📅 Autonomy & Operations
- [ ] Database per service + data ownership
- [ ] Choreography vs Saga decision framework
- [ ] Azure Durable Functions project — orchestrator + activity functions for Saga workflows
- [ ] Database migration strategy (EF bundles + init containers)
- [ ] Performance conventions (`AsNoTracking`, indexing review, EF Core 8 `SqlQuery<T>` for complex queries, bulk operations)
- [ ] Per-service CI/CD pipelines
- [ ] Observability dashboards + SLOs
- [ ] Advanced Polly (bulkhead, fallback)
- [ ] Azure App Configuration + feature flags
- [ ] Azure AI Document Intelligence (invoice extraction from Blob Storage uploads)
- [ ] DR / Business Continuity (RTO/RPO targets, geo-replication strategy)
- [ ] Performance / Load Testing (Azure Load Testing or k6)

### Phase 13-14 📅 Maturity & CQRS
- [ ] .NET Aspire orchestration + resource definitions + service discovery
- [ ] Aspire integration tests (`DistributedApplicationTestingBuilder`)
- [ ] Cosmos DB (MongoDB API) read models + projection handlers
- [ ] Partition key strategy (`TenantId`) + autoscale RU provisioning
- [ ] Read model versioning (`_schemaVersion`) + projection lag metric
- [ ] Cosmos DB change feed awareness (alternative projection driver)
- [ ] Hangfire background jobs for projection rebuilds
- [ ] Narrow distributed-locking showcase for one Hangfire rebuild/backfill job (non-generic singleton coordination)
- [ ] Snapshot pattern — periodic aggregate snapshots for fast rebuild from event history

---

## Core Architecture State (After Phase 14)

| Capability | Implementation |
|-----------|----------------|
| **Architecture** | Clean Architecture + CQRS + Event-Driven Microservices (modular monolith → microservices extraction) |
| **Gateway** | APIM (public, north-south) + YARP (internal, east-west) with JWT validation |
| **Communication** | Azure Service Bus (async domain events) + Event Grid (platform events) + HTTP (sync queries) |
| **Write DB** | SQL Server (source of truth) per service |
| **Read DB** | Azure Cosmos DB for MongoDB API (denormalized projections, TenantId partition key) |
| **Identity** | Azure Entra ID + JWT + Managed Identity |
| **Multi-tenancy** | Enforced at every layer (API, events, DB, Cosmos DB partition key) |
| **Observability** | OpenTelemetry + App Insights + Azure Monitor dashboards |
| **Resilience** | Polly (retry, circuit breaker, timeout, bulkhead) + dead-letter queues |
| **Performance** | `AsNoTracking` convention, indexed tenant queries, EF Core 8 `SqlQuery<T>` for complex queries, bulk operations |
| **Cache** | Azure Cache for Redis (distributed cache + session state) |
| **Error Handling** | ProblemDetails (RFC 9457) + global exception middleware |
| **Domain Modeling** | DDD aggregate roots, state machines, value objects, domain invariants via `Result<T>` |
| **Module Boundaries** | Per-module API contracts, `AssemblyReference.cs` markers, NetArchTest enforcement |
| **Code Quality** | Roslyn analyzers (Roslynator, Meziantou, SonarAnalyzer) — build-time enforcement |
| **Events** | Versioned schemas (inbox + outbox) + choreography with Saga escalation + parallel dispatch |
| **Workflows** | Azure Durable Functions — orchestrator/activity pattern for Saga workflows with compensating actions |
| **Serverless** | Azure Functions for DLQ reprocessing + scheduled health checks + Durable orchestrations |
| **File Storage** | Azure Blob Storage (order attachments, private endpoint) |
| **AI / Cognitive** | Azure AI Document Intelligence (invoice data extraction) |
| **Orchestration** | .NET Aspire (local) + Azure Container Apps (cloud) |
| **CI/CD** | Per-service GitHub Actions + health check deployment gates |
| **Deployments** | Blue-green + canary via ACA revisions |

---

## Gap Analysis: Patterns Evaluated & Deferred

_Patterns from industry reference architectures evaluated against the 14-phase plan. Items below were considered and deliberately deferred or excluded — documented here so the reasoning is preserved._

| Pattern | Decision | Phase | Rationale |
|---|---:|---|---|
| Explicit `IUnitOfWork` interface | Skipped | N/A | `IAppDbContext` already exposes `SaveChangesAsync()` and DbSets — separate `IUnitOfWork` would duplicate abstraction in the monolith. |
| Repository per aggregate root | Skipped / Deferred | Phase 9 | Repositories add indirection in a monolith; useful when modules own persistence (Phase 9+). |
| Dapper for CQRS read side | Deferred | Phase 14 | Performance/read-model optimization — not needed until dedicated read stores or heavy denormalized queries. |
| `EFCore.BulkExtensions` or `ExecuteSqlInterpolated` for bulk writes | Deferred | Phase 11 | Bulk write optimizations are useful only once service-owned databases and real batch import/export scenarios exist. Premature use would bypass normal EF change tracking and complicate write-side behavior before throughput data justifies it. |
| `IConfigureNamedOptions<T>` (JWT setup) | Skipped | Phase 10 | Implementation detail applied when Entra ID/JWT is wired; not a design-level requirement. |
| Local Keycloak (IdP) | Deferred | Phase 9 | Requires Docker Compose infra; defer until local microservice orchestration exists. |
| `DelegatingHandler` for external HTTP | Deferred | Phase 9 | Relevant for inter-service `HttpClient` use; implement when services call each other. |
| Optimistic concurrency (`RowVersion`) | Added | Phase 7 | `RowVersion` is implemented on `Order`; broader rollout and explicit concurrency-conflict surfacing remain follow-up work where justified. |
| Strongly-typed IDs (`OrderId`, `CustomerId`) | Added | Phase 7 | Lightweight safety to prevent Guid parameter-swap bugs; use EF value converters for persistence. |
| SaveChangesAsync domain event dispatch (ChangeTracker) | Added | Phase 8 | Ensures domain events are only published after successful persistence (in-process or to Outbox). |
| Value Objects (`Money` implemented, `Address` deferred) | Added | Phase 7 | `Money` is implemented in Phase 7; `Address` remains deferred until a concrete customer, billing, or shipping boundary needs it. |


### Deliberately Skipped (Not Needed)

| Pattern | Why Skipped |
|---------|------------|
| **Explicit `IUnitOfWork` interface** (separate from DbContext) | `IAppDbContext` already serves this purpose — exposes `DbSet`s + `SaveChangesAsync()`. Adding a separate `IUnitOfWork` with only `SaveChangesAsync()` duplicates the abstraction without adding testability or flexibility. Both approaches are valid; this plan prefers one abstraction over two. Bookify's choice reflects MediatR conventions; our hand-rolled CQRS doesn't require it. |
| **Repository per aggregate root** (generic `Repository<T>` base) | Handlers call `_dbContext.Orders.FindAsync()` directly — adding a repository wrapper introduces indirection without value in a monolith where EF Core already provides unit-of-work + change tracking. Repositories become useful in Phase 9 (module isolation) as per-module persistence boundaries; the plan already implies them there. Adding them earlier is premature abstraction. |
| **Dapper for CQRS read side** (`ISqlConnectionFactory` + raw SQL for queries) | The read side currently targets the same SQL database with EF `AsNoTracking()` queries. Dapper's performance advantage matters at scale or with complex denormalized reads — neither applies until Phase 14 (MongoDB read models). Adding `ISqlConnectionFactory` now creates a second data-access path that must be maintained alongside EF Core with no measurable benefit. Phase 14's Cosmos DB read models achieve the CQRS read-side separation more completely. |
| **`IConfigureNamedOptions<T>`** (for JWT Bearer setup) | Clean pattern for injecting `IOptions<T>` into authentication configuration, but Phase 10 (Entra ID + JWT) is the earliest it becomes relevant. Not worth a plan bullet — will be applied as an implementation detail when JWT auth is wired. |
| **Vertical Slice Architecture (VSA)** | Feature-folder CQRS already delivers VSA's cohesion benefit — each feature's command, handler, validator, and DTO are co-located in `Features/{Domain}/`. VSA eliminates layer boundaries, which would break `NetArchTest` architecture tests (Phase 5), remove reusable pipeline behaviors (`ValidationBehavior`, `LoggingBehavior`, `CachingBehavior`), and prevent Phase 9 module isolation (can't extract `Orders.Domain` if domain logic is tangled with EF Core). Clean Architecture + feature folders = high cohesion AND low coupling; VSA trades the latter for the former. |

### Deferred to Later Phase (Will Add When Relevant)

| Pattern | Deferred To | Why Not Now |
|---------|-------------|-------------|
| **Local Identity Provider (Keycloak)** | Phase 9 (Docker Compose) | Docker Compose infrastructure doesn't exist until Phase 9. Adding Keycloak before that means managing a standalone Docker dependency just for auth testing — unnecessary when Azure Entra ID is already configured for the deployed app. Phase 9's Docker Compose is the natural home for local Keycloak alongside the other service containers. |
| **`DelegatingHandler` for external HTTP** (auto-inject auth tokens on outgoing calls) | Phase 9 (inter-service HTTP) | No inter-service HTTP calls exist until Phase 9 (YARP + microservices). The existing OpenPay adapter is a direct SDK call, not `HttpClient`. Phase 9's Polly v8 section (retry, circuit breaker, timeout) is where `HttpClientFactory` + `DelegatingHandler` patterns belong — they work together. |
| **`EFCore.BulkExtensions` or `ExecuteSqlInterpolated`** (bulk writes/imports) | Phase 11 (service-owned databases) | Bulk operations are a performance tool for true batch import/export or backfill scenarios, not a default write path. Before Phase 11, the system still centers on standard EF Core transactional writes, aggregate behavior, and normal `SaveChangesAsync()` flows. Introduce bulk writes only after service-owned databases exist and throughput measurements justify bypassing normal change tracking for specific batch workloads. |
| **Distributed locking / singleton job coordination** | Phase 14 (Hangfire rebuilds/backfills) | Not needed for normal request handling or event consumers because Inbox/Outbox idempotency and messaging semantics come first. Becomes relevant only for true singleton maintenance jobs such as projection rebuilds, backfills, or repair tasks where duplicate execution across multiple instances has real operational cost. Keep it as a single concrete example, not a shared locking framework. |
| **MCP server integration** (GitHub API, Azure CLI, DB queries via AI tooling) | Phase 9+ (microservices) | Current context infrastructure (copilot-instructions.md, 6 instruction files, 3 repo memory files, reusable prompts) covers ~90% of what MCP would provide for a monolith. MCP becomes valuable when cross-service context is needed — querying live infrastructure state across multiple ACA services, reading PR comments for multi-repo changes, or running cross-service health checks. Revisit when Docker Compose orchestration (Phase 9) or ACA deployment (Phase 10) creates the need for live external context that static memory files can't provide. |

### Already Covered (Analysis Missed It)

| Pattern | Where Covered |
|---------|---------------|
| **Value Object** (`Money`) | Phase 7 — DDD Tactical Patterns section; `Address` remains intentionally deferred until a concrete boundary exists |
| **Factory methods + private constructors** | Phase 7 — "`Order` entity with private constructor, `Create()` factory method returning `Result<Order>`" |
| **Entity state machine** (guard clauses returning `Result`) | Phase 7 — `Pay()`, `Ship()`, `Deliver()`, `Cancel()` each returning `Result<T>` |
| **Bogus/Faker for seed data** | Already in codebase — `Bogus` package in Infrastructure project, used for dev data seeding |
| **Domain event dispatch** | Phase 8 — Outbox pattern + automatic `SaveChangesAsync` dispatch via `ChangeTracker` |

### Added After Gap Analysis

| Pattern | Added To | Rationale |
|---------|----------|----------|
| **Optimistic concurrency** (EF `RowVersion` + `ConcurrencyException`) | Phase 7 | `RowVersion` is implemented on `Order`; explicit concurrency-conflict surfacing and broader rollout stay as follow-up work where justified. |
| **Strongly-typed IDs** (`OrderId`, `CustomerId` as `readonly record struct`) | Phase 7 | Eliminates `Guid` parameter-swap bugs at compile time. Lightweight pattern (one-line record struct + EF value converter) with high safety payoff. Natural companion to Value Objects. |
| **SaveChangesAsync domain event dispatch** (ChangeTracker extraction) | Phase 8 | Was implied by Outbox pattern but not explicitly documented. Made explicit: extract events from `ChangeTracker.Entries<Entity>()` after `base.SaveChangesAsync()` — ensures events only fire on successful persistence. |
| **Specification pattern** (composable query objects) | Phase 9 | Encapsulates reusable EF Core query logic (`Where`/`Include`/`OrderBy`) into named, testable specifications. Not useful in monolith (inline LINQ suffices); becomes valuable when per-module repositories need shared query definitions across handlers. |
| **Snapshot pattern** (point-in-time entity state capture) | Phase 14 | Enables fast aggregate rebuild from event history: load latest snapshot + replay recent events instead of full replay. Paired with Hangfire periodic snapshot jobs. Not needed until event volumes justify optimization. |

### Twelve-Factor App Compliance

_Every factor is already covered across the 14-phase plan — documented here for completeness._

| # | Factor | Where Covered | Status |
|---|--------|---------------|--------|
| 1 | **Codebase** — one repo, multiple deploys | GitHub repo + branch→env mapping (`dev`→dev, `staging`→staging, `main`→prod) | ✅ |
| 2 | **Dependencies** — explicitly declared | CPM (`Directory.Packages.props`), all NuGet packages versioned centrally (Phase 6) | ✅ |
| 3 | **Config** — env vars, not code | `sharedsettings.{dev,stg,prod}.json`, `ASPNETCORE_ENVIRONMENT`, Key Vault for secrets | ✅ |
| 4 | **Backing Services** — treat as attached resources | Azure SQL, Redis (Phase 6), Service Bus (Phase 10) — all via connection strings, swappable | ✅ |
| 5 | **Build, Release, Run** — strict separation | GitHub Actions: build → test → publish → deploy. 9 workflows. Docker images. | ✅ |
| 6 | **Processes** — stateless | `IDistributedCache` (Phase 6) — Redis or in-memory. No in-process session state. | ✅ |
| 7 | **Port Binding** — self-contained | Kestrel, Docker port mapping (5010–5043), ACA ingress (Phase 10) | ✅ |
| 8 | **Concurrency** — scale out via processes | ACA auto-scale + scale-to-zero (Phase 10), per-service scaling | ✅ |
| 9 | **Disposability** — fast startup, graceful shutdown | `IHostApplicationLifetime` drain pattern (Phase 9) | ✅ |
| 10 | **Dev/Prod Parity** — keep environments similar | Docker Compose mirrors prod (Phase 9), `sharedsettings` per env, same Bicep IaC all envs | ✅ |
| 11 | **Logs** — stream to stdout | Serilog Console sink (Phase 3), structured logging with `TraceId` + `TenantId` | ✅ |
| 12 | **Admin Processes** — one-off tasks as code | EF migrations (`run-database-migrations.ps1`), PowerShell bootstrap scripts, Hangfire jobs (Phase 14) | ✅ |

> All 12 factors are addressed. The plan doesn't explicitly name-drop "Twelve-Factor" as a concept, but every principle is implemented organically across Phases 1–14.

---

## References

### Documentation
- [AZURE-PROGRESS-EVALUATION.md](./docs/internal/AZURE-PROGRESS-EVALUATION.md) - Detailed learning plan
- [docs/README.md](./docs/README.md) - Central documentation hub
- [docs/guides/deployment/aca-migration-plan.md](./docs/guides/deployment/aca-migration-plan.md) - Container Apps operational runbook (13-phase)

### Azure Resources
- **Current Deployment:** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
- **Azure Portal:** https://portal.azure.com
- **Resource Group:** rg-orderprocessing-dev

### External References
- YARP Documentation: https://microsoft.github.io/reverse-proxy/
- Azure Container Apps: https://learn.microsoft.com/azure/container-apps/
- Azure API Management: https://learn.microsoft.com/azure/api-management/
- Azure Functions: https://learn.microsoft.com/azure/azure-functions/
- Azure Durable Functions: https://learn.microsoft.com/azure/azure-functions/durable/
- Azure Service Bus: https://learn.microsoft.com/azure/service-bus-messaging/
- Azure Event Grid: https://learn.microsoft.com/azure/event-grid/
- Azure Blob Storage: https://learn.microsoft.com/azure/storage/blobs/
- Azure AI Document Intelligence: https://learn.microsoft.com/azure/ai-services/document-intelligence/
- Azure Cosmos DB for MongoDB: https://learn.microsoft.com/azure/cosmos-db/mongodb/
- .NET Aspire: https://learn.microsoft.com/dotnet/aspire/
- Hangfire: https://www.hangfire.io/
- NetArchTest: https://github.com/BenMorris/NetArchTest
- Microservices Patterns: https://microservices.io/patterns/

---

## Appendix: Azure .NET Job Profile Coverage (Informative)

_This section maps the architecture plan to common Azure .NET senior role requirements. It is informative only — no actionable items._

### Coverage Scorecard

| Job Skill Area | Status | Where Covered |
|---|---|---|
| **C# / .NET Core** | ✅ Covered | .NET 8 throughout all 14 phases |
| **ASP.NET / ASP.NET Core** | ✅ Covered | API (controllers, middleware, pipeline), UI (MVC), YARP gateway |
| **Entity Framework** | ✅ Covered | EF Core, global query filters, migrations, `IAppDbContext`, DB per service (Phase 11) |
| **Azure App Services** | ✅ Covered | Baseline deployment — already running in production |
| **Azure Functions** | ✅ Covered | Phase 10 — DLQ reprocessor (Service Bus trigger), timer-triggered health checks; Phase 11 — Durable Functions orchestrations (Saga workflows) |
| **Azure Storage (Blob)** | ✅ Covered | Phase 10 — order attachments, managed identity, Event Grid integration |
| **Azure SQL Database** | ✅ Covered | Baseline → Phase 14 — source of truth, per-service DBs in Phase 11 |
| **Azure Cosmos DB (NoSQL)** | ✅ Covered | Phase 14 — MongoDB API, TenantId partition key, projections |
| **Cloud-native / Microservices** | ✅ Covered | Phases 9-14 — CQRS, event-driven, outbox/inbox, saga, scale-to-zero |
| **Scalability** | ✅ Covered | ACA auto-scale, Cosmos DB autoscale RU, canary/blue-green, Redis |
| **Integration** | ✅ Covered | Service Bus, Event Grid, Blob → Document Intelligence, OpenPay adapter |
| **CI/CD Pipelines** | ✅ Covered | GitHub Actions (9 workflows), per-service pipelines (Phase 12), OIDC deploy |
| **Git / Source Control** | ✅ Covered | GitHub repo, branch→environment mapping, PR workflows |
| **RESTful APIs** | ✅ Covered | All phases — versioned `/api/v1/`, Swagger, thin controllers |
| **Third-party API Integration** | ✅ Covered | OpenPay adapter (existing), Document Intelligence API (Phase 12) |
| **OAuth / OpenID Connect** | ✅ Covered | Phase 10 — Entra ID + JWT + OIDC (GitHub Actions already uses OIDC) |
| **Security Best Practices** | ✅ Covered | Phase 7 (headers, HSTS), Phase 10 (WAF, managed identity, private endpoints, Key Vault) |
| **Identity Management** | ✅ Covered | Entra ID, managed identity, JWT propagation, Key Vault RBAC (Phase 12) |
| **Data Encryption / Secrets** | ✅ Covered | Key Vault, private endpoints, TLS/HSTS — no plaintext credentials |
| **IaC (ARM / Bicep)** | ✅ Covered | Bicep IaC in `infra/` and `bicep/` folders (Bicep compiles to ARM) |
| **Azure Kubernetes Service (AKS)** | ⚠️ Equivalent | Plan uses **Azure Container Apps** (runs on AKS under the hood — same container concepts) |
| **Azure DevOps** | ⚠️ Equivalent | Plan uses **GitHub Actions** (identical CI/CD concepts, different tool) |

### Gap Analysis

**AKS vs ACA** — The plan uses Azure Container Apps, which is built on Kubernetes and covers ~70% of the same orchestration concepts (ingress, scaling rules, revisions, managed identity). ACA is Microsoft's recommended choice for .NET app teams that don't need custom Kubernetes operators, Helm charts, or cluster-level administration. Most Azure .NET roles accept ACA experience as equivalent.

**Azure DevOps vs GitHub Actions** — The plan uses GitHub Actions for all CI/CD. Azure DevOps pipelines use different YAML syntax but identical concepts (stages, jobs, steps, service connections, environments, approvals). The repo already has 9 workflows demonstrating advanced patterns (OIDC auth, reusable workflows, environment gates, manual dispatch). The CI/CD skill set transfers directly.

### Verdict

All technical skills from a typical Azure .NET senior role are fully covered or have strong equivalents in the plan. The two ⚠️ items (AKS, Azure DevOps) are low-risk because ACA is the modern successor to AKS for application teams, and GitHub Actions is the direct competitor to Azure DevOps Pipelines with identical concepts.

---

**Last Updated:** May 10, 2026
**Status:** Phase 8 Closeout Matrix Validation Passed ✅ | Track U U5 Complete ✅ | Phase 8.5 Complete ✅ | Phases 8.7, 9, 10, 11, 11.5, 12-14 Planned 📅 | Phase 9.5 identity portability runtime verified ✅

