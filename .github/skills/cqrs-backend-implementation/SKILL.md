---
name: cqrs-backend-implementation
description: "Use when working on C# backend code in this repository: Domain entities, Application CQRS handlers, DTOs, Infrastructure data access, API controllers, migrations, or backend test coverage."
---

# CQRS Backend Implementation

Use this skill for repeatable C# backend feature and fix work in this repository.

## Scope

Use when the task involves any of the following:

- Domain entities, value objects, enums, or domain rules
- Application commands, queries, handlers, validators, or DTOs
- Infrastructure data access, DbContext changes, EF Core mappings, or migrations
- API controllers or backend composition-root changes
- Backend unit, integration, or architecture tests
- Clean architecture or CQRS compliance troubleshooting

Do not use this skill for:

- Azure deployment workflows, Bicep, or OIDC setup
- UI-only work in `frontend/`
- Documentation-only changes outside backend architecture decisions

## Required References

Open the relevant sources before changing backend behavior:

- `.github/instructions/clean-architecture.instructions.md`
- `.github/instructions/multitenant-payment-schema.instructions.md` when the change touches payment or tenant-owned data
- `.github/instructions/ef-migrations.instructions.md` when Infrastructure or migrations change
- `.github/agents/cqrs-backend.agent.md`
- `.github/prompts/XYDataLabs-new-feature.prompt.md` when the task is an end-to-end feature flow
- `ARCHITECTURE.md` when the change adds a new model or architectural constraint

## Operating Rules

1. Keep clean architecture boundaries intact.
   - Domain has zero infrastructure dependencies.
   - Application defines use cases and abstractions, not infrastructure implementations.
   - Infrastructure implements persistence and external integrations.
2. Use the repo's hand-rolled CQRS pattern.
   - `ICommand<T>` / `IQuery<T>`
   - `ICommandHandler<,>` / `IQueryHandler<,>`
   - `IDispatcher` instead of MediatR
3. Use `Result<T>` for expected failures.
   - Do not rely on exceptions for normal validation or not-found flows.
4. Preserve tenant safety.
   - Tenant-owned entities require `TenantId`.
   - Resolve tenant context via the approved provider path.
5. Never store raw payment card data.
   - Preserve masking and tokenized data rules.
6. Keep migrations and model changes together.
   - If schema changes, update the owning mappings and migration assets in the same change.

## Recommended Execution Flow

1. Classify the task.
   - Domain rule change
   - CQRS feature or fix
   - Persistence change
   - Controller/API change
   - Test gap or architecture guard
2. Identify the narrowest owning slice.
   - Domain entity or rule
   - Application handler or DTO
   - Infrastructure mapping or migration
   - API endpoint
3. Apply the smallest architecture-safe change.
4. Validate the touched slice first.
   - Targeted unit or integration tests for the changed feature
   - Focused build or test for the touched project when no narrower test exists
5. If the change is part of a new feature, keep the end-to-end flow aligned with `/XYDataLabs-new-feature`.

## Common Checks

- If a handler returns plain values instead of `Result<T>`, treat that as the first defect.
- If a Domain or Application file imports infrastructure concerns, stop and repair the boundary.
- If a tenant-owned entity lacks `TenantId`, treat that as a schema and guardrail violation.
- If a payment-related model exposes raw PAN or CVV2, remove it and restore masking rules.
- If a schema change lacks a matching migration or mapping update, treat the persistence layer as incomplete.

## Validation Path

After backend changes, prefer the narrowest executable validation for the touched slice:

- Targeted test project runs under `tests/`
- Focused `dotnet test` for the changed backend project or scenario
- Focused build when a narrow test is not available
- `pwsh scripts/validate-ai-customization.ps1` when shared AI governance files changed

## Related Assets

- `.github/agents/cqrs-backend.agent.md`
- `.github/prompts/XYDataLabs-new-feature.prompt.md`
- `.github/prompts/XYDataLabs-completion-check.prompt.md`
- `tests/XYDataLabs.OrderProcessingSystem.Application.Tests/`
- `tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/`