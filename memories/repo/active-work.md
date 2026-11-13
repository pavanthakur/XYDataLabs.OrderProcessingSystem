# Active Work

Session navigation only—not proof. Verify current Git, code, evidence and runtime state before acting.

## Checkpoint — 12 November 2026

- Historical acceptance candidate: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe` (`dev`), clean at E2E/NFR start and finish. Current work is on a later `dev` candidate and does not inherit the historical Docker acceptance; verify Git state.
- Review revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Worktree state: `UNKNOWN`
- Verify Git state before continuing.
- Evidence revision: `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `bounded non-Azure local Docker acceptance; not full Phase 10 or Azure acceptance`
- Evidence reference: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`
- Evidence status: `HISTORICAL`
- The pinned candidate's recorded verdict is **PASS, bounded non-Azure local acceptance**. Do not describe this as full Phase 10 closure or Azure acceptance.
- E2E: `phase10-docker-http-20261111-230915653`; NFR: `phase10-docker-nfr-20261111-234505649`; the v4 reconciler returned PASS with all 13 image identities equal. Sanitized tracked summary: `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`.
- E2E passed cold build, foundations, smoke, isolated integration, identity, deterministic and sandbox journeys (TenantA/B/C × Razorpay/OpenPay), messaging/Functions, persistence after Docker restart, and settings restoration. Six positives per payment mode; six Razorpay failure/cancellation cases passed.
- NFR passed all categories: 100/100 messages/effects at 2.273 s P95; replay visibility 1.080 s; outage recovery 26.201 s, zero lost/duplicate effects; retained Inventory rollback and restore passed. L5-R HTML had no issues and measured backend, frontend, and integration coverage.
- L6 A passed on this candidate (42 architecture-invariant tests + 1 Gateway topology test). L6 B passed with bounded local evidence. L6 C passed under DW-028 Option A: Drift Scanner, AI Customization Windows/Linux, and Documentation Links passed on this SHA; workflow `99` hosted parity is excluded. See the checklist for action links and limits.
- L6 C is closed/PASS for `494ab4fd` under Option A; no corrective rerun is required for that candidate. Azure and the separate combined `l6-ci-parity-and-azure` report gate remain NOT-RUN; that combined gate is not non-Azure L6 C. Checkpoint A CI improvements do not reopen the accepted verdict or certify later candidates. DW-023/DW-024 remain Phase 11 deferrals. Fulfillment, installments, unresolved-payment recovery, visible OpenPay 3DS, Razorpay S2S, and ACA revision rollback remain uncertified.

## Current implementation checkpoint — 13 November 2026

- P0–P2 cost/retention batch is implemented in the working tree at base `84419a87`. P1 makes ACR cleanup manual inventory-only with a fail-closed six-repository digest planner and fixture tests; P2 adds read-only cost/storage snapshots and offline comparison. Static tests were run earlier; rerun applicable validation before committing.
- P0 budget is owner-created and read-back verified: ₹5,000 monthly subscription budget on the subscription ending `980c`, 50% actual-cost alert, one email recipient, expiry `2028-10-31`; owner accepted this setup. It is an alert, not a spending cap. Run owner/cleanup approver: Pavan Thakur; planned window 13 Nov 2026 20:15 IST to 15 Nov 2026 06:57 IST; evidence path `TestResults/AzureCost/phase10-dev-20261113/` outside the Azure RG. The first foundation run began at 20:15 IST; the deadline is not an automatic shutdown.
- The dev branch currently has hosted CI success and immutable release evidence for `f334548f` (CI run `43332284710`; image release `43452746987`). Foundation `00` and hostname bootstrap `00a` passed (`43445749120`, `43446186450`); `01` What-If `43454063480` passed with 26 creates, one ACA Log Analytics reference modification, two unchanged, no deletes. Key Vault nested secret details were not expanded in What-If due secure parameters; actual Key Vault child deployment later succeeded.
- Owner chose generated ACA URLs for dev only. The code adds a dev-only, dry-run-default hostname bootstrap for RG/Log Analytics/ACA environment; extracts the ACA environment Bicep module for reuse; leaves generated hostnames out of `runtime-targets.json`; checks live Gateway/UI FQDN and exact Entra UI origin in dev workflows. Staging/prod retain custom-domain policy. Final local checks passed: both Bicep builds, six workflow YAML parses, 16 static/resolver tests, 2 catalog tests, 9 hosted-CI contract tests, TypeScript check, 187 environment-contract checks, AI customization, doc links and `git diff --check`. These are static/local results, not Azure execution.
- Actual dev workflow `01` run `43455621377` partially deployed the stack: incremental ARM deployment, SQL migrations and SQL managed-identity grant passed. Functions ZIP upload succeeded; a live read-only check matched `20261113160231.zip` to the approved package SHA-256. The workflow failed in its Basic-auth verifier; runtime package hash settings, host refresh, provider contract and endpoint smoke did not run. Cleanup was skipped.
- Local OIDC remediation replaces publishing-credential retrieval and Basic auth with Entra Bearer package verification, disables SCM/FTP Basic auth in existing App Service IaC modules, and extends Azure static validation across future Bicep templates and deployment workflows. Focused verifier/static-preflight tests pass 26/26; both affected Bicep modules compile; static Azure preflight passes. These changes are uncommitted and not deployed, so the previously exposed app-scoped SCM credential is still treated as exposed until Azure applies the policy. No reset/rotation or live auth-policy change has been performed. The current signed-in account's API `platform-admin` role is verified; named regular-user identities/tenant claims remain pending before P6.1. Historical Docker/L6 evidence remains bound only to `494ab4fd`; staging is not certified.

## Next action

Hosted CI and release evidence are bound to `f334548f`; the new OIDC remediation is only in the dirty worktree. Review and validate the complete diff, then obtain explicit Git-write authorization for a new candidate and hosted CI/release checks. After those pass, rerun additive workflow `01` with cleanup disabled; confirm SCM/FTP Basic auth is disabled and the mounted package verifier succeeds before proceeding. Then run `02`, `03`, and `04` in order. Obtain named regular-user accounts before P6.1. Recheck cost/window before continuing; cleanup remains separately destructive and needs immediate confirmation.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
