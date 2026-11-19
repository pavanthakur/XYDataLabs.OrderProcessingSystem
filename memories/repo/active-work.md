# Active Work

Session navigation, not proof. Verify Git, runtime and evidence before acting.

## Latest checkpoint — 19 November 2026

- Review revision: `0e46047491e9e664e4d5a1b968ab59d7deda1581`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `TenantA/B/C × Razorpay/OpenPay local deterministic and sandbox baseline, plus local NFR/recovery; Azure excluded`
- Evidence reference: `TestResults/Phase10/local-followup-20261119-current-candidate015/local-followup.json`
- Goal: finish Phase 10 local Docker acceptance. The current-candidate015 report is being regenerated after this handoff correction; candidate014 is the preceding snapshot and is not authoritative for this revision.
- Payment evidence: E2E run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-021441154/`: deterministic 6/6, sandbox positives 6/6, and Razorpay negative/cancellation 6/6 across TenantA/B/C × Razorpay/OpenPay. Provider confirmation, SQL/order correlation and fixture restoration passed. Do not retry successful or ambiguous charges. OpenPay baseline uses 3DS off; challenge-negative support is not certified.
- Latest source-bound evidence will be linked by candidate015's manifest. The previous selected checks passed: no-charge NFR, operational/recovery/rollback, Docker restart persistence, and messaging/Functions replay. Refreshed runs must retain 100-message recovery with zero loss/duplicates, exact Inventory rollback restoration, unchanged paid-order rows/SQL volume across restart, one approved replay and restoration.
- Candidate014 is **INCOMPLETE**: the worktree is dirty; OpenPay challenge-negative is blocked/unverified; order continuation is deferred as DW-023; Azure is not run. The sealed E2E packet's persistence step is NOT-RUN, but the separate current persistence proof passed. Regenerate the report after source-bound checks without repeating sandbox charges.
- Focused validation on current code passed: local-followup tests 16/16, automation TypeScript check, NFR-selection and operational-only contract tests, AI-customization validator, documentation-link validator, and `git diff --check`. The NU1701 OpenPay SDK compatibility warning remains unsuppressed.
- Docker was running all 13 `xy-phase10` services after persistence/replay checks. Verify before further work. Preserve volumes and provider settings; Docker SQL is loopback 14330; native Windows SQL 1433 is out of scope. The deleted F: retention copy is not recoverable. No reset, global prune, VHDX compaction, Azure mutation or Git write occurred.
- Next: rebind no-charge NFR, operations/recovery, persistence and replay evidence to this exact post-handoff worktree, regenerate candidate015, then review the dirty diff. Obtain fresh scoped authorization before staging, committing or pushing.

Canonical plans: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored and must be preserved.
