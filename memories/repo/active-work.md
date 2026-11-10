# Active Work

This is a session checkpoint, not proof of current runtime correctness. Verify material claims against the relevant plan, code and evidence. Historical details remain in Git history and the existing reports; do not replay old recovery instructions automatically.

## Checkpoint Provenance

- Review revision: `f2bd3587`
- Worktree state: `CLEAN`
- Evidence status: `CURRENT_PASS`
- Evidence revision: `f2bd3587`
- Evidence environment: `docker-dev`
- Evidence scope: `non-azure-local`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261111-024241244/phase10-acceptance-reconciliation.json`

## Last Session

- Updated: 2026-11-11. Branch `dev`. Non-Azure local acceptance **PASS** on one clean committed candidate `f2bd3587` (commits `5a117599`, `d84b9f60`, `0a5e4602`, `f2bd3587`; later commits are documentation only). Verdict from `npm --prefix automation run reconcile:phase10-acceptance` over E2E run `phase10-docker-http-20261111-024241244` and NFR run `phase10-docker-nfr-20261111-023057463`: sealed completion, foundations, smoke, integration, deterministic and sandbox payments (3 tenants x 2 providers), TenantC routing, messaging/Functions, persistence restart, restoration, L5-R report (no issues, all coverage measured), NFR categories, 100-message burst (P95 2.0 s), approved replay 1.07 s (limit 60 s), consumer-outage backlog recovery 26 s with 0 lost/0 duplicate (limit 30 min), and rollback executed and restored.
- Fixes made on the way: skipped/blocked NFR categories are `incomplete`, never `passed`; rollback prerequisite no longer blocks drills; non-ASCII test names broke discovery reconciliation (UTF-8 helper); `tenantc-routing-regression` is now derived from run evidence; report no longer flags integration bookkeeping JSON.
- Rollback proof scope: a locally built previous inventory image (`phase10-prev-290d0fba`, built from a clean export of `290d0fba`, provenance under `TestResults/Phase10/rollback-baseline/290d0fba/`) swapped in and restored. No application source differs from the base, so this proves the swap/restore mechanism and schema readiness, not a behavioural difference, and is not an ACA revision rollback.
- Not done: L6 CI parity (workflow `99`) and every Azure stage are NOT-RUN; DW-023 and DW-024 stay deferred to Phase 11. Nothing was pushed. `origin/dev` showed `d84b9f60` mid-session although no push was run from here; investigate before any push.
- DW-027 (controlled-client behavioral acceptance) remains open; AI-context token measurement is still byte-estimated.

## Verified Evidence And Limits

- The PASS covers only the `non-azure-local` scope on `f2bd3587`: it does not certify Phase 10 completion, Azure, CI parity, fulfillment, installments, unresolved-payment recovery, a visible OpenPay 3DS challenge or Razorpay S2S.
- Images are locally built (no registry digest); the candidate is identified by commit and local image IDs.
- Docs edits after `f2bd3587` change no code; rerun the reconciler if any code changes.

## Pending / Next Actions

1. Phase 10 closes only after L6 (architecture conformance, CI workflow `99` on a pushed SHA) and the separately approved Azure stages. Push and Azure need explicit approval.
2. Phase 11 (DW-023/DW-024) is separate: [plan](../../docs/internal/phase11-implementation-plan.md), [Deferred Work Log](../../docs/internal/DEFERRED-WORK-LOG.md).

## Recent Key Facts And Safety Boundaries

- Shared `dbo.Tenants` owns active tenant tier/provider routing. Provider settings live in each tenant's actual business database; the dedicated tenant-row copy is not routing authority.
- Local project SQL uses loopback port `14330`; native Windows SQL uses `1433` and must remain untouched. Verify project ownership and physical SQL identity before any separately approved database operation; do not reuse historical process IDs.
- Docker storage was verified on G: in earlier work, with named SQL storage. Reverify only when needed; never reset Docker just to resume or reconstruct context.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Historical pre-reset captured-currency mismatch disposition is **not established here**. See `TestResults/DockerStorage/fresh-playwright-20261109-1902/manual-currency-mismatch.md` and `TestResults/DockerStorage/order-continuation-review-20261109/review.md`. Old order/customer URLs may no longer identify the original records. Do not retry, refund, force Paid, alter currency or assume reset resolved provider-side history without a separate approved investigation.
- Keep original approved provider settings and sandbox/deterministic evidence distinct. Never blindly retry an ambiguous charge. Azure deployment/directory writes, resets, charges/refunds and Git writes require their explicit scoped approvals.

## If Returning After A Long Gap

Read this checkpoint, inspect Git status/HEAD and the Phase 10 plan section, then check only evidence material to the task. Phase 10 local acceptance passed; the next step is a separately approved L6/CI parity run, not an automatic push, Azure deployment or payment reset.
