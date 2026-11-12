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

- User-approved Phase 10 Azure-readiness implementation is in progress on `dev` at base `4d929805eed1227285cd02a04fd7873ca95210c9`; current worktree is dirty. Do not treat hosted checks on that base SHA as validating these edits.
- Implemented in the worktree: immutable six-image + Functions package release manifest, exact-run/hosted-evidence verifiers, deployment identity hash, read-only Azure subscription/RBAC/provider preflight, and Bicep changes for dedicated Functions host StorageV2 + user-assigned managed identity. User selected this storage design. No Azure provisioning, ACR publication, deployment, payment, commit or push has occurred.
- Local validation now passes on the dirty worktree: Phase 10 scripts 28/28; hosted-CI contract 9/9; environment contract 185/185; AI-customization validator; documentation links 197/197; all workflow YAML parsed without syntax/duplicate-key errors; all `scripts/**/*.mjs` passed `node --check`; Phase 10 Bicep compiled; JSON parameters parsed; `git diff --check` passed. These are local structural/contract checks, not live Azure validation or hosted CI for these edits.
- The manual Azure orchestrator now defaults `dryRun=true`. Functions package verification checks the exact HTTPS SCM hostname, disallows redirects, uses a bounded request timeout, and compares mounted ZIP bytes to the selected release hash.
- Review blocker: release branch/environment equality and workflow-SHA equality prevent reuse of one immutable artifact across dev→staging/main after merges change SHA. Documented as unresolved; do not bypass the guards or claim promotion readiness.
- Functions host-storage identity needs target-scope `Microsoft.Authorization/roleAssignments/write`; live effective permission and target SKU cost are not verified. A separate user-approved Azure preflight/deployment gate is still required.
- Historical Docker/L6 PASS remains limited to candidate `494ab4fd`; L6 C under DW-028 Option A is closed for that candidate only. Phase 10 Azure stages are NOT-RUN.

## Next action

Complete local validation of the current worktree, correct any remaining workflow/documentation defects, then review the diff and report the precise Azure blockers. Azure workflows, ACR publication, provisioning, deployment, payment matrix, commit/push, and branch merges remain separate actions; do not start them automatically.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
