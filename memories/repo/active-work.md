# Active Work

Navigation only, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 23 November 2026

- Review revision: `b534e70f1645f3e3c869c71c4520b03016ee13e7`
- Worktree state: `CLEAN`
- Evidence status: `HISTORICAL`
- Evidence revision: `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`
- Evidence environment: `AZURE_DEV`
- Evidence scope: `Deployment/runtime/transport and six prior sandbox journeys are recorded; current replay preflight is ready, but payment digest binding, regular-user isolation, duplicate replay/restoration and rollback are open.`
- Evidence reference: `TestResults/Phase10/azure-dev-evidence-review-20261123.md`
- Current candidate: `dev` at `b534e70f1645f3e3c869c71c4520b03016ee13e7`, clean and aligned with `origin/dev`.
- Latest exact-SHA hosted checks passed: CI/Contract `45080052387`, Documentation Links `45080052421`, Drift Scanner `45080052369`. The AI-customization validator passed locally; its hosted workflow was not triggered for this checklist-only change.
- Current deployed application release: source `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`; deployment `45067679429`, runtime smoke `45068970780`, transport smoke `45069084216`, workflow-04 service preflight `45072102164` passed. Transport proves consumer effects and Functions quarantine intake, not approved deployed replay.
- Read-only replay preflight `TestResults/Phase10/azure-replay-preflight-20261123-current.json`: **24/24 PASS**, no mutation, runner `99fce3f5-b801-4aa1-b2df-122900204d65`. It verifies the isolated/normal queues, expected single-publisher baseline, Functions normal queue, App Insights query access and scoped runner roles. The supplied runner is also subscription Owner and has API `platform-admin` and `phase10-operator`; use a dedicated non-Owner identity for least-privilege live replay testing. This is readiness only; no duplicate-delivery or exact restoration proof.
- A one-time protected TenantA replay has prior verified SQL evidence under ignored `TestResults/Phase10/azure-dlq-replay-20261123/`. It is not the isolated duplicate-redelivery drill and does not prove all-tenant deployed replay.
- Payment matrix `payment-automation-azure-matrix-2026-11-22T17-38-57-237Z` passed six sandbox cases and fixture cleanup on its run. It has no deployed image digest binding. Its associated prior release source was `64adfb6443b0badd3f07b2f657af2e10b6a1cde1`; current release `e5c40fbe...` differs in all six Container App image digests and the Functions package hash. Treat the six results as historical—not current-release payment acceptance. No payment was repeated in this audit.
- Entra API app has `platform-admin` and `phase10-operator`; both roles are assigned to the same runner/admin user. The `extn.applicationTenantCode` access-token claim is configured and its user extension property exists. No regular-user claim values or Azure isolation tests were verified. Named TenantA/B/C Entra test users are still needed.
- Workflow 04 run `45072102164` was `service-preflight`, not browser payments: the no-payment service check passed; browser handoff and order lookup were skipped. The payment matrix must be run and correlated against the current release before it counts.
- The checklist now records the 23 November Azure evidence checkpoint. Its update was pushed as `b534e70f`; exact-SHA CI/contract, documentation links and drift checks passed. Detailed read-only findings: `TestResults/Phase10/azure-dev-evidence-review-20261123.md` (ignored local evidence; preserve raw reports).

## Remaining before Phase 10 closure

1. Run a fresh current-release Azure sandbox matrix only under a separately scoped payment approval; bind each case to deployed image digests and settings.
2. Provide/approve named regular-user Entra accounts and verify API-token tenant claims, own-tenant allow, cross-tenant denial, invalid/expired token rejection and logout.
3. Establish a dedicated non-Owner replay runner with only scoped roles. After separate replay approval, execute the isolated replay and duplicate-delivery/fault-injection cases; verify exact publisher-settings restoration and durable effects. Fresh preflight is mandatory immediately before mutation.
4. Execute/verify Azure recovery and rollback, then reconcile one candidate-bound acceptance packet. An available prior image is not rollback proof.

No payment, replay mutation, deployment, directory write or RBAC change was made in the 23 November read-only audit. Keep Phase 10 open; staging/production and approved Phase 11/provider-capability deferrals remain outside this acceptance.

See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
