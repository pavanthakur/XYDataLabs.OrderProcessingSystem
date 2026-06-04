# Azure Learning Curriculum - Navigation Guide

Canonical curriculum navigation for the learning track.

## Primary Documents

- `1_MASTER_CURRICULUM.md` — active source of truth for daily curriculum execution
- `docs/learning/curriculum/README.md` — canonical navigation and status guide
- `../implementation-notes/implementation-notes-days-29-38.md` — detailed implementation evidence for curriculum days 29-38
- `../implementation-notes/implementation-notes-days-51-56.md` — detailed implementation evidence for the Phase 8 event-foundation closeout slices
- `../implementation-notes/implementation-notes-days-57-59.md` — detailed implementation evidence for Phase 8.5 multi-provider payment closeout
- `../reference/containerization-aca-aspire-learning-path.md` — supporting learning reference for Docker, ACR, ACA, and Aspire

## Working Usage

1. Open `1_MASTER_CURRICULUM.md` in this folder.
2. Complete the current day tasks and update checklist status there.
3. Use `docs/internal/AZURE-PROGRESS-EVALUATION.md` for milestone-level tracking.
4. Record detailed implementation evidence in the matching implementation-notes file for the active day range.

## Current Learning Status

- Completed: Days 1-43, Architecture Phases 1-8, Phase 8.5, and Track U U5 web cutover
- Current: Phase 8.5 closed (May 31, 2026); Phase 8.7 provider webhook receiver is the active next backend phase
- Next: Phase 8.7 signed provider webhooks, Phase 9 module extraction plus Aspire-Lite, Phase 9.5 Keycloak portability, and Phase 10 Azure transport + DLQ operations behind hard entry gates
- Companion planning surface before payment automation implementation: `docs/guides/development/payment-journey-automation-blueprint.md`

Last Updated: May 31, 2026
Current Focus: Phase 8.7 — Provider Webhook Receiver (HMAC signature validation, inbox idempotency, tenant resolution from metadata)
