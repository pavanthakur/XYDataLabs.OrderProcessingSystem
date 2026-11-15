# Active Work

Session navigation, not proof. Verify Git, runtime and referenced evidence before acting.

## Latest checkpoint — 16 November 2026

- Review revision: `b434672aacff9284a4646f0a75fca2ce0374625f`
- Worktree state: `DIRTY`
- Evidence status: `HISTORICAL`
- Evidence revision: `b434672aacff9284a4646f0a75fca2ce0374625f`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G: AND AZURE DEV`
- Evidence scope: bounded Docker acceptance and six Azure sandbox positives; not full Phase 10
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261115-194923198/acceptance-packet.json`

- Tested automation revision: `b434672aacff9284a4646f0a75fca2ce0374625f`, clean during acceptance. Historical recorded evidence, not live revalidation of all runtime settings.
- Docker `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261115-194923198/`: packet, completion and offline HTML passed. Backend 374, frontend 61, automation 62 cases/12 suites, isolated integration 75 passed. Six deterministic positives, six sandbox positives and six Razorpay negatives passed across A/B/C and both providers. Identity, messaging/Functions, persistence and all 18 fixture restorations passed. Integration databases cleaned; application metadata unchanged.
- Azure `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-15T15-14-59-368Z/summary.json`: six fresh sandbox positives, 66/66 required checks, one Entra login/MFA and final sign-out. Provider/SQL/callback/unique charge/Paid projection passed. Final read-only reconciliation confirmed six verified/restored receipts and unchanged source/deployment/settings. Docker/Azure client source identities agree; Azure deployed application image identity is separate. Not hosted unattended workflow 04 acceptance.
- Hosted build/contracts `43723705879` and AI/docs/prompts/drift checks passed on `b434672a`. ADR skipped by opt-in, not PASS. Preserve earlier failed CI and stopped Docker evidence.
- Final Docker storage: G: 437.5 GiB free, SQL allocation 0.28 GiB, 13 containers at `10m × 3`, zero mismatches. Build/package warnings and coverage source-line branch limitation remain.
- Approved cost-only follow-up fixes Windows JSON transport, CLI response normalization and unknown/null handling. Ten cost and nine hosted-contract tests passed. Read-only snapshot `TestResults/AzureCost/phase10-dev-20261116-cost-snapshot.json` captured 16 November 00:20 IST: approximately INR 586.07 subscription month-to-date, lagging and not per-run cost; three SQL size limits unknown. Monthly INR 5,000 budget is an alert, not a cap.
- Closeout validation: 82 release-contract tests and nine hosted-contract tests passed (the ten cost tests are included in the 82); secret hygiene, documentation links, AI customization, 211 environment checks and diff whitespace checks passed. Application build/integration reruns are not applicable to this cost/CI/docs-only follow-up; runtime evidence remains bound to `b434672a`.
- Next: commit/push only reviewed cost/CI/docs files and verify hosted checks on the new revision (pending at this checkpoint). New cost-only commits do not inherit exact-revision payment acceptance. No further login or payment rerun needed.
- Azure testing window expired 15 November 22:30 IST. No new charges/runtime mutations, deployment, access changes or cleanup without renewed scoped approval; resources may continue billing.
- Broader current-candidate Azure transport/Functions, regular-user isolation/expiry, negatives/recovery, NFR/rollback and unified reporting remain open. Historical L6 C PASS on `494ab4fd` under DW-028 Option A remains valid only in its recorded scope. Current-image NFR/rollback was not rerun.
- DW-023/DW-024 fulfillment, installments/unresolved-payment recovery, Razorpay S2S and visible OpenPay challenge capabilities remain uncertified. Never retry uncertain history blindly: preserve old TenantA ORDER-1/4/5 and TenantB shared ORDER-2 (provider `order_U044q4vHIUIQhZ`, zero attempts at diagnostic `43698126336`). Dedicated numeric IDs overlap: correlate tenant/database/reference/provider.
- Local Docker SQL loopback14330 only; native Windows SQL1433 excluded. Preserve volumes/settings/unrelated backups. No reset/prune/compaction. Owner deleted F: retention; not a recovery option. Do not broaden Key Vault permissions.

## Historical reference and navigation

Historical bounded Docker acceptance on `494ab4fd`: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`. It does not certify changed images. Preserve failed/partial reports and successful payment history.

Canonical owners: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-azure-smoke.md`. Raw TestResults remain ignored. No new workstream automatically.
