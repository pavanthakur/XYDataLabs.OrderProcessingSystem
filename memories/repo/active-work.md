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

- Release promotion on the committed baseline includes full-SHA release building, six digest-pinned images, Functions ZIP/package hash, exact producer-run/artifact and hosted-evidence checks, source-to-deployment ancestry, environment mapping, a dedicated Functions StorageV2 account + user-assigned identity, and a shared non-cancelling Actions lease. Storage + managed identity was selected; no Azure resource has been provisioned.
- Commit `0b9e97c56905f04e8234703a89d375a220af847d` adds offline tests for arbitrary shared/dedicated tenant discovery, fail-closed Azure discovery, repeated missing-only seed preservation, environment/suffix mapping and Entra scope/audience. It registers tenant-catalog tests in hosted CI. No live runtime was accessed.
- Local checks passed: release/identity/static-preflight 38 tests; tenant catalog 4/4; Application.Tests 80/80; Docker safety 45/45; environment contract 185/185; hosted-CI contract 9/9; payment/evidence/report suites 43/43; local Bicep compilation; AI customization/doc-link validators; `git diff --check`. Release solution build succeeded with 174 warnings and no errors, including existing OpenPay `NU1701` warnings.
- Exact-SHA hosted checks passed on `dev` (CI 43164671576; docs 43164671593; AI customization 43164671552; prompts 43164671726; drift 43164671539), `staging` merge `e35da419338d21b636c6415d3c8cc09233590023` (CI 43165496815; docs 43165496775; AI customization 43165496713; prompts 43165496845; drift 43165496703) and `main` merge `c14d721fc8b790be5c213647fe11e1ec32d546d6` (CI 43165517250; docs 43165517293; AI customization 43165517281; prompts 43165517432; drift 43165517265). ADR was skipped by opt-in policy on each.
- Docker acceptance/L6 evidence remains historical and bound only to `494ab4fd`; it does not certify the current candidate. Azure identity/RBAC/quotas/cost, ACR publication, live `what-if`, deployment, runtime, payments, Functions invocation and rollback remain NOT-RUN. Staging deployment acceptance is not machine-enforced before production promotion.

## Next action

Continue repository-only Checkpoint B review, especially the production-promotion gap: staging deployment acceptance is not machine-enforced. Checkpoint C/D live Azure preflight and acceptance remain NOT-RUN and separately approval-gated. Keep `dev` as the working branch.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
