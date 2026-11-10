# Active Work

This is a session checkpoint, not proof of current runtime correctness. Verify material claims against the relevant plan, code and evidence. Historical details remain in Git history and the existing reports; do not replay old recovery instructions automatically.

## Checkpoint Provenance

- Review revision: `802bdfe`
- Worktree state: `DIRTY`
- Evidence status: `HISTORICAL`
- Evidence revision: `UNKNOWN`
- Evidence environment: `docker-dev`
- Evidence scope: `baseline`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261110-030929435/acceptance-packet.json`

## Last Session

- Updated: 2026-11-10. Branch at review: `dev`; repository baseline: `802bdfe` (clean before Batch 1). This is the review baseline, not the revision certified by the historical payment report.
- Current task: approved governance remediation and commit preparation. Batches 1–3 tooling is implemented. DW-025's narrow orchestration/test correction is locally verified; Batch 4 acceptance remains blocked. Resolve delivery commit identity from Git history; the historical report does not certify it. No new skills or global model settings.
- Phase 10 remains **paused**. Its reporting and Azure work are planned, not implemented by this governance task. Phase 11 is not started.
- Existing commits: `6c467a5` contains tenant identity and Phase 10 payment/Docker implementation; `b3f7ed5` contains dropdown styling and P11-W0 planning; `802bdfe` records the remaining Phase 10/11 plans. None alone establishes Azure acceptance.
- Latest governance regression: **28 passed, one symlink NOT TESTED, exit 1/partial**. Evidence: `TestResults/AIGovernance/regression-57932721cb3d47ef9e7cba5ca5c7e517/summary.json`. AI/docs/diff checks passed; five skills remain canonical. No elevation or runtime access. Hosted CI has not run; publishing this candidate/dispatch requires separate approval.
- Codex CLI `0.164.0-alpha.11.1` remains behaviorally untested. Restricted Copilot continuation was attempted: CLI reports `1.0.83-5`, execution uses runtime `1.0.56`. Configured model rejected; identical-permission per-run `auto` timed out after about two minutes and only verified owned processes were stopped. One scenario attempted/two launches; no behavioral PASS, eleven other scenarios unexecuted. Evidence: `TestResults/AIGovernance/remediation-20261110/summary.json`. Startup confirmed five skill descriptors and disabled mutation/MCP tools, not full guidance application or VS Code behavior.
- [Phase 10 findings](../../docs/internal/phase10-implementation-checklist.md#parked-findings-phase-10-remediation-backlog): DW-025 **closed locally** (environment contract 178 pass/0 fail; unchanged checker; mocked TenantC/arbitrary-tenant prepare/restore and unfiltered native matrix checks pass). Runtime wrapper's redundant sample-filtered invocation was removed. DW-026 symlink/hosted CI and DW-027 supported-model/controlled-client acceptance remain open. Parking is not a waiver.

## Verified Evidence And Limits

- Environment: `docker-dev`, HTTP; profile: `baseline`; deterministic and real-sandbox payment suites. Historical run: `phase10-docker-http-20261110-030929435`.
- Evidence: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261110-030929435/acceptance-packet.json`, with `run-summary.json`, `seed-contract.json` and raw per-stage reports in the same directory. These local artifacts were read during this task; a clean checkout may not contain them. Missing artifacts mean evidence unavailable, not PASS.
- Report revision binding: **UNKNOWN**; do not assign the run to today's HEAD. Historical packet status: **PASS for the bounded Docker baseline**, carrying DW-023/DW-024 explicitly. The report records foundations, smoke, isolated integration, tenant routing, deterministic/sandbox payments, messaging/Functions, persistence and restoration as passed. Deferred order continuation is not PASS.
- Reported seed baseline: three active tenants; A/B shared and assigned Razorpay, C dedicated and assigned OpenPay; both providers available in each business database; local OpenPay 3DS off. These are recorded observations, not newly queried live SQL/configuration.
- This does not certify current-candidate architecture/NFR/security/rollback gates, Azure, visible OpenPay 3DS challenge, Razorpay S2S, fulfillment, installments or deferred unresolved-order recovery. Earlier failure reports remain historical evidence, not instructions to reset or overwrite credentials.
- No live Docker settings, databases, providers or Azure state were reverified. No application transactions, resets or deployments ran. Executable changes cover governance tooling/CI plus the approved narrow E2E wrapper and mocked fixture regression correction; this is not current Docker acceptance.

## Pending / Next Actions

1. Review the remediation diff. No automatic commit/push, additional runtime work, permission broadening or gate waiver. Overall acceptance remains incomplete until DW-026/027 close with evidence.
2. Obtain an approved symlink-capable host and controlled Codex setup, plus a supported responsive Copilot model. Review publication/CI dispatch separately. Observe six scenarios per tool; retain both unsuccessful launches. Three-task efficiency metrics remain pending; bytes are not tokens.
3. Resume Phase 10 only after approval: start with **L5-R unified HTML reporting and coverage**. Follow the [Phase 10 pause/resume checkpoint](../../docs/internal/phase10-implementation-checklist.md#remaining-pre-azure-implementation-board); that checklist owns the remaining scope and Azure gates.
4. Phase 11 scope remains in its [implementation plan](../../docs/internal/phase11-implementation-plan.md): P11-W0 payment UX first, with provider-switch safety and generic-tenant regression work tracked separately. Recovery/capability exclusions remain in the [Deferred Work Log](../../docs/internal/DEFERRED-WORK-LOG.md).

## Recent Key Facts And Safety Boundaries

- Shared `dbo.Tenants` owns active tenant tier/provider routing. Provider settings live in each tenant's actual business database; the dedicated tenant-row copy is not routing authority.
- Local project SQL uses loopback port `14330`; native Windows SQL uses `1433` and must remain untouched. Verify project ownership and physical SQL identity before any separately approved database operation; do not reuse historical process IDs.
- Docker storage was verified on G: in earlier work, with named SQL storage. Reverify only when needed; never reset Docker just to resume or reconstruct context.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Historical pre-reset captured-currency mismatch disposition is **not established here**. See `TestResults/DockerStorage/fresh-playwright-20261109-1902/manual-currency-mismatch.md` and `TestResults/DockerStorage/order-continuation-review-20261109/review.md`. Old order/customer URLs may no longer identify the original records. Do not retry, refund, force Paid, alter currency or assume reset resolved provider-side history without a separate approved investigation.
- Keep original approved provider settings and sandbox/deterministic evidence distinct. Never blindly retry an ambiguous charge. Azure deployment/directory writes, resets, charges/refunds and Git writes require their explicit scoped approvals.

## If Returning After A Long Gap

Read this short checkpoint, inspect Git status/HEAD and the relevant Phase 10 plan section, then check only evidence material to the requested task. Report missing evidence or conflicting sources explicitly. Phase 10 is paused; the next implementation candidate is L5-R after approval, not an automatic Azure deployment or payment reset.
