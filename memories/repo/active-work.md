# Active Work

Session navigation, not proof. Verify Git, runtime and referenced evidence before acting.

## Latest checkpoint — 16 November 2026

- Review revision: `4302823e6d2495a30adf3289fbb3ef1ae2d300cc`
- Worktree state: `DIRTY`
- Evidence status: `HISTORICAL`
- Evidence revision: `UNKNOWN`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: supplemental local Docker reconciliation from historical E2E plus dirty-worktree foundation/Functions/operational/rollback evidence; not full Phase 10 acceptance
- Evidence reference: `TestResults/Phase10/local-followup-20261116-p0close-v6/local-followup.json`
- Read-only hosted checks on base `4302823e6d2495a30adf3289fbb3ef1ae2d300cc`: CI 43903804899, docs 43903804795, AI customization 43903804759, drift 43903804779 and prompts 43903804968 succeeded; ADR 43903804833 was skipped. These do not certify the dirty changes.

- Base revision: `4302823e6d2495a30adf3289fbb3ef1ae2d300cc` (`dev`, tracking `origin/dev`). Worktree is dirty with scoped, uncommitted Phase 10 NFR/Functions/report changes. No commit or push was performed.
- Latest local supplement: `TestResults/Phase10/local-followup-20261116-p0close-v6/` (INCOMPLETE). Image manifest `TestResults/Phase10/current-image-audit-20261116-followup005/docker-image-identities-after.json` matches the recorded Nov 15 E2E images 13/13; its dirty-state hash still matches the current status list. Image equality is not source, test-runner, config or acceptance equivalence.
- Fresh foundation: `TestResults/Phase10/foundation-local-followup-20261116-final03/summary.json` passed 32/32. Canonical report tests passed 10/10; supplemental report tests passed 6/6; TypeScript, AI-customization validation, documentation links 197/197 and `git diff --check` passed. Cobertura branch HTML warning remains; use XML as source.
- Reporting fix: explicit failed order-continuation, Functions, foundation, operational/recovery, rollback or NFR evidence remains FAIL. Only a single blocked/deferred/not-run order-continuation step with recorded DW-023 is DEFERRED.
- Current local operational evidence: `TestResults/Phase10/operational-only-db230e2d59794a4ab6b91a87670ccf43/nfr/` passed 100-message burst, consumer outage/recovery and settings restoration; rollback exercised a verified previous Inventory image and restored the exact current image. Functions replay lifecycle proof is `TestResults/Phase10/lifecycle-fresh-2f6b73ffd6034c72860a1ace059a17b8/functions-proof.json`.
- The operational-only NFR report intentionally leaves functional, performance, tenant, payments and security not run. Full NFR mode launches a dynamic payment matrix. Do not run it without separately scoped approval for provider transactions and fixture mutations.
- The Nov 15 Docker E2E packet `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261115-194923198/` is bound to clean commit `b434672aacff9284a4646f0a75fca2ce0374625f`. Relevant automation changes, including the payment journey runner, exist after that commit. Matching service images alone do not certify the newer runner; current-candidate E2E and NFR remain open.
- Read-only hosted checks on clean base `4302823e6d2495a30adf3289fbb3ef1ae2d300cc`: CI `43903804899`, docs links `43903804795`, AI customization `43903804759`, drift `43903804779` and prompts `43903804968` succeeded; ADR `43903804833` was skipped. These runs do not certify this dirty worktree.
- Owner reports Azure dev resources were cleaned up on 17 November. Cleanup was not independently verified in this session; do not claim resource deletion or cost cessation as verified. Historical Azure payment matrix on Nov 15 recorded six positives/66 required checks for its deployed version; it does not cover the remaining current-candidate Azure identity, transport/Functions, NFR/rollback and unified reconciliation gates. A fresh approved provisioning/deployment window is required before Azure acceptance.
- Next: complete scoped diff review; establish a reviewed clean candidate and exact-commit hosted checks; then perform current Docker E2E/NFR with explicitly approved sandbox/payment scope. Azure follows only in a renewed test window.
- Preserve uncertain payment history: TenantA ORDER-1/4/5 and TenantB shared ORDER-2 (provider order `order_U044q4vHIUIQhZ`, zero attempts at diagnostic `43698126336`). Never retry ambiguous charges; correlate dedicated tenant rows by tenant/database/reference/provider because numeric IDs overlap.
- DW-023/DW-024, fulfillment/installments/unresolved-payment recovery, Razorpay S2S and visible OpenPay challenge capability remain uncertified/deferred. L6 gate C is PASS only for its recorded `494ab4fd` candidate under DW-028 Option A; workflow 99 remains local-only.
- F: retained Docker copy was deleted and is not a recovery option. Preserve existing Docker volumes/provider settings; local Docker SQL is loopback 14330, native SQL 1433 is out of scope. No Docker reset, pruning or VHDX compaction was performed.

Canonical owners: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored; preserve all failed/partial reports.
