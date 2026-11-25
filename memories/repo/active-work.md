# Active Work

Navigation, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 25 November 2026

- Phase 10 remains **OPEN**. Azure is dev-only; staging/prod and Azure cleanup were not performed in this checkpoint. Owner-reported prior dev resource-group cleanup is not independent cleanup evidence.
- Review revision: `8bad8dc185cea28cd060cab4b205b169204cbe83`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `AZURE_DEV`
- Evidence scope: Three successful member checkout cases across separate runs; candidate-bound matrix and Phase 10 closure are not established.
- Evidence reference: `TestResults/Phase10/azure-member-payment-reconciliation-2026-11-25/summary.json`
- The review revision is the base of the tenant-scoped runner changes, not their commit. Live image digests and origins were not reverified for this checkpoint.
- The earlier Azure deployment record is workflow `01` run `45360420141`, source `51769efdbcdd8ca7701b9f5fb169c9db17c208de`, app release source `b38590af8a936072a301fc744e12f4c54f612827`. Workflow `02` runtime smoke `45364125339`, `03` transport smoke `45365542421`, and `04` service preflight `45365998186` passed for that recorded deployment. This is historical deployment evidence, not proof of today's live health.
- Earlier admin sandbox matrix `payment-automation-azure-matrix-2026-11-24T09-43-39-072Z` passed six A/B/C × Razorpay/OpenPay cases on its recorded release. It does not certify member identities or later runtime candidates. Preserve it as historical evidence.
- Organizational member accounts for TenantA/B/C were provisioned. The no-charge **member** isolation run `TestResults/Phase10/azure-regular-user-isolation/2026-11-24T17-52-14-217Z-37936/regular-user-isolation.json` passed at clean source `89c3f4f8`; compare its deployment fingerprint before carrying it forward. The earlier `12-11-14-168Z-33812` report was the guest run, not member evidence. Signed expired-token denial remains **NOT RUN**.

### Member sandbox payment reconciliation

- Sanitized packet: `TestResults/Phase10/azure-member-payment-reconciliation-2026-11-25/summary.md` and `summary.json`. It links the original summaries by SHA-256 and omits provider payment IDs, callback URLs, emails, tokens and credentials. Raw reports were not modified.
- Individual case evidence exists for all three configured member/provider pairs, but across separate runs: TenantA/Razorpay, 200 INR, journey/provider/SQL verification passed; TenantB/Razorpay, 200 INR, fresh order journey/provider/SQL verification passed; TenantC/OpenPay, 200 MXN, journey/provider/SQL verification passed. Each row observed the provider challenge and each isolated B/C run recorded sign-out PASS.
- This is **not an overall matrix PASS**. The original A+B run had an ambiguous B checkout (no retry) and aggregate sign-out FAIL. A later read-only Razorpay lookup for that original B order found zero payment attempts (`45468766060`). The fresh B run was top-level failed by the then-current one-tenant aggregation defect; C's one-tenant run passed. TenantB/C preflight reports say source was dirty and have no diff fingerprint. Deployed image identity was not captured in these summaries. No single clean-source, deployment-bound A/B/C matrix or complete run-level sign-out result is established.
- No payment was repeated during reconciliation. Do not retry the ambiguous original TenantB checkout. The runner supports selecting tenant subsets; a subset result is not a full-matrix result.

### Remaining before Phase 10 closure

1. Verify hosted checks for the reviewed runner commit and inventory member-isolation, payment and release evidence. Use the tenant-scoped runner only for specifically approved missing cases; do not repeat successful sandbox cases solely to refresh reports.
2. Establish a least-privileged non-Owner replay identity and pass its read-only preflight. Then separately run the duplicate/recovery drill, requiring exactly-once business effect, no cross-tenant effect, interruption recovery and exact publisher-setting restoration. Existing transport/quarantine evidence does not prove these.
3. Decide whether the 23-Nov stateless UI rollback/restore evidence satisfies L6 for the current release. If not, test only the required scope using verified immutable image digests; do not alter SQL state.
4. Reconcile final L5-R/L6 evidence by source revision, dirty-state/diff identity, deployed image digests, configuration identity and run scope. Keep PASS/FAIL/BLOCKED/NOT RUN distinct. Do not close Phase 10 while required gates remain open.

Previously recorded: workflow `03` passed publish/fan-out, durable Inventory/Notifications effects, dead-letter forwarding, Functions quarantine intake and firewall-lease cleanup; duplicate replay/recovery/restoration were **NOT RUN**. DW-023/DW-024 and unsupported OpenPay visible-challenge/Razorpay S2S capabilities remain deferred or unverified. Workflow `99` remains intentionally local-only under DW-028.

See the [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md), [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md), and [member test-user guide](../../docs/runbooks/phase10-entra-member-test-users.md).
