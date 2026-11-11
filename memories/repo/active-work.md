# Active Work

This is a session checkpoint, not proof of current runtime correctness. The provenance block below binds the accepted local run and its clean state at run time; it does not describe the current checkout. Verify material claims against the relevant plan, code and evidence. Historical details remain in Git history and the existing reports; do not replay old recovery instructions automatically.

## Checkpoint Provenance

- Review revision: `f2bd3587`
- Worktree state: `CLEAN`
- Evidence status: `CURRENT_PASS`
- Evidence revision: `f2bd3587`
- Evidence environment: `docker-dev`
- Evidence scope: `non-azure-local`
- Evidence reference: `TestResults/Phase10/accepted/phase10-local-acceptance-f2bd3587.json`

## Last Session

- Updated: 2026-11-11. Branch `dev`, clean at `3659a743`. Non-Azure L6 gates are recorded individually: architecture gate A passed at `3659a743` (42 invariant tests + 1 topology test); Docker/NFR gate B passed at `f2bd3587` (full evidence/source checksum in the tracked summary); hosted gate C passed at `3659a743` under DW-028 Option A. The applicable hosted runs were AI Customization 42945848330 (Windows/Linux), Documentation Links 42945847974 and Drift Scanner 42945848074. The environment-contract validator also passed 178/178 at `3659a743`. No new payment transactions were run.
- Fixes made on the way: skipped/blocked NFR categories are `incomplete`, never `passed`; rollback prerequisite no longer blocks drills; non-ASCII test names broke discovery reconciliation (UTF-8 helper); `tenantc-routing-regression` is now derived from run evidence; report no longer flags integration bookkeeping JSON.
- Rollback proof scope: a locally built previous inventory image (`phase10-prev-290d0fba`, built from a clean export of `290d0fba`, provenance under `TestResults/Phase10/rollback-baseline/290d0fba/`) swapped in and restored. No application source differs from the base, so this proves the swap/restore mechanism and schema readiness, not a behavioural difference, and is not an ACA revision rollback.
- DW-028 decision: Option A accepted 2026-11-11. The local Docker hook is manual acceptance; hosted workflow `99` parity is explicitly excluded and the Docker safety guard remains unchanged. Do not claim hosted workflow `99` PASS.
- The three non-Azure L6 gates have scoped PASS verdicts, but evidence spans revisions: B is bound to `f2bd3587`; A/C are bound to `3659a743`. The historical packet remains unchanged and no single refreshed same-SHA report is claimed. Before Azure, meet the Pre-Azure LLD's one-target-SHA/image-identity evidence requirement or obtain a reviewed exception. Azure stages remain NOT-RUN and separately approval-gated; DW-023/DW-024 remain Phase 11 deferrals.
- DW-027 (controlled-client behavioral acceptance) remains open; AI-context token measurement is still byte-estimated.

## Verified Evidence And Limits

- The PASS covers only the `non-azure-local` scope on `f2bd3587`: it does not certify Phase 10 completion, Azure, hosted workflow `99`, fulfillment, installments, unresolved-payment recovery, a visible OpenPay 3DS challenge or Razorpay S2S.
- Images are locally built (no registry digest); the candidate is identified by commit and local image IDs.
- The app/runtime acceptance is bound to `f2bd3587`. Later changes include CI workflow and environment-contract tooling; validate those on the target SHA. Changes to app/runtime behavior, payment flows, images, or the evidence generator invalidate the corresponding local acceptance and require rerunning affected gates.

## Pending / Next Actions

1. Non-Azure gate evidence and run references are in `docs/internal/phase10-implementation-checklist.md`. DW-028 Option A is closed; workflow `99` hosted parity is excluded and its guard remains unchanged. Before Azure, resolve the same-target-SHA/image-identity evidence requirement without repeating sandbox charges unless separately approved.
2. Phase 11 (DW-023/DW-024) is separate: [plan](../../docs/internal/phase11-implementation-plan.md), [Deferred Work Log](../../docs/internal/DEFERRED-WORK-LOG.md).

## Recent Key Facts And Safety Boundaries

- Shared `dbo.Tenants` owns active tenant tier/provider routing. Provider settings live in each tenant's actual business database; the dedicated tenant-row copy is not routing authority.
- Local project SQL uses loopback port `14330`; native Windows SQL uses `1433` and must remain untouched. Verify project ownership and physical SQL identity before any separately approved database operation; do not reuse historical process IDs.
- Docker storage was verified on G: in earlier work, with named SQL storage. Reverify only when needed; never reset Docker just to resume or reconstruct context.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Historical pre-reset captured-currency mismatch disposition is **not established here**. See `TestResults/DockerStorage/fresh-playwright-20261109-1902/manual-currency-mismatch.md` and `TestResults/DockerStorage/order-continuation-review-20261109/review.md`. Old order/customer URLs may no longer identify the original records. Do not retry, refund, force Paid, alter currency or assume reset resolved provider-side history without a separate approved investigation.
- Keep original approved provider settings and sandbox/deterministic evidence distinct. Never blindly retry an ambiguous charge. Azure deployment/directory writes, resets, charges/refunds and Git writes require their explicit scoped approvals.

## If Returning After A Long Gap

Read this checkpoint, inspect Git status/HEAD and the Phase 10 plan section, then check only evidence material to the task. Bounded Docker acceptance passed on `f2bd3587`; the next step is review and separately authorized commit/push, then hosted-check verification on that exact SHA. Workflow `99` stays local-only under DW-028 Option A. No automatic push, Azure deployment or payment reset.
