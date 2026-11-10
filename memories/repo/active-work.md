# Active Work

This is a session checkpoint, not proof of current runtime correctness. Verify material claims against the relevant plan, code and evidence. Historical details remain in Git history and the existing reports; do not replay old recovery instructions automatically.

## Checkpoint Provenance

- Review revision: `290d0fba`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `docker-dev`
- Evidence scope: `baseline`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261110-localacceptance001/local-acceptance-reconciliation.json`

## Last Session

- Updated: 2026-11-11. Branch: `dev`; base revision `290d0fba`; worktree remains dirty. The approved local Docker acceptance command ran without `-ResetData`; a separate NFR run followed a narrow PowerShell argument-binding fix. Docker E2E passed selected foundations, isolated integration, identity, six deterministic and six sandbox positives (all active tenants × both providers), Razorpay negative cases, messaging/Functions effects, persistence restart, settings restoration, and storage/log rotation. NFR functional, tenant, payment, security/identity and 100-message performance checks passed (100/100 inbox/effects, P95 1.907s); scripted operational/recovery sub-suites were skipped. A separate inventory/notifications restart diagnostic passed. Two L5-R reporting defects were fixed; fresh foundations and 27 report tests pass, with 18/18 runner checks, five .NET inventories reconciled, and 61/61 unique frontend identities. The local environment contract passed 178/0. See the reconciliation artifact for exact run paths and dirty diff hashes.
- Phase 10 remains open: the original HTML report is sealed but provisional/BLOCKED and was not regenerated after the reporting fix; sandbox payment cases were not repeated just to refresh it. Order continuation remains DW-023 deferred; rollback is blocked because the old image is absent; replay/recovery-time failure drills remain unrun. No Azure operations, reset, commit or push were performed. Do not interpret the packet's bounded `passed` status or completion seal as total Phase 10 acceptance.
- AI-context token optimization through `46f4309` remains byte-estimated, not token-measured; three-task measurement and DW-027 remain pending. Generated evidence/build folders are Git-ignored, but Git ignore does not prove Copilot context exclusion. Seven skills remain canonical.
- Guidance checks: AI validator, `git diff --check` and the 14-case runner exit-status test PASS locally. Hosted [run 42802711936](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/42802711936) at `1000ff6`: Validate AI Customization passed on Windows/Linux (DW-026 closed). The separate Drift Scanner workflow was fixed in `d77b895`/`af5bec3` and passes in hosted CI.
- DW-027: Codex CLI untested; Copilot CLI rejected its configured model and `auto` timed out. No behavioral PASS, eleven of twelve scenarios unexecuted (`TestResults/AIGovernance/remediation-20261110/summary.json`).
- [Phase 10 findings](../../docs/internal/phase10-implementation-checklist.md#parked-findings-phase-10-remediation-backlog): DW-025 and DW-026 closed. DW-027 (controlled-client acceptance) remains open; parking is not a waiver.

## Verified Evidence And Limits

- Current local evidence: Docker HTTP, baseline profile, cold build, payment suites `both`, persistence restart. E2E run `phase10-docker-http-20261110-localacceptance001`; NFR run `phase10-docker-nfr-20261111-001359480`. Final read-only seed and storage reports are under the NFR run directory. Environment-contract validator: 178 passes / 0 failures. No Azure state was read or changed.
- Candidate binding: base `290d0fba499f6fea70fe6e1b8e6950dd9432302b`, dirty tree. `local-acceptance-reconciliation.json` records SHA-256 identity for the tracked diff and untracked files; this is not committed-revision certification.
- Docker packet status is PASS for its selected bounded stages. It explicitly marks order continuation deferred and TenantC routing regression not-run in that packet; the separate mocked generalized fixture regression passed in foundations. NFR report passed functional, tenant, payments, security/identity and the 100-message burst; operational/recovery were explicitly skipped.
- Final limits: L5-R full-packet dashboard remains BLOCKED/provisional; reporting fixes have passing standalone regression evidence but are not integrated into the sealed E2E packet. Overall Phase 10 is incomplete. Rollback is blocked because no retained previous inventory image was present. No replay-under-60s or recovery-under-30m failure drill was executed. DW-023 order continuation remains deferred. Azure, visible OpenPay 3DS challenge, Razorpay S2S, fulfillment and installments are not certified.

## Pending / Next Actions

1. Complete L5-R by resolving missing per-test and frontend coverage evidence, then reconcile the HTML against Docker and NFR source results without promoting provisional data.
2. Plan separately approved local operational/recovery drills; rollback cannot run until a verified previous inventory image is available. Do not retry any ambiguous charge.
3. Keep Azure outside this approval; do not start it automatically. Phase 11 remains separate in its [implementation plan](../../docs/internal/phase11-implementation-plan.md) and [Deferred Work Log](../../docs/internal/DEFERRED-WORK-LOG.md).

## Recent Key Facts And Safety Boundaries

- Shared `dbo.Tenants` owns active tenant tier/provider routing. Provider settings live in each tenant's actual business database; the dedicated tenant-row copy is not routing authority.
- Local project SQL uses loopback port `14330`; native Windows SQL uses `1433` and must remain untouched. Verify project ownership and physical SQL identity before any separately approved database operation; do not reuse historical process IDs.
- Docker storage was verified on G: in earlier work, with named SQL storage. Reverify only when needed; never reset Docker just to resume or reconstruct context.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Historical pre-reset captured-currency mismatch disposition is **not established here**. See `TestResults/DockerStorage/fresh-playwright-20261109-1902/manual-currency-mismatch.md` and `TestResults/DockerStorage/order-continuation-review-20261109/review.md`. Old order/customer URLs may no longer identify the original records. Do not retry, refund, force Paid, alter currency or assume reset resolved provider-side history without a separate approved investigation.
- Keep original approved provider settings and sandbox/deterministic evidence distinct. Never blindly retry an ambiguous charge. Azure deployment/directory writes, resets, charges/refunds and Git writes require their explicit scoped approvals.

## If Returning After A Long Gap

Read this short checkpoint, inspect Git status/HEAD and the relevant Phase 10 plan section, then check only evidence material to the requested task. Report missing evidence or conflicting sources explicitly. Phase 10 is paused; the next implementation candidate is L5-R after approval, not an automatic Azure deployment or payment reset.
