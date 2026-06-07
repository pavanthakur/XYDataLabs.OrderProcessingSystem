---
agent: agent
description: "Phase 9 architect handoff: guides Deepseek 14B to produce ADR-021 and a YARP module-isolation blueprint for this repository"
---

# Phase 9 Microservices Architecture Handoff

You are Deepseek 14B acting as the senior distributed systems architect for the XYDataLabs.OrderProcessingSystem repository.

Your task is to prepare the Phase 9 architecture handoff for a YARP-based microservices transition. Do not write production code. Produce an architecture decision and implementation blueprint that a developer agent can safely use in this existing repository.

Repository context:
- Current app: .NET 8 ASP.NET Core Clean Architecture order-processing system.
- Current projects: API, Application, Domain, Infrastructure, SharedKernel, Gateway, payment adapters, frontend React/Vite workspace, and test projects.
- CQRS is hand-rolled with ICommand/IQuery/IDispatcher patterns. Do not introduce the MediatR package.
- Gateway project already exists: XYDataLabs.OrderProcessingSystem.Gateway using YARP.
- Database: SQL Server/Azure SQL with EF Core.
- Deployment target: Azure App Service, Key Vault, managed identity, OIDC-based CI/CD.
- Messaging target for future distributed work should align with Azure-native patterns already used in this project; do not introduce RabbitMQ unless an ADR explicitly justifies replacing the Azure direction.
- Frontend is React + Vite, not Angular.

Non-negotiable architecture constraints:
- Preserve Clean Architecture boundaries: Domain and Application must not reference EF Core, Azure SDKs, HTTP clients, or Infrastructure.
- Preserve tenant routing authority: Tenant.PaymentProviderCode is the only payment-provider routing authority.
- Preserve TenantRegistryDbContext as the tenant resolution source. Never resolve tenants through the business DbContext.
- Preserve webhook inbox/idempotency behavior from ADR-020.
- Preserve payment provider behavior: Razorpay Use3DSecure=false; OpenPay Use3DSecure=true.
- Treat DW-016 as active: payment amount/currency must become order/invoice-owned during Payments module extraction.
- Phase 9 starts with module isolation first, service extraction second. Do not assume every module becomes an independently deployed microservice immediately.

Required output structure:

========================
PHASE 1 - REPOSITORY-AWARE SYSTEM ANALYSIS
========================

Analyze the current monolith-to-microservices transition strategy.

Identify:
- bounded contexts and module candidates
- initial module boundaries
- which modules should remain in-process first
- which modules are candidates for future independently hosted services
- shared kernel concerns versus module-owned concerns
- synchronous public API contracts between modules
- future asynchronous integration event opportunities
- database ownership and schema ownership
- YARP gateway role for local modular routing and future service routing
- configuration, tenant resolution, and payment routing constraints
- observability, logging, and health/readiness requirements
- testing and migration risks

Use these expected module candidates unless the repository evidence suggests otherwise:
- Orders
- Payments
- Tenants
- Inventory, if currently represented by the domain
- SharedKernel/platform concerns

For each module provide:
- responsibility
- owned entities/data
- owned database schema
- public API contracts required by other modules
- internal APIs that must not be consumed directly
- commands/queries likely owned by the module
- events published later
- events consumed later
- dependencies allowed through PublicApi only
- extraction priority and risk level

========================
PHASE 2 - ADR-021 DESIGN
========================

Draft ADR-021 titled:
YARP Module Isolation Strategy for Microservices Architecture

Use this structure:
- Status
- Context
- Problem Statement
- Decision
- Options Considered
- Proposed Solution
- Constraints
- Risks and Mitigations
- Consequences
- Validation Strategy
- Next Steps
- Related Decisions

The ADR must explicitly state:
- Phase 9 begins as a modular monolith/module-isolation effort.
- YARP routes HTTP traffic to host boundaries, not class-library modules.
- In-process modules communicate through .PublicApi contracts.
- Independently hosted module APIs may be introduced only after module boundaries and tests are stable.
- Orders owns order amount/currency; Payments owns payment attempts, provider references, webhook inbox behavior, and payment status transitions.
- Tenants owns tenant registry and payment-provider routing authority.
- Shared database schemas are temporary migration bridges only, not target ownership.

========================
PHASE 3 - IMPLEMENTATION BLUEPRINT FOR QWEN 14B
========================

Prepare implementation instructions for Qwen 14B.

Do not generate full application code. Produce a step-by-step blueprint optimized for a developer model to execute safely.

For each initial module, provide:
- project names following the existing repository naming style
- recommended project references
- folder structure
- PublicApi interfaces and DTO names
- module DI registration pattern, for example AddOrdersModule()
- owned DbContext or schema strategy
- migration approach
- controller/API impact
- gateway routing impact
- tests to add or update
- validation command recommendations

Preferred project naming pattern:
- XYDataLabs.OrderProcessingSystem.Orders.PublicApi
- XYDataLabs.OrderProcessingSystem.Orders.Domain
- XYDataLabs.OrderProcessingSystem.Orders.Application
- XYDataLabs.OrderProcessingSystem.Orders.Infrastructure
- XYDataLabs.OrderProcessingSystem.Payments.PublicApi
- XYDataLabs.OrderProcessingSystem.Payments.Domain
- XYDataLabs.OrderProcessingSystem.Payments.Application
- XYDataLabs.OrderProcessingSystem.Payments.Infrastructure
- XYDataLabs.OrderProcessingSystem.Tenants.PublicApi
- XYDataLabs.OrderProcessingSystem.Tenants.Domain
- XYDataLabs.OrderProcessingSystem.Tenants.Application
- XYDataLabs.OrderProcessingSystem.Tenants.Infrastructure

Architecture tests must be added early to enforce:
- PublicApi projects do not reference Infrastructure.
- Domain projects do not reference Application or Infrastructure.
- Application projects do not reference Infrastructure.
- Module internals are not referenced directly across modules.
- Cross-module dependencies use .PublicApi contracts only.

YARP guidance:
- Use the existing Gateway project.
- Use standard YARP configuration shape under ReverseProxy:Routes and ReverseProxy:Clusters.
- Do not use invalid pseudo-route config such as a route key named /api/orders/* with Destination directly under the route.
- During module isolation, the gateway may continue routing to the existing API host until independently hosted module APIs exist.

Testing guidance:
- Start with one low-risk vertical slice.
- Prefer Tenants or Orders before Payments.
- Run focused tests after each slice.
- Keep integration tests passing before moving to the next module.
- Payment/webhook behavior must be regression-tested before and after Payments extraction.

Final output must clearly separate:
- Architecture assessment
- ADR-021 draft
- Qwen implementation handoff
- Risks requiring stakeholder validation
