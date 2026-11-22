# Active Work

Navigation only, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 23 November 2026

- Review revision: `d6eb68713e3d48a9eb047684c142c2b93d0d64e1`
- Worktree state: `CLEAN`
- Evidence status: `HISTORICAL`
- Evidence revision: `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`
- Evidence environment: `AZURE_DEV`
- Evidence scope: `Deployment/runtime/transport and six prior sandbox journeys are recorded; current replay preflight is ready, but payment digest binding, regular-user isolation, duplicate replay/restoration and rollback are open.`
- Evidence reference: `TestResults/Phase10/azure-dev-evidence-review-20261123.md`
- Current candidate: `dev` at `d6eb68713e3d48a9eb047684c142c2b93d0d64e1`, clean and aligned with `origin/dev`.
- Latest exact-SHA hosted checks passed: CI/Contract `45075550986`, AI Customization `45075550866`, Documentation Links `45075550932`, Drift Scanner `45075550837`.
- Current deployed application release: source `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`; deployment `45067679429`, runtime smoke `45068970780`, transport smoke `45069084216`, workflow-04 service preflight `45072102164` passed. Transport proves consumer effects and Functions quarantine intake, not approved deployed replay.
- Read-only replay preflight `TestResults/Phase10/azure-replay-preflight-20261123-current.json`: **24/24 PASS**, no mutation, runner `99fce3f5-b801-4aa1-b2df-122900204d65`. It verifies the isolated/normal queues, expected single-publisher baseline, Functions normal queue, App Insights query access and scoped runner roles. This is readiness only; no duplicate-delivery or exact restoration proof.
- A one-time protected TenantA replay has prior verified SQL evidence under ignored `TestResults/Phase10/azure-dlq-replay-20261123/`. It is not the isolated duplicate-redelivery drill and does not prove all-tenant deployed replay.
- Payment matrix `payment-automation-azure-matrix-2026-11-22T17-38-57-237Z` passed six sandbox cases and fixture cleanup on its run. It has no deployed image digest binding. Its associated prior release source was `64adfb6443b0badd3f07b2f657af2e10b6a1cde1`; current release `e5c40fbe...` differs in all six Container App image digests and the Functions package hash. Treat the six results as historical—not current-release payment acceptance. No payment was repeated in this audit.
- Entra API app has `platform-admin` and `phase10-operator`; both roles are assigned to the same runner/admin user. The `extn.applicationTenantCode` access-token claim is configured and its user extension property exists. No regular-user claim values or Azure isolation tests were verified. Named TenantA/B/C Entra test users are still needed.
- Detailed read-only findings: `TestResults/Phase10/azure-dev-evidence-review-20261123.md` (ignored local evidence; preserve raw reports).

## Remaining before Phase 10 closure

1. Run a fresh current-release Azure sandbox matrix only under a separately scoped payment approval; bind each case to deployed image digests and settings.
2. Provide/approve named regular-user Entra accounts and verify API-token tenant claims, own-tenant allow, cross-tenant denial, invalid/expired token rejection and logout.
3. After separate replay approval, execute the isolated replay and duplicate-delivery/fault-injection cases; verify exact publisher-settings restoration and durable effects. Fresh preflight is mandatory immediately before mutation.
4. Execute/verify Azure recovery and rollback, then reconcile one candidate-bound acceptance packet. An available prior image is not rollback proof.

No payment, replay mutation, deployment, directory write or RBAC change was made in the 23 November read-only audit. Keep Phase 10 open; staging/production and approved Phase 11/provider-capability deferrals remain outside this acceptance.

See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
