# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 11 November 2026

- Review revision: `58c361a`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `58c361a`
- Evidence environment: `LOCAL DOCKER DESKTOP`
- Evidence scope: `historical E2E/NFR image identity is unproven; implementation runtime not tested`
- Evidence reference: `TestResults/Phase10/accepted/phase10-preazure-image-evidence-58c361a9.json`
- Base revision: `58c361a9d0c594da604c0a274204c8dbb72090ea` (`dev`). The E2E/NFR runs below were clean at that revision. This checkout is now **DIRTY** from the Phase 10 image-integrity implementation; do not bind new acceptance to the base SHA.
- Earlier accepted Docker summary at `f2bd3587` remains historical and unchanged. Gate A/C evidence is on `3659a743`; no single unified L6 candidate is claimed.
- E2E `phase10-docker-http-20261111-103838867` and NFR `phase10-docker-nfr-20261111-102444152` passed under the former completion-v3 / reconciliation-v1 contract. E2E covered six deterministic and six sandbox positives across TenantA/B/C and Razorpay/OpenPay. NFR: 100 messages/effects; P95 2.16305 s (30 s limit); replay 1.085 s (60 s); recovery 28.027 s (1,800 s); zero lost/duplicate effects; local rollback/restore.
- The old reconciler did not compare images. E2E start rollback evidence and the NFR retained-image log record Inventory image `d619aefc…`; a supplemental E2E image inventory recorded `926ef950…` after E2E completed, without a candidate SHA and outside the v3 completion hashes. Treat same-image proof as **BLOCKED**, not as a Docker PASS or FAIL. Sanitized record: `TestResults/Phase10/accepted/phase10-preazure-image-evidence-58c361a9.json`.
- Current changes fix Gateway/Functions Docker restore inputs and add automatic 13-service image manifests, completion-v4 integrity, image-aware preview/reconciliation and tests. Focused code checks are recorded in the current implementation summary. A forced local Gateway publish resolved central package versions and NuGet audit found no vulnerable packages; this is not Docker image proof. Existing S1694/CA1062/MA0074 analyzer warnings and Openpay 1.0.25 NU1701 are recorded for disposition; none were suppressed. No Docker runtime rerun has exercised these changes. Historical image package versions remain UNKNOWN.
- Runbook now labels the prior NFR-first order as historical and documents the pending v4 sequence: E2E, NFR against its exact image manifest, then explicit run-directory reconciliation. Documentation links pass; no runtime acceptance was run.
- Phase 10 is **not complete**. Azure stages are NOT RUN. DW-028 Option A remains accepted (workflow 99 local/manual; hosted parity excluded). DW-027 remains BLOCKED/NOT TESTED. DW-023/DW-024 remain Phase 11 deferrals. OpenPay visible 3DS and Razorpay S2S are uncertified.

## Next action

Review the uncommitted implementation diff and safe-test packet. Before acceptance, get separate scoped authorization for Git candidate creation/push and for Docker cold build, E2E/payment acceptance, NFR, and persistence/recovery operations. Freeze one clean candidate, cold-build once, pass its E2E image manifest to NFR, then reconcile v4 evidence. Do not rerun payments solely to refresh documentation; never retry an ambiguous charge. Azure requires a later separate approval.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
