# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 12 November 2026

- Historical acceptance candidate: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`), clean at E2E/NFR start and finish. Current work is on a later `dev` candidate and does not inherit the historical Docker acceptance; verify Git state.
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

- P0–P2 cost/retention batch is implemented in the working tree at base `84419a87`. P1 changes ACR cleanup to manual inventory-only, adds a fail-closed six-repository digest planner including Payments, protects active and verified rollback digests, and adds fixture tests. The workflow checks platform ACR ownership, active revision inventory shape, and digest-qualified active refs; it parses as YAML and cannot delete manifests. P2 adds read-only cost/storage snapshots and offline comparison for resource/service costs, Container Apps replicas, ACR usage, Log Analytics ingestion, SQL storage, and Functions host storage. No Azure queries or writes were run for this batch. Prior local validation was 64 Node script tests, AI customization validator, documentation links (197), environment-contract validator (187), and `git diff --check`; rerun before committing.
- P0 budget is now owner-created and read-back verified: ₹5,000 monthly subscription budget on the subscription ending `980c`, 50% actual-cost alert, one email recipient, expiry `2028-10-31`; owner accepted this setup. It is an alert, not a spending cap. The 35-hour maximum live window remains. Run owner, start/teardown time, cleanup approver and evidence location are still TBD, so deployment is not yet ready.
- At start of the repository-only work, `dev` was clean at `3520c6d960604677c9f4c538ce87bcb4712f8f03`. The Azure-dev generated-URL bootstrap and associated workflow/catalog/validation edits passed local checks. Verify the resulting Git revision and remote state before claiming hosted acceptance or an image identity.
- Read-only Azure-dev preflight selected the Pay-As-You-Go subscription ending `980c`, confirmed by the owner. No resource groups were visible in that subscription; required providers were registered and Central India ACA quota reported 0/20 managed environments, 0/300 sandbox cores. GitHub OIDC dev federation exists, but secret values/effective role-assignment permission are unverified. Entra variables are absent. `xydatalabs.com` did not resolve and Verisign RDAP returned 404 at inspection time. No live Azure what-if, resource write, provider transaction or deployment was performed.
- Owner chose generated ACA URLs for dev only. The code adds a dev-only, dry-run-default hostname bootstrap for RG/Log Analytics/ACA environment; extracts the ACA environment Bicep module for reuse; leaves generated hostnames out of `runtime-targets.json`; checks live Gateway/UI FQDN and exact Entra UI origin in dev workflows. Staging/prod retain custom-domain policy. Final local checks passed: both Bicep builds, six workflow YAML parses, 16 static/resolver tests, 2 catalog tests, 9 hosted-CI contract tests, TypeScript check, 187 environment-contract checks, AI customization, doc links and `git diff --check`. These are static/local results, not Azure execution.
- This is repository-only work. ACR publication, Entra/RBAC changes, Azure what-if and deployment, runtime/payment/Functions acceptance and rollback are still NOT-RUN and each requires scoped approval. Historical Docker/L6 evidence remains bound only to `494ab4fd`. Staging acceptance is a required operator gate before production but is not machine-enforced.

## Next action

Next: review and commit the P0–P2 repository changes; then complete the deployment run record (owner, time window, cleanup approver, evidence location). Before deployment, publish a reviewed candidate and verify hosted CI on that exact SHA. Azure deployment remains separately approval-gated.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
