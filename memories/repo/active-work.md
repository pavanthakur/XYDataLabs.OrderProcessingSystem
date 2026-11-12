# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 12 November 2026

- Acceptance candidate: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`), clean at both E2E and NFR start/finish. Current branch tip before Checkpoint A work was `fb3e74ad`; the worktree now contains uncommitted CI-hardening changes. Verify Git before binding any new evidence.
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

- Current implementation commit: `e5d9bc8bd43c7745b645dafd7ea569dfa32efff5` (`Support immutable Phase 10 release promotion`); final branch-sync handoff update: `2356ec9ff0fff0d8b2a2806248dd41c0b47cb443`. Release promotion distinguishes source and deployment workflow SHAs, validates source/target CI evidence and ancestry, and checks runtime URL contracts. The earlier release pipeline, six digest-qualified images, Functions package, dedicated Functions StorageV2 + user-assigned managed identity, read-only preflight and dry-run default remain in place; the owner selected Storage + managed identity. None of these resources has been provisioned.
- Promotion distinguishes immutable artifact source SHA from target deployment-workflow SHA. It checks source ancestry, environment/branch policy, successful hosted checks and CI evidence packets on both exact revisions; it does not rebuild or relabel images. Offline tests reject unrelated commits, unapproved branches and missing/failed evidence. Runtime-target validation rejects local/emulator/Windows and unapproved generated-host URLs.
- Local checks on this candidate: 33 Phase 10 release/preflight tests, 9 hosted-CI contract tests, 185 environment-contract checks, workflow YAML parsing, documentation links, AI customization and `git diff --check` passed. Hosted exact-SHA checks: [CI 43150694052](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43150694052), [Drift 43150694060](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43150694060), [AI Prompts 43150694049](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43150694049), and [Documentation Links 43150694169](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43150694169) passed. [ADR 43150694328](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/43150694328) was skipped by opt-in policy. No Docker, provider, Azure, directory, ACR or deployment operation was performed.
- Authorized branch sync is complete: the release implementation and follow-up status/documentation commits are synchronized from `dev` to `staging` and `main`, preserving target-only history. Exact-SHA CI, Drift Scanner, AI Customization and applicable Documentation Links checks passed for the pushed revisions; ADR validation was skipped by configured opt-in policy. Pushes triggered validation, not Azure deployment. Production staging-acceptance evidence is not machine-enforced by the release verifier; it remains a required operator gate.
- Azure OIDC/RBAC, permissions, quotas, cost, domain ownership, live service readiness, deployed identity/payments/transport and rollback remain unverified/NOT-RUN. Historical Docker/L6 PASS is limited to `494ab4fd`; it does not certify this candidate or Azure.

## Next action

For the next material change, verify exact-SHA hosted checks and clean/synchronized refs. Keep Azure actions separate: live inspection, ACR publication, Bicep what-if, billable resource creation, deployment and payment tests require their own scoped approvals.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
