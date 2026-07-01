# Azure Learning Curriculum - Navigation Guide

Canonical curriculum navigation for the learning track.

## Primary Documents

- `1_MASTER_CURRICULUM.md` — active source of truth for daily curriculum execution
- `docs/learning/curriculum/README.md` — canonical navigation and status guide
- `../implementation-notes/implementation-notes-days-29-38.md` — detailed implementation evidence for curriculum days 29-38
- `../implementation-notes/implementation-notes-days-51-56.md` — detailed implementation evidence for the Phase 8 event-foundation closeout slices
- `../implementation-notes/implementation-notes-days-57-59.md` — detailed implementation evidence for Phase 8.5 multi-provider payment closeout
- `../implementation-notes/implementation-notes-days-60-64.md` — detailed implementation evidence for Phase 8.7 provider webhook closeout
- `../reference/containerization-aca-aspire-learning-path.md` — supporting learning material for Docker, ACR, ACA, and Aspire

## Working Usage

1. Open `1_MASTER_CURRICULUM.md` in this folder.
2. Complete the current day tasks and update checklist status there.
3. Use `docs/internal/AZURE-PROGRESS-EVALUATION.md` for milestone-level tracking.
4. Record detailed implementation evidence in the matching implementation-notes file for the active day range.

## Learning Shape

- Core path: Azure basics, API design, Service Bus/Event Grid/Functions, microservice communication, Docker, Aspire, and Azure operations.
- Optional path: Cosmos DB, PostgreSQL pilot, Keycloak portability, advanced orchestration, search, real-time UI, and packaging.
- Rule: do not treat every advanced topic as mandatory; only move the optional path forward after the core path feels solid.
- Principal-architect rule: prefer a smaller number of well-justified enterprise capabilities over copying a large starter kit wholesale.

## Current Learning Status

- Completed: Days 1-43, Architecture Phases 1-8.7, Phase 8.5, Phase 8.6, and Track U U5 web cutover
- Current: Phase 8.7 closed (June 6, 2026); Phase 9 closeout is verified complete and the next backend phase is Phase 10
- Next: Phase 10 Azure transport + DLQ operations behind hard entry gates, followed by Phase 11 autonomy, Phase 11.5 portability, Phase 12 platform engineering, Phase 13 Aspire deepening, and Phase 14 read-model maturity in that order
- Roadmap note: `.NET 10` is planned as a Phase 12 assessment with a Phase 13 go/no-go gate, not as a Phase 10 deliverable
- Companion planning surface before payment automation implementation: `docs/guides/development/payment-journey-automation-blueprint.md`

Last Updated: July 1, 2026
Current Focus: Phase 10 — Azure Transport + DLQ Operations (Service Bus, Event Grid, Azure Functions, communication rules, and operational hardening first; ACA as the hosting outcome)

