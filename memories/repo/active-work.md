# Active Work

Session navigation, not proof. Verify Git, runtime and evidence before acting.

## Latest checkpoint — 19 November 2026

- Review revision: `2200b5b15d766f13c019fb22fff5a72f23d29498`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: `TenantA/B/C × Razorpay/OpenPay local deterministic and sandbox baseline, plus local NFR/recovery; Azure excluded`
- Evidence reference: `TestResults/Phase10/local-followup-20261119-postcommit004/local-followup.json`
- Goal: finish Phase 10 local Docker acceptance. Commit `2200b5b` contains reporting/NFR tooling and documentation only; no payment was rerun after it. The post-commit report records exact image-source content equivalence where proven and keeps the earlier E2E source mismatch explicit.
- Payment evidence: E2E run `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261119-021441154/`: deterministic 6/6, sandbox positives 6/6, and Razorpay negative/cancellation 6/6 across TenantA/B/C × Razorpay/OpenPay. Provider confirmation, SQL/order correlation and fixture restoration passed. Do not retry successful or ambiguous charges. OpenPay baseline uses 3DS off; challenge-negative support is not certified.
- Pre-commit candidate015 is retained unchanged as historical evidence. The new post-commit report is the current checkpoint; its source-binding and remaining gates are authoritative only for its recorded snapshot.
- Post-push hosted checks for `2200b5b` passed: CI Build/Contract, Drift Scanner, AI Customization, AI Prompts and Documentation Links. ADR Markdown was skipped because no ADR changed. These checks do not certify Docker/Azure runtime acceptance.
- Focused validation on current code passed: local-followup tests 16/16, automation TypeScript check, NFR-selection and operational-only contract tests, AI-customization validator, documentation-link validator, and `git diff --check`. The NU1701 OpenPay SDK compatibility warning remains unsuppressed.
- Docker was running all 13 `xy-phase10` services after persistence/replay checks; verify before further work. Preserve volumes and provider settings; Docker SQL is loopback 14330; native Windows SQL 1433 is out of scope. The deleted F: retention copy is not recoverable. No reset, global prune, VHDX compaction or Azure mutation occurred.
- Next: review the post-commit report. It must keep OpenPay challenge-negative blocked/unverified, order continuation deferred as DW-023, Azure not run, and any cross-run source mismatch visible. Do not repeat sandbox payments merely to refresh reporting. Separately review and authorize any Git write for the reporting/handoff follow-up.

Canonical plans: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored and must be preserved.
