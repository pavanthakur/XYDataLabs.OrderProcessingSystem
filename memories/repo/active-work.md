# Active Work

Session navigation, not proof. Verify Git, runtime and referenced evidence before acting.

## Historical local acceptance — 12 November 2026

- Review revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Worktree state: `UNKNOWN`
- Evidence status: `HISTORICAL`
- Evidence revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: bounded non-Azure local Docker acceptance; not full Phase 10 or Azure acceptance
- Evidence reference: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`
- Candidate `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`) passed bounded non-Azure Docker acceptance; this does not certify later candidates, full Phase 10 or Azure.
- Evidence: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`; E2E `phase10-docker-http-20261111-230915653`, NFR `phase10-docker-nfr-20261111-234505649`.
- Recorded scope included all A/B/C × Razorpay/OpenPay deterministic and sandbox journeys, isolated integration, identity, messaging/Functions, persistence, settings restoration and NFR recovery/rollback. L6 A/B passed; L6 C passed under DW-028 Option A (workflow 99 local-only). See Phase 10 checklist for run links and limits.
- DW-023/DW-024 and payment/order continuation capabilities remain Phase 11 deferrals. Visible OpenPay 3DS, Razorpay S2S and ACA revision rollback are not certified by this historical packet.

## Current Azure dev checkpoint — 14 November 2026

The current review is based on `c0e6ad1cfceb316cab637fa77fdf83974a9b89a6` plus a dirty worktree. Current-candidate evidence revision is `UNKNOWN`; Azure acceptance remains PARTIAL and unbound to a commit/image. See the evidence paths below.
- Azure dev is partially deployed, not accepted. Workflows `43455621377` and `43485246975` exposed Functions publishing-auth and Functions host-indexing issues. Local IaC/workflow fixes exist but have not been redeployed or verified against the live runtime. Azure work remains Phase 10 and must follow its approval-gated runbook.
- A one-login, no-charge Entra preflight passed for TenantA/B/C, assigned providers (A/B Razorpay; C OpenPay), UI switching A→B→C→A, and logout. Evidence: `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-14T12-29-52-606Z/summary.json`. It does not prove regular-user isolation, session expiry, payments, replay or image identity.
- A headed test created/continued sandbox activity before stopping: TenantA Razorpay order 1 (INR 200) was provider-confirmed and its existing callback correlated; TenantB order 2 reached provider contact details but has no verified final result. TenantC was not run. Do not retry either order until authoritative status is checked. Preserve partial report `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-14T12-59-46-515Z/operator-stop-note.md`.
- Key Vault access-policy `secrets/get` is Forbidden to the signed-in operator. Do not grant broad user access. This does not verify GitHub OIDC or workload managed identities. SQL Entra operator reads require the scoped firewall lease; its helper test passes and the latest temporary rule was confirmed absent.
- Read-only TenantA verification correlated existing browser reference `OR-1794661186-14Nov-TenantA-https-rz` through provider ID to persisted `ORDER-1`; telemetry, provider dependency/request, SQL history/transaction and tenant isolation checks passed. No payment was created or retried. Evidence: `TestResults/Playwright/azure-https/appinsight-verification-20261114/TenantA-provider-id-fallback-readonly.{json,md,txt}`. Azure dev service preflight (App Insights, shared/TenantC dedicated SQL reads and topology) also passed: `TestResults/Playwright/azure-https/preflight-dev-20261114-current-check/`.
- Historical hosted `04` run `43623386488` passed service-preflight-only on `815be4d38a593c8fe3f9c80cf64083d55f472746`: OIDC Key Vault, App Insights, shared/dedicated SQL, topology and firewall cleanup. Artifact: `TestResults/Playwright/azure-https/hosted-service-preflight-43623386488/`. Zero payment journeys; not payment or image acceptance. CI/AI/docs/drift passed; ADR skipped by conditions.

## Next action

### 15 November operator-runner implementation checkpoint

Current parity repair (prepared on `47dadbf4`; owner authorized commit/push to `dev` after review/checks): shared Docker/Azure UI scenarios; fail-closed versioned checks; separate dry-run packets/pointers; durable case ledger; read-only Azure checkpoint reconciliation; safe independent-case continuation; completed charge/Paid-order/terms/callback gates. Full precommit foundations passed (`TestResults/Phase10/payment-parity-precommit-20261115`), as did 28 report tests, 33 Azure static checks, 211 environment checks, secret scan, scoped local/Docker/Azure-dev dry runs, AI/docs and PowerShell parsing. Source-inventory, recovery and strict-verifier regressions passed. Coverage HTML retains its existing source-line branch limitation; Windows symlink test remains skipped. Docker seed/storage audits passed. No new charges yet. Next: commit/push, then rebuild/start Docker without reset and run clean-candidate deterministic/sandbox acceptance before Azure-dev. See the checklist's parity-repair checkpoint; full acceptance remains open. Earlier paragraphs below are historical evidence, not current acceptance or remaining-action authority.

Historical no-charge preflight `payment-automation-azure-matrix-2026-11-15T08-23-42-227Z` passed one-login A/B/C access, switching, sandbox routes and logout. No order/payment was created. TenantC OpenPay reported 3DS enabled; preserve settings. Expiry and live interrupted-run recovery remain NOT TESTED. Legacy runs lack resumable anchors. This is dirty-candidate evidence, not current committed acceptance.

Earlier TenantA ORDER-4/5 reconciliation is in `TestResults/Playwright/azure-https/reconciliation-20261115-readonly/summary.json`. During parity repair, stricter read-only checks additionally found the Razorpay callback (1 required/1 observed); OpenPay Paid order, unique successful charge/matching terms and callback passed. No payment was retried; this is not a fresh full-matrix packet or a new provider-status lookup. Preserve the interrupted matrix. B/C payment acceptance remains pending. Legacy cases lack resumable anchors; workload-identity API testing remains separate/unimplemented.

Historical code `dbe264bc1fdf1bdde194f93ed90225d1f3a1fed9` is pushed. OIDC diagnostic `43698126336` confirms TenantB provider order `order_U044q4vHIUIQhZ` (ORDER-2): zero attempts/payments, INR 200 due, zero paid (`NO_PAYMENT_ATTEMPTS`). Leave its old checkout untouched. Artifact: `TestResults/Playwright/azure-https/hosted-provider-lookup-43698126336/`. No charge, browser run, access grant or forced status. Retain the SSMS helper. Payment `04`, Functions replay, regular-user isolation, expiry and current image binding remain open; Azure acceptance is NOT COMPLETE.

## Safety and navigation

- Local Docker SQL uses loopback `14330`; native Windows SQL `1433` is out of scope. Verify physical identity before any DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not recoverable from that location. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No reset, global prune, VHDX compaction, charge/refund, Azure/directory mutation or Git write without explicit scoped approval. Never resolve uncertain payment state by forcing status or resubmitting.
- Phase 10 source of truth: `docs/internal/phase10-implementation-checklist.md`; design/gates: `docs/internal/phase10-preazure-lld.md`; Azure sequence: `docs/runbooks/phase10-azure-smoke.md`.
