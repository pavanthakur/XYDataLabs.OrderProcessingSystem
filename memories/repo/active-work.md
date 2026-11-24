# Active Work

Navigation, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 24 November 2026

- Review revision: `51769efdbcdd8ca7701b9f5fb169c9db17c208de`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `51769efdbcdd8ca7701b9f5fb169c9db17c208de`
- Evidence environment: `AZURE_DEV`
- Evidence scope: Azure dev deployment/runtime/transport, no-charge preflight and six-case supervised sandbox matrix passed for the recorded release; overall Phase 10 remains open for regular-user isolation, duplicate replay/recovery/restoration and L5-R/L6 reconciliation.
- Evidence reference: `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-24T09-43-39-072Z/summary.json`
- Phase 10 is **OPEN**. Azure dev was redeployed and validated; no staging/prod, cleanup or teardown was run in this checkpoint.
- Deployment provenance: acceptance/workflow SHA `51769efdbcdd8ca7701b9f5fb169c9db17c208de` (`dev`); the worktree was clean when runs began and all workflow runs below used this SHA. The immutable image release was produced from app candidate `b38590af8a936072a301fc744e12f4c54f612827`; workflow `01` verified the source, six image digests, Functions package and parameter identity before deployment. This status update is a docs-only, uncommitted change on that base and has not had hosted CI.
- Workflow `01` deployment `45360420141`, `02` runtime smoke `45364125339`, `03` transport smoke `45365542421`, and `04` service preflight `45365998186` passed. Generated dev origins are recorded in the run summaries; do not treat their current availability as permanent. Workflow `04` handoff `45366348978` only printed desktop instructions; it did not run the browser or payments.
- Workflow `03` verified Service Bus publish/fan-out, durable Inventory and Notifications effects, dead-letter forwarding, Functions quarantine intake and firewall-lease cleanup. `prepareReplayCandidate=false`; duplicate replay, recovery and exact publisher-setting restoration were **NOT RUN**.
- Workflow `04` no-charge preflight validated Azure dependencies and the active tenant/provider contract; no-charge topology verification and firewall cleanup passed.
- Supervised desktop sandbox matrix `payment-automation-azure-matrix-2026-11-24T09-43-39-072Z` passed 6/6: TenantA/B/C × Razorpay/OpenPay. All journeys completed, provider verification passed, fixture cleanup was `reset`, and final Entra sign-out passed. Razorpay used INR 200 hosted checkout with its sandbox challenge; OpenPay used MXN 200 with configured 3DS disabled and no challenge. This does not prove OpenPay 3DS-on or Razorpay S2S. Evidence: `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-24T09-43-39-072Z/summary.json` and `summary.md` (ignored local artifacts).
- An earlier matrix attempt timed out at Entra preflight with 0 cases and explicitly no order/payment attempt. The successful run used an interactive terminal so the local Playwright sign-in window could be surfaced, completed one normal MFA session, reused it, and did not retry any payment.
- The workflow/payment evidence is now bound to the current deployed release and SHA above. Preserve original and failed reports; do not repeat successful sandbox charges just to refresh evidence.

## Remaining before Phase 10 closure

1. **Regular-user Entra isolation:** not tested. Verify TenantA/B/C guest redemption and API tenant claims using live runtime; then prove each non-admin user is allowed only in its assigned tenant, denied in the other tenants, and signed expired/malformed tokens fail closed. Admin switching is not this proof. TenantA portal status was previously observed as Accepted; email delivery was not verified. Re-read current B/C status before planning any invitation action.
2. **Replay/recovery:** the current `03` run proves transport and quarantine intake only. Establish a dedicated non-Owner identity with narrowly scoped drill permissions, rerun the read-only preflight as that identity, then separately authorize and execute duplicate delivery/recovery. Require one business effect, no cross-tenant effects, and exact publisher-settings restoration; stop on restoration uncertainty.
3. **Rollback/recovery:** a stateless UI rollback/restore was evidenced on 23 November, before this redeployment. Decide against L6 criteria whether that evidence applies to the current image/revision; if not, perform only the required scoped rollback check with a verified immutable prior digest. Do not change SQL schema/state for a UI rollback test.
4. **L5-R/L6 closeout:** reconcile all gates and artifacts to the actual release source, deployed digests, config identity and this SHA. Keep per-gate PASS/FAIL/BLOCKED/NOT RUN; include Azure deployment, runtime, transport, payment, regular-user identity, replay, rollback, Docker/non-Azure and hosted-CI scope. Do not claim overall acceptance while a required gate is open.

DW-023/DW-024 and unsupported payment capabilities remain deferred/unverified, not baseline blockers. Workflow `99` remains intentionally local-only under DW-028. Next action: read-only verify current Entra guest/claim state and identify a least-privilege replay identity; no invitations, role assignments or replay mutation until separately approved. See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
