# Active Work

Session navigation, not proof. Verify Git, runtime and evidence before acting.

## Latest checkpoint — 20 November 2026

- Review revision: `a42ddd3355b2b4fae04f822882c34e06e9a3abe2`
- Worktree state: `CLEAN`
- Evidence status: `BLOCKED`
- Evidence revision: `a42ddd3355b2b4fae04f822882c34e06e9a3abe2`
- Evidence environment: LOCAL_DOCKER_DESKTOP_G
- Evidence scope: `Docker non-payment run, prior TenantA/B/C payment matrix, NFR/operations/recovery/rollback/persistence/replay; Azure excluded`
- Evidence reference: `TestResults/Phase10/local-followup-20261119-candidate-1fba2df2-final005/local-followup.json`
- Reconciliation note: its original dirty-tree content hash and paths were independently reproduced from commit `a42ddd33`; its verdict remains `INCOMPLETE`.
- Latest no-payment Docker run: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-202125004/`. Foundations, smoke, isolated integration, customer directory, currency/order entry, messaging/Functions and settings restoration passed. Payment suites and payment-dependent continuation were explicitly not run; this report is `partial` by design.
- Earlier Docker payment run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-211313195/`: deterministic positives 6/6, sandbox positives 6/6, and Razorpay decline/dismissal 6/6 across TenantA/B/C and both providers. Provider confirmation, SQL/order correlation and fixture restoration passed for recorded cases. Do not repeat charges just to refresh evidence.
- Separate Docker Desktop restart persistence evidence passed: known tenant/order rows and the named SQL volume persisted, with unchanged service image identities. At the latest read-only check, all 13 `xy-phase10` containers were running and G: had about 439 GiB free. No reset, prune, Azure operation, or native SQL change occurred. F: retained storage was deleted earlier and is not recoverable.
- Exact-SHA hosted checks all passed on `a42ddd33`: CI Build/Contract `44589653256`, AI Customization `44589653161`, Documentation Links `44589653254`, Drift Scanner `44589653174`. No deployment workflow ran.
- OpenPay sandbox 3DS is documented and the test fixture is configured, but visible challenge acceptance and provider-documented challenge rejection/cancellation remain unverified/BLOCKED. Order continuation/recovery remains deferred under DW-023/DW-024. Azure acceptance is NOT-RUN. These gaps do not negate the recorded baseline payment journeys; Phase 10 remains open.
- Reporting correction checks passed: local-follow-up 21/21, report 39/39, TypeScript typecheck, AI customization validator, documentation links and `git diff --check`. OpenPay NU1701 compatibility warning remains recorded.
- Next: keep OpenPay challenge behavior and DW-023/DW-024 in their documented follow-up scope; begin Azure only as a separate approved stage. Do not submit more payments, reset data, prune Docker or delete additional storage without specific approval.

Canonical plans: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored; preserve them.
