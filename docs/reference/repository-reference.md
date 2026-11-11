# Repository Reference Guide

This page is the current orientation guide for `XYDataLabs.OrderProcessingSystem`. It replaces the former large Copilot inventory without making the always-loaded Copilot entry point responsible for maintaining a duplicated project, workflow, or phase table.

## Repository Purpose

This is a .NET 8 multi-tenant order-processing platform with Clean Architecture, hand-rolled CQRS, payment-provider integrations, React frontend applications, payment automation, and Azure deployment tooling.

The repository is also a learning and engineering practice project. Architecture, deployment, and acceptance claims must be supported by the current code, approved plan, and revision-bound evidence. Historical reports and the repository handoff are navigation, not current acceptance proof.

## Architecture Map

The primary .NET layers are:

- **Domain** — entities and domain rules with no infrastructure dependency.
- **Application** — CQRS commands, queries, handlers, DTOs, validators, and abstractions.
- **Infrastructure** — EF Core, persistence, migrations, external integrations, and data access.
- **API/Hosts** — composition roots, controllers, middleware, and bounded-context hosts.
- **SharedKernel** — `Result<T>`, errors, API envelopes, observability, and cross-cutting primitives.
- **Gateway** — YARP routing and gateway host behavior.
- **Payments** — payment features, contracts, infrastructure, OpenPay, and Razorpay adapters.
- **Orders, Inventory, Notifications, and Tenants** — bounded-context projects and hosts.

The solution file is the authoritative project inventory. Do not copy a manually maintained complete project table into always-loaded AI instructions. Use `dotnet sln XYDataLabs.OrderProcessingSystem.sln list` when the current project list is required.

## Frontend And Automation Workspaces

- `frontend/apps/web` — React, Vite, TypeScript web application.
- `frontend/packages/api-sdk` — shared API client contracts and client implementation.
- `frontend/packages/tenant-session` — runtime tenant bootstrap and tenant header behavior.
- `automation/` — payment journey execution, browser tests, provider fixtures, verification adapters, reports, and runtime-target catalogs.

The frontend workspace currently exposes these root commands from `frontend/`:

```powershell
npm run typecheck
npm run test:web
npm run build
```

The owning package files and CI workflow are authoritative if these commands change.

## Directory Ownership

| Area | Canonical owner | Use it for |
|---|---|---|
| Shared AI behavior | `AGENTS.md` | Engineering rules, evidence, and approval boundaries |
| Copilot routing | `.github/copilot-instructions.md` | Short Copilot-specific entry point |
| AI operating model | `docs/AI-OPERATING-MODEL.md` | Governance, ownership, routing, and validation |
| File-pattern rules | `.github/instructions/` | Language, architecture, frontend, migration, payment, and workflow rules |
| Reusable workflows | `.github/prompts/` | Explicit user-triggered operational workflows |
| Specialist workflows | `.github/skills/` | Stable, repeated procedures requiring focused context |
| Role agents | `.github/agents/` | Backend, review, and Azure role behavior |
| Architecture intent | `ARCHITECTURE.md` and `docs/architecture/decisions/` | Binding architecture constraints and ADRs |
| Human documentation | `docs/` | Guides, references, runbooks, curriculum, and internal tracking |
| Phase scope | Approved phase plans under `docs/internal/` | What work is approved or paused |
| Session checkpoint | `memories/repo/active-work.md` | Concise continuation state and evidence limits |
| Runtime targets | `automation/config/runtime-targets.json` | Configured local, Docker, and Azure target metadata |

## AI Development Routing

Start with `AGENTS.md`, then read only the applicable route:

- Backend/CQRS: `.github/skills/cqrs-backend-implementation/SKILL.md` and `.github/instructions/clean-architecture.instructions.md`.
- Tenant or payment work: `.github/skills/payment-provider-development/SKILL.md` and `.github/instructions/multitenant-payment-schema.instructions.md`.
- React or TypeScript work: `.github/skills/frontend-feature-development/SKILL.md` and `.github/instructions/frontend.instructions.md`.
- Azure or deployment automation: `.github/skills/azure-deployment-operations/SKILL.md` and `.github/instructions/azure-workflows.instructions.md`.
- Code review: `.github/skills/code-review-guardrails/SKILL.md`.
- Context drift: `.github/skills/context-audit-governance/SKILL.md` and `/XYDataLabs-context-audit`.
- Task closeout: `.github/skills/completion-check-governance/SKILL.md` and `/XYDataLabs-completion-check`.
- End-to-end feature flow: `/XYDataLabs-new-feature`, which classifies backend, frontend, full-stack, and payment-provider scope before implementation.

The complete prompt and skill indexes are the discovery authorities. Native client discovery is separate from explicit routing and must be observed before it is claimed as working.

## Validation Lanes

Use the narrowest safe validation for the changed area:

- Shared AI assets: `pwsh -NoProfile -File scripts/validate-ai-customization.ps1`.
- Documentation links: `node scripts/validate-doc-links.js` when `docs/` changes.
- Diff hygiene: `git diff --check`.
- Frontend: run the applicable `frontend/` typecheck, test, and build commands.
- .NET: build and run the affected test project first; broaden only when required by the approved scope.
- Azure runtime contract: `pwsh Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` when Azure runtime-target or deployment automation changes.
- Full PR CI behavior is defined by `.github/workflows/ci.yml`; local success is not hosted-CI evidence.

Missing approval, unavailable environments, or absent revision-bound evidence must be reported as `BLOCKED`, `NOT TESTED`, or `EVIDENCE UNAVAILABLE`, not as PASS.

## Azure Runtime-Target Convention

For Phase 10 and later automation, `automation/config/runtime-targets.json` owns configured target metadata. Stable configured names and approved public custom domains may be recorded there. Generated Container Apps hostnames, revision suffixes, random suffixes, GUID-like discovery values, and one-run outputs must not be committed to the catalog.

When adding or renaming an automation-visible runtime dependency, update the runtime-target catalog, its TypeScript contract when needed, the owning workflow or script, and the Phase 10 environment-contract validator together. Read the Azure workflow instructions and Azure skill before changing this area. This guidance does not authorize deployment.

## Safety And Approval Boundaries

Repository inspection is read-only by default. Edits and safe targeted tests must fit the approved scope. Database mutations, Docker lifecycle or resets, payment transactions/refunds, Azure or directory changes, and Git writes require explicit scoped approval. Do not stage, commit, push, merge, tag, create branches, or resume a paused phase automatically.

Never place credentials, private keys, raw card data, CVV, connection strings with credentials, or sensitive provider payloads in source, prompts, memory, reports, or documentation.

## Maintenance Rules

- Keep this page orientation-focused and link to canonical owners instead of copying their full bodies.
- Use live solution, workflow, package, and runtime-target files for inventories.
- Update this page when ownership, routing, validation lanes, or stable repository boundaries materially change.
- Do not use it as a phase tracker, acceptance report, deployment runbook, or replacement for an ADR.
- Refresh the existing handoff only after material approved work or a verified checkpoint change.
