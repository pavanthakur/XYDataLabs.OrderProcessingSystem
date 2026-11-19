# Active Work

Session navigation, not proof. Verify Git, runtime and evidence before acting.

## Latest checkpoint — 19 November 2026

- Review revision: `1fba2df2`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `TenantA/B/C payments, current-candidate NFR/operations/recovery/rollback/persistence/replay; Azure excluded`
- Evidence reference: `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-final003/local-followup.json`
- Review base: `1fba2df2c634cd4786c0c8dfc24cb7b299dd34b7` on `dev`. The seven-file delta is limited to reporting/tests and checkpoint documentation; no application source or image changed. Verify current HEAD and publication state directly; this handoff does not assert Git or hosted-CI completion.
- `Worktree state: DIRTY` describes the evidence snapshot, not current live Git state; verify with `git status` before acting.
- Latest local reconciliation: `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-final003/local-followup.json`. It records image/source compatibility, payment evidence, NFR, operations/recovery, rollback, persistence, Functions/replay and artifact integrity separately. Overall remains **INCOMPLETE**, not full Phase 10 PASS.
- Docker E2E run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-211313195/`: deterministic positives 6/6, real sandbox positives 6/6, and Razorpay failure/cancellation 6/6 passed across TenantA/B/C × both providers. Provider confirmation, SQL/order correlation and exact fixture restoration passed. Do not repeat successful charges just to refresh evidence.
- Current-candidate no-charge tests: targeted NFR profile passed functional, 100-message performance, tenant, payment-integration, and security/identity checks; its standalone result is partial because the dynamic payment matrix was explicitly skipped. Operational-only profile passed 100/100 effects/inbox in burst and consumer-outage recovery, zero losses/duplicates, 32.259 s recovery, exact consumer restoration, retained-image Inventory rollback and current-image restoration. The combined report reconciles these distinct profiles.
- Docker Desktop restart persistence passed: known tenant/order rows, named SQL volume and all image identities persisted; native SQL listener was unchanged. All 13 `xy-phase10` containers are running. No reset, prune, Azure operation, native SQL change, or F: recovery occurred. F: retained storage was deleted earlier and is not recoverable.
- Reporting correction: clean image manifests must encode `changedPaths: []`; legacy `null` is normalized only for clean manifests. Dirty manifests still fail closed. Tool/report-only working-tree changes can be distinguished from application changes; application edits remain blocked. Latest checks passed: local-follow-up 21/21, report 39/39, PowerShell image-evidence 8/8, AI customization, docs links, and `git diff --check`. OpenPay NU1701 compatibility warning remains.
- Remaining: OpenPay sandbox challenge-negative capability is unverified/BLOCKED; order continuation/recovery remains deferred under DW-023/DW-024; Azure acceptance is NOT-RUN. These are not local baseline payment failures. Phase 10 is not closed.
- Next: verify hosted checks against the exact published SHA, then decide whether to begin the separately approval-gated Azure stage. Do not submit more payments, deploy Azure, reset data, prune Docker, or delete additional storage without scoped approval.

Canonical plans: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored; preserve them.
