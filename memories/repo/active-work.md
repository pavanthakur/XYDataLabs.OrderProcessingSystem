# Active Work

Session navigation, not proof. Verify Git, runtime and referenced evidence before acting.

## Latest checkpoint — 16 November 2026

- Review revision: `eec6fd57aa60030ecd0aca463a969607bd0d9f1e`
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
- Historical cost/CI follow-up `10ac3678` passed hosted checks. It did not renew runtime acceptance on `b434672a`.
- Replay/identity: local approval uses Keycloak PKCE and the protected API; `phase10-operator` stays distinct from `platform-admin`. Azure app-role assignment and deployed replay are unverified. The CLI makes one approval POST, then read-only SQL polling bound to tenant/message/quarantine/request/correlation and one effect per consumer; no ambiguous retries. DB-backed duplicate-delivery proof remains open.
- Report: offline HTML verifies Azure evidence bytes/hashes and admin/regular-user isolation; unsafe or missing evidence blocks, and Azure/Docker verdicts stay separate. Report tests 39/39 and TS compile passed; historical evidence still lacks complete provenance binding.
- NFR separates execution/restoration, terminates probe trees, checks readiness/environment and blocks later actions after unproven restoration. Mock tests are not runtime proof. HTML branch totals omit some Cobertura branches; use XML.
- Latest local implementation (16 Nov): opt-in Azure-dev replay-candidate preparation uses separate shared operations/dedicated business SQL; output collision guards run before Azure/firewall access. Candidate creation was not run. Static preflight 35/35, report/replay tests 62/62, TS compile, PowerShell parse and tool build passed (NU1900 advisory-service warning). Deployed replay/duplicate delivery remain unproven.
- Added SQL-backed replay crash-window regression: fake publisher records broker acceptance then throws; retry asserts stable business MessageId. Integration test project builds (6 warnings, 0 errors); regression NOT RUN because it mutates test SQL. Consumer inbox dedupe remains a separate test, not a combined duplicate-effect or Azure proof. Runbook/checklist updated.
- Foundation `TestResults/Phase10/foundation-local-20261116-replayhardening004/summary.json`: 29 PASS; preview BLOCKED. Report/contracts/replay/NFR, secret scan/211 env pass. Committed/pushed `eec6fd57`; no runtime run. Hosted AI check `43894898214` failed Windows CRLF handoff size; shorten without weakening budget. Build CI `43894898317` pending at checkpoint; docs/prompts/drift passed, ADR skipped.
- Identity prep: runbook has admin/regular-user claims and isolation cases; A/B/C role assignments pending, no directory changes. Local messaging refuses proof overwrite; unique run folders documented. Restoration tests 6/6; docs links 197/197; Docker safety 45 and NFR aggregate 5 passed.
- Next: validate handoff size in LF/CRLF, obtain follow-up commit approval, verify exact-commit CI. DB duplicate-delivery tests, Azure window and explicit operator role need separate runtime/access approval.
- Azure testing window expired 15 November 22:30 IST. No new charges/runtime mutations, deployment, access changes or cleanup without renewed scoped approval; resources may continue billing.
- Broader current-candidate Azure transport/Functions, regular-user isolation/expiry, negatives/recovery, NFR/rollback and unified reporting remain open. Historical L6 C PASS on `494ab4fd` under DW-028 Option A remains valid only in its recorded scope. Current-image NFR/rollback was not rerun. The active goal covers local Steps 1–5 only; Step 6+ requires fresh scoped approval.
- DW-023/DW-024 fulfillment, installments/unresolved-payment recovery, Razorpay S2S and visible OpenPay challenge capabilities remain uncertified. Never retry uncertain history blindly: preserve old TenantA ORDER-1/4/5 and TenantB shared ORDER-2 (provider `order_U044q4vHIUIQhZ`, zero attempts at diagnostic `43698126336`). Dedicated numeric IDs overlap: correlate tenant/database/reference/provider.
- Local Docker SQL loopback14330 only; native Windows SQL1433 excluded. Preserve volumes/settings/unrelated backups. No reset/prune/compaction. Owner deleted F: retention; not a recovery option. Do not broaden Key Vault permissions.

## Historical reference and navigation

Historical bounded Docker acceptance on `494ab4fd`: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`. It does not certify changed images. Preserve failed/partial reports and successful payment history.

Canonical owners: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-azure-smoke.md`. Raw TestResults remain ignored. No new workstream automatically.
