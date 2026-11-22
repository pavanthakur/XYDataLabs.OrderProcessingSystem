# Active Work

Navigation only, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 23 November 2026

- Review revision: `de3a5497c6c1179418508e1c20f3f0f73cfc435e`
- Worktree state: `CLEAN`
- Evidence status: `HISTORICAL`
- Evidence revision: `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`
- Evidence environment: `AZURE_DEV`
- Evidence scope: `Deployment, runtime, transport, service preflight and one approved TenantA replay passed; Azure browser payment matrix is blocked before any order/payment.`
- Evidence reference: `TestResults/Phase10/azure-dlq-replay-20261123/validation.json`
- Deployed application/image candidate: `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`. Verifier/test fixes are committed as `de3a5497c6c1179418508e1c20f3f0f73cfc435e`; they do not change deployed application images.
- Latest hosted results on the candidate: CI/Contract and Drift Scanner `45066710757` / `45066710721`; immutable release build `45067365380`; deploy orchestrator `45067679429`; runtime smoke `45068970780`; transport smoke `45069084216`; workflow 04 service-only preflight `45072102164`. Verify each run before treating it as current evidence.
- Deploy, runtime, transport and service-access preflight passed. Workflow 04 service-preflight is no-charge and does not prove browser or payment journeys.
- TenantA approved DLQ replay was executed once using the authenticated operator identity. SQL evidence and the acceptance projection are under ignored `TestResults/Phase10/azure-dlq-replay-20261123/`. Validation passed: one replay, one tenant-scoped Inventory and Notifications effect each, no cross-tenant effects, and temporary SQL firewall lease restored. Regression fixes cover tenant variable shadowing, SQL UTC interpretation, and valid downstream effects that occur after publication but before the Functions completion marker.
- Exact-commit CI on `de3a5497c6c1179418508e1c20f3f0f73cfc435e`: CI/Contract `45073184649`, AI Customization `45073184685`, Documentation Links `45073184689`, AI Prompts `45073184727`, and Drift Scanner `45073184724` passed; ADR Markdown `45073184735` was skipped by path scope.
- **Still open:** the Azure browser payment matrix. The recent runner attempt stopped during Entra preflight before fixtures/orders/payments (0 cases, 0 orders, 0 payments); the browser-control session is currently unavailable. Do not bypass MFA. Resume the supervised six-case matrix once the attended browser session is visible, then reconcile Azure and final Phase 10 evidence.
- This is not full Phase 10 closure. OpenPay visible-challenge behavior, Razorpay S2S, and DW-023/DW-024 order recovery/fulfillment scope remain uncertified or deferred. Staging and production are out of scope.

See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md), [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md), and [Service Bus DLQ replay runbook](../../docs/runbooks/servicebus-dlq-replay.md).
