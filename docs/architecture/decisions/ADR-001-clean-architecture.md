# ADR-001: Clean Architecture with DDD Layers

**Date:** 2024-12-01  
**Status:** Accepted  
**Deciders:** Project architect

---

## Context

Building a .NET 8 order processing system that will grow over time — starting as a monolith, evolving toward microservices and ACA. Need a layer structure that:
- Keeps business rules independent of frameworks and infrastructure
- Makes unit testing possible without a database or HTTP
- Supports future extraction of microservices without rewriting domain logic

## Decision

Adopt Clean Architecture with four projects mirroring the dependency rule:
- **Domain** — entities, value objects, domain events. Zero external dependencies.
- **Application** — use cases (MediatR commands/queries), interfaces, DTOs. Depends only on Domain.
- **Infrastructure** — EF Core, SQL Server, external adapters. Implements Application interfaces.
- **API / UI** — ASP.NET Core entry points. Wire everything together via DI.

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Clean Architecture | Testable, framework-agnostic domain, clear dependency rule | More projects, more ceremony for small features | ✅ Selected |
| Layered / N-Tier | Simple, familiar | Domain coupled to persistence, hard to test | ❌ Rejected |
| Vertical Slices only | Fast for CRUD | Hard to share domain rules across slices | ❌ Rejected for now |

## Consequences

**Positive:**
- Domain and Application layers test without mocking EF Core or HTTP
- Infrastructure can be swapped (SQL → Cosmos DB) without touching business logic
- MediatR pipeline decorators add cross-cutting concerns (validation, logging) cleanly

**Negative / Trade-offs:**
- More boilerplate: DTOs, mapping profiles (AutoMapper), interface duplication
- Newcomers need to understand the dependency rule before being productive

**Future obligations:**
- Keep Application layer free of `using Microsoft.EntityFrameworkCore` or `using Azure.*`
- All Azure SDK calls go in Infrastructure or dedicated Adapters (e.g. OpenPayAdapter)

## Related
- ADR-004: EF Core for data access (Infrastructure layer implementation detail)
- ARCHITECTURE-EVOLUTION.md — Phase 1 (monolith) → Phase 2 (YARP microservices)
