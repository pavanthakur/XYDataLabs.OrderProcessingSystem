# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 12 November 2026

- Historical acceptance candidate: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`), clean at E2E/NFR start and finish. Current `dev` is `0b9e97c56905f04e8234703a89d375a220af847d`; the worktree is clean. This later commit does not inherit the historical Docker acceptance.
- Review revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Worktree state: `UNKNOWN`
- Verify Git state before continuing.
- Evidence revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `bounded non-Azure local Docker acceptance; not full Phase 10 or Azure acceptance`
- Evidence reference: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`
- Evidence status: `HISTORICAL`
- The pinned candidate's recorded verdict is **PASS, bounded non-Azure local acceptance**. Do not describe this as full Phase 10 closure or Azure acceptance.
- E2E: `phase10-docker-http-20261111-230915653`; NFR: `phase10-docker-nfr-20261111-234505649`; the v4 reconciler returned PASS with all 13 image identities equal. Sanitized tracked summary: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`.
- E2E passed cold build, foundations, smoke, isolated integration, identity, deterministic and sandbox journeys (TenantA/B/C × Razorpay/OpenPay), messaging/Functions, persistence after Docker restart, and settings restoration. Six positives per payment mode; six Razorpay failure/cancellation cases passed.
- NFR passed all categories: 100/100 messages/effects at 2.273 s P95; replay visibility 1.080 s; outage recovery 26.201 s, zero lost/duplicate effects; retained Inventory rollback and restore passed. L5-R HTML had no issues and measured backend, frontend, and integration coverage.
- L6 A passed on this candidate (42 architecture-invariant tests + 1 Gateway topology test). L6 B passed with bounded local evidence. L6 C passed under DW-028 Option A: Drift Scanner, AI Customization Windows/Linux, and Documentation Links passed on this SHA; workflow `99` hosted parity is excluded. See the checklist for action links and limits.
- L6 C is closed/PASS for `494ab4fd` under Option A; no corrective rerun is required for that candidate. Azure and the separate combined `l6-ci-parity-and-azure` report gate remain NOT-RUN; that combined gate is not non-Azure L6 C. Checkpoint A CI improvements do not reopen the accepted verdict or certify later candidates. DW-023/DW-024 remain Phase 11 deferrals. Fulfillment, installments, unresolved-payment recovery, visible OpenPay 3DS, Razorpay S2S, and ACA revision rollback remain uncertified.

## Current implementation checkpoint — 12 November 2026

- Docker acceptance/L6 evidence remains historical and bound only to `494ab4fd`; it does not certify the current candidate. Azure identity/RBAC/quotas/cost, ACR publication, live `what-if`, deployment, runtime, payments, Functions invocation and rollback remain NOT-RUN. Staging deployment acceptance is not machine-enforced before production promotion.
- Current branch heads: `dev` `e8433081a8256b68cd597473bcc8221adafca2a6`, `staging` `a3916ac2249912486df9c5d1cc2e4e6b16021564`, and `main` `becdaab42963382f54cf3110d031f0fefc7ef364`; each was synced to its origin and hosted CI, AI customization and Drift Scanner passed on its exact SHA. Documentation/prompt-specific checks passed on the earlier feature commits where applicable; ADR validation remained skipped by its opt-in policy.
- Repository-only B2 contract implementation and its offline validation are complete on the feature candidate `0b9e97c56905f04e8234703a89d375a220af847d`; the handoff-only `e8433081` update does not change runtime code. Checks included release/identity/static-preflight (38), tenant catalog (4), Application.Tests (80), Docker safety (45), environment contract (185), hosted-CI contract (9), payment/evidence/report (43), Bicep compilation, AI customization/doc links, and `git diff --check`. Release build succeeded with 174 warnings and no errors; existing warnings were not remediated here.
- Azure remains unverified: identity/RBAC/quotas/cost, ACR publication, live `what-if`, deployment, runtime, payments, Functions invocation and rollback are NOT-RUN. The chosen dedicated Functions StorageV2 + user-assigned managed-identity design is in IaC only; no resource has been provisioned. Staging acceptance is a required operator gate before production, but is not machine-enforced by the release verifier. Historical Docker/L6 evidence remains bound only to `494ab4fd` and does not certify the current candidate.

## Next action

Next: decide whether to implement a machine-enforced staging-acceptance evidence gate before production promotion. Checkpoint C/D live Azure preflight and acceptance remain NOT-RUN and require separate scoped approval; do not infer that the selected storage design authorizes provisioning or deployment. Keep `dev` as the working branch.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
