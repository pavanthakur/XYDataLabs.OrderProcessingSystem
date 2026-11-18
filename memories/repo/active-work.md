# Active Work

Session navigation, not proof. Verify Git, runtime and referenced evidence before acting.

## Latest checkpoint — 18 November 2026

- Review revision: `9fa6160c18616003ad6d6aaa14753183d20c4c71`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `UNKNOWN`
- Evidence environment: `LOCAL DOCKER DESKTOP ON G:`
- Evidence scope: supplemental local evidence; no single clean candidate or Azure acceptance
- Evidence reference: `TestResults/Phase10/local-followup-20261118-022000/local-followup.json`

- Scope: Phase 10 non-Azure local Docker follow-up. Azure is excluded. No Git write, reset, prune, VHDX compaction or payment submission was performed in this follow-up.
- Candidate: base commit `9fa6160c18616003ad6d6aaa14753183d20c4c71`; worktree is DIRTY. The supplemental reconciliation records the report-time content identity; inspect it and re-run reconciliation after any candidate changes.
- Reconciliation: `TestResults/Phase10/local-followup-20261118-022000/` (`INCOMPLETE`). It validates evidence hashes and all 13 current service image identities against the historical Docker payment baseline. It explicitly blocks a clean-single-source-candidate claim because the current worktree is dirty.
- Current no-payment Docker run: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261118-014011896/`. Selected foundation (36/36), isolated integration (75/75), smoke, tenant/routing, currency/order-entry, messaging/Functions, restoration and restart persistence checks passed. Payment suite was `none`, so this is partial and not fresh payment acceptance.
- Current-image operational/recovery run: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-013113758/`; targeted no-charge checks: `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261118-013233653/`. Operational results include 100-message burst, outage recovery with zero loss/duplicate effects, replay/restoration and verified Inventory rollback followed by exact-image restoration. Targeted tests passed only their selected no-charge categories; dynamic payment matrix was not run.
- Historical sandbox payment matrix: `TestResults/Playwright/phase10-docker-http/phase10-preazure-20261117-full-baseline/`, bound to the clean base revision. It may be reused only within the supplemental report’s limited compatibility check (same image binaries and payment settings); it is not a fresh run against the dirty source/test candidate. Do not charge again just to refresh reports.
- Storage/runtime read-only check on 18 Nov: Docker Desktop active, all 13 project containers running; configured data path `G:\DockerStorage\DockerDesktopWSL`; storage manifest reported 469,915,316,224 bytes free (about 437.7 GiB), SQL allocation about 0.28 GiB, all 13 services with `10m × 3` logs and no rotation mismatches. Recheck before future actions. Retained F: Docker copy was deleted; it is not recoverable from that path.
- Focused follow-up: report regression 10/10, TypeScript check, no-payment finalization and operational-only contract passed; Phase10 NFR probe build passed. Evidence is in the associated ignored `TestResults` directories.
- Next: verify hosted checks on the published candidate SHA, then reconcile current Docker evidence and rerun only affected or missing required gates. The evidence above describes the earlier test snapshot, not the publication state. DW-023/DW-024 remain deferred; Azure acceptance for this candidate is NOT-RUN. Owner-reported Azure dev cleanup was not independently verified.
- Historical L6 C PASS applies to `494ab4fd` under DW-028 Option A; workflow 99 remains local-only. The uncertain attempts on TenantA ORDER-1/4/5 and TenantB shared ORDER-2 remain protected; do not blindly retry.
- Preserve payment-history safeguards: do not retry ambiguous attempts; correlate by tenant/database/order reference/provider because numeric IDs overlap. Preserve current Docker volumes/provider settings. Local SQL is Docker loopback `14330`; native Windows SQL `1433` is out of scope. No Azure/native SQL mutation or F: deletion.

Canonical plans/runbooks: `docs/internal/phase10-implementation-checklist.md`, `docs/internal/phase10-preazure-lld.md`, `docs/runbooks/phase10-docker-fresh-ssd.md`, and `docs/runbooks/phase10-azure-smoke.md`. Raw `TestResults` are ignored; preserve failed/partial evidence.
