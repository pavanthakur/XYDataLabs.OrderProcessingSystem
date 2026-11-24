# Active Work

Navigation, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 24 November 2026

- Review revision: `1bdc10e194558ec341e39f4faacc87f394eda53c`
- Worktree state: `DIRTY` — member-payment task and supporting tests/documentation are under review; not committed.
- Evidence status: `BLOCKED`
- Evidence revision: `51769efdbcdd8ca7701b9f5fb169c9db17c208de`
- Evidence environment: `AZURE_DEV`
- Evidence scope: Azure dev deployment/runtime/transport, no-charge preflight and six-case supervised sandbox matrix passed for the recorded release; overall Phase 10 remains open for regular-user isolation, duplicate replay/recovery/restoration and L5-R/L6 reconciliation.
- Evidence reference: `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-24T09-43-39-072Z/summary.json`
- Phase 10 is **OPEN**. Azure dev was redeployed and validated; no staging/prod, cleanup or teardown was run in this checkpoint.
- Deployment provenance: workflow SHA `51769efdbcdd8ca7701b9f5fb169c9db17c208de`; immutable app release source `b38590af8a936072a301fc744e12f4c54f612827`. Workflow `01` verified six image digests, Functions package and parameter identity at deployment. Checkpoint commit `a56c468d` passed four hosted checks without deploying. Identity-test, runner, documentation, and organizational-member provisioning changes are committed in review revision `018d953e`; member accounts and claims have since been applied and verified in Entra.
- Workflow `01` deployment `45360420141`, `02` runtime smoke `45364125339`, `03` transport smoke `45365542421`, and `04` service preflight `45365998186` passed. Generated dev origins are recorded in the run summaries; do not treat their current availability as permanent. Workflow `04` handoff `45366348978` only printed desktop instructions; it did not run the browser or payments.
- Workflow `03` verified Service Bus publish/fan-out, durable Inventory and Notifications effects, dead-letter forwarding, Functions quarantine intake and firewall-lease cleanup. `prepareReplayCandidate=false`; duplicate replay, recovery and exact publisher-setting restoration were **NOT RUN**.
- Workflow `04` no-charge preflight validated Azure dependencies and the active tenant/provider contract; no-charge topology verification and firewall cleanup passed.
- Supervised desktop sandbox matrix `payment-automation-azure-matrix-2026-11-24T09-43-39-072Z` passed 6/6: TenantA/B/C × Razorpay/OpenPay. All journeys completed, provider verification passed, fixture cleanup was `reset`, and final Entra sign-out passed. Razorpay used INR 200 hosted checkout with its sandbox challenge; OpenPay used MXN 200 with configured 3DS disabled and no challenge. This does not prove OpenPay 3DS-on or Razorpay S2S. Evidence: `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-24T09-43-39-072Z/summary.json` and `summary.md` (ignored local artifacts).
- An earlier matrix attempt timed out at Entra preflight with 0 cases and explicitly no order/payment attempt. The successful run used an interactive terminal so the local Playwright sign-in window could be surfaced, completed one normal MFA session, reused it, and did not retry any payment.
- The workflow/payment evidence is now bound to the current deployed release and SHA above. Preserve original and failed reports; do not repeat successful sandbox charges just to refresh evidence.

## Remaining before Phase 10 closure

### Latest member-payment preflight correction — 24 November 2026

- The latest `NonAdminSandbox` preflight (`payment-automation-azure-matrix-2026-11-24T17-01-17-406Z`) **failed closed before creating an order**: TenantA claim validation failed; `orderId=0`, `customerOrderId=not-created`, no payment attempt. Operator sign-out completed. Do not interpret this as a payment failure or retry a charge.
- Read-only inspection found the API registration emits `extension_<API-client-ID-without-hyphens>_applicationTenantCode`, but the deployed Gateway setting expected `extn.applicationTenantCode`. The no-charge guard correctly prevented order creation.
- Local changes now derive the exact claim from the API client ID across deployment preparation, identity verification and browser tests; stale workflow input wiring and documentation are being removed. These changes are uncommitted and **not deployed**. Re-run local contract tests, review the diff, and obtain deployment approval before applying them to Azure dev.
- After the corrected deployment, run the no-charge member preflight first. Only if it passes, ask separately before the three sandbox member payment journeys. Existing admin six-case sandbox evidence remains historical and is not invalidated by this preflight; the member-payment gate remains NOT RUN.

Optional non-admin checkout coverage: VS Code Azure Dev 06 is the optional B2B guest sandbox task; 06b is the organizational-member sandbox task (A/B Razorpay, C OpenPay). Both are separate from the passed no-payment isolation matrix and existing admin payment coverage. Live non-admin payment task is NOT RUN and needs separate sandbox-payment approval.

The `04a-04b Phase 10 Entra Member Setup Guide` GitHub workflow is informational only; it has no Azure permissions and does not query Entra or perform directory writes. Local member provisioning was separately confirmed and verified.

1. **Regular-user Entra isolation:** the earlier MSA guest trial was unsuitable for API extension-claim validation. Organizational member accounts were subsequently provisioned and verified. The headed A/B/C matrix passed at `12:15` (`TestResults/Phase10/azure-regular-user-isolation/2026-11-24T12-11-14-168Z-33812`, sanitized report): each member passed own-tenant access, cross-tenant denial, deep-link denial and cross-tab sign-out; no payments were attempted. Signed expired-token denial remains **NOT RUN**. The current local changes add a separate member sandbox-payment task; that task is **NOT RUN** and needs separate sandbox-payment approval.
2. **Replay/recovery:** the current `03` run proves transport and quarantine intake only. Establish a dedicated non-Owner identity with narrowly scoped drill permissions, rerun the read-only preflight as that identity, then separately authorize and execute duplicate delivery/recovery. Require one business effect, no cross-tenant effects, and exact publisher-settings restoration; stop on restoration uncertainty.
3. **Rollback/recovery:** a stateless UI rollback/restore was evidenced on 23 November, before this redeployment. Decide against L6 criteria whether that evidence applies to the current image/revision; if not, perform only the required scoped rollback check with a verified immutable prior digest. Do not change SQL schema/state for a UI rollback test.
4. **L5-R/L6 closeout:** reconcile all gates and artifacts to the actual release source, deployed digests, config identity and this SHA. Keep per-gate PASS/FAIL/BLOCKED/NOT RUN; include Azure deployment, runtime, transport, payment, regular-user identity, replay, rollback, Docker/non-Azure and hosted-CI scope. Do not claim overall acceptance while a required gate is open.

Read-only closeout verified all six live image digests against workflow `01`, gateway/UI HTTP 200 and both Functions indexed. No entity-scoped replay runner was found. The current UI digest differs from the one restored on 23 November. Next: cover signed expiry separately and identify a dedicated non-Owner replay runner for scoped permission review. No role assignments, replay, rollback or payments were performed in the identity follow-up. DW-023/DW-024 and unsupported payment capabilities remain deferred/unverified; workflow `99` stays local-only. See the [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
