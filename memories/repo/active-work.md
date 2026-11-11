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

- Updated: 2026-11-11. Current branch `dev`, HEAD `2bae6ef6`; worktree is being updated for the approved DW-028 scope decision and tracked sanitized evidence. The bounded non-Azure local acceptance **PASS** is on clean committed candidate `f2bd3587` (full SHA and source checksum in the tracked summary). Commits after that candidate include workflow, environment-contract-validator, and documentation changes; they do not silently inherit the local result as full L6 acceptance. The reconciler covered sealed completion, foundations, smoke, integration, deterministic and sandbox payments (3 tenants x 2 providers), TenantC routing, messaging/Functions, persistence, restoration, L5-R coverage/reporting, NFR categories, 100-message burst (P95 2.0 s), replay visibility 1.07 s, consumer-outage recovery 26 s with 0 lost/0 duplicate, and a single-service local rollback/restore.
- Fixes made on the way: skipped/blocked NFR categories are `incomplete`, never `passed`; rollback prerequisite no longer blocks drills; non-ASCII test names broke discovery reconciliation (UTF-8 helper); `tenantc-routing-regression` is now derived from run evidence; report no longer flags integration bookkeeping JSON.
- Rollback proof scope: a locally built previous inventory image (`phase10-prev-290d0fba`, built from a clean export of `290d0fba`, provenance under `TestResults/Phase10/rollback-baseline/290d0fba/`) swapped in and restored. No application source differs from the base, so this proves the swap/restore mechanism and schema readiness, not a behavioural difference, and is not an ACA revision rollback.
- DW-028 decision: Option A accepted 2026-11-11. The local Docker hook is manual acceptance; hosted workflow `99` parity is explicitly excluded and the Docker safety guard remains unchanged. Do not claim hosted workflow `99` PASS.
- L6 is still incomplete. On `2bae6ef6`, documentation links and Drift Scanner passed, while hosted AI customization failed AI109 because the evidence artifact was ignored/unavailable in checkout. This change tracks a sanitized summary; rerun applicable hosted checks on the reviewed pushed commit before updating the L6 verdict. No commit or push has been performed. Azure stages remain NOT-RUN and separately approval-gated; DW-023/DW-024 remain Phase 11 deferrals.
- DW-027 (controlled-client behavioral acceptance) remains open; AI-context token measurement is still byte-estimated.

## Verified Evidence And Limits

- The PASS covers only the `non-azure-local` scope on `f2bd3587`: it does not certify Phase 10 completion, Azure, hosted workflow `99`, fulfillment, installments, unresolved-payment recovery, a visible OpenPay 3DS challenge or Razorpay S2S.
- Images are locally built (no registry digest); the candidate is identified by commit and local image IDs.
- The app/runtime acceptance is bound to `f2bd3587`. Later changes include CI workflow and environment-contract tooling; validate those on the target SHA. Changes to app/runtime behavior, payment flows, images, or the evidence generator invalidate the corresponding local acceptance and require rerunning affected gates.

## Pending / Next Actions

1. L6 gate A passed locally on 2026-11-11 (`TestResults/Phase10/local-preazure/20261111-070847708_architecture-conformance`). DW-028 is decided as local-only/manual under Option A; keep the guard unchanged. Gate C remains pending applicable hosted checks on a reviewed pushed SHA. Before this update, hosted run 42940645353 failed AI109; runs 42940645447 (documentation links) and 42940645321 (Drift Scanner) passed on `2bae6ef6`. After this work is separately committed/pushed, verify the new run results; do not claim overall Gate C PASS until all applicable checks pass.
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
