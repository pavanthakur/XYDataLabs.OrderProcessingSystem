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

## Current implementation checkpoint — 14 November 2026

- Phase 10 Azure dev is partially deployed, not accepted. Workflow `01` run `43455621377` deployed SQL/identity and a Functions package but failed its SCM Basic-auth verifier. Later run `43485246975` uploaded Functions and passed ARM/SQL setup, but the host indexed 0/2 because the local validator rejected Azure managed-identity storage settings. Live runtime/configuration state has not been rechecked in this turn.
- Local, uncommitted remediation accepts local or Azure managed-identity Functions storage, configures Functions and Container Apps SQL access with managed identity, adds explicit SQL-disabled what-if targets, wires DLQ/replay settings and the replay queue, and pauses Functions triggers until SQL grants and exact package/index checks pass. Workflow 03 polls quarantine SQL read-only rather than competing with the deployed intake trigger. The local SQL-firewall helper no longer prints the Key Vault admin password. Approved Functions replay is explicitly not proven by workflow 03. Base revision: `823b96f3e7c1055524c580c5d69a1e369bd65ba7`.
- Local checks: static-preflight suite 22/22, environment-contract 204/204, focused .NET contract tests 12/12, TransportSmoke build succeeded with a NuGet vulnerability-feed connectivity warning, and Bicep compiled with no template diagnostics. No cloud deployment or live Function invocation occurred. See `docs/internal/phase10-implementation-checklist.md` for the exact checkpoint.
- Current dirty-candidate OIDC/deployment changes and first Azure deployment are still unverified. Azure redeploy, Function indexing/invocation/quarantine/replay, provider contract, endpoint smoke and workflows `02`–`04` remain pending. Named regular-user Entra accounts are still needed before P6.1. Phase 10 remains open; historical Docker/L6 evidence is bound only to `494ab4fd`.

## Next action

Finish local workflow/static review, then obtain explicit authorization before committing or pushing. Only after hosted checks pass and the cost window is rechecked should a separate approval start additive workflow `01` with cleanup disabled. Verify Functions indexing and deployed quarantine; approved replay remains a separate gate. Then run `02`, `03`, and `04` in order. Cleanup remains destructive and requires immediate per-operation confirmation.

## Safety / navigation

- Local Docker SQL is loopback `14330`; native Windows SQL is `1433` and must remain untouched. Verify project ownership/physical SQL identity before separately approved DB work.
- The owner deleted `F:\DockerRetained\DockerDesktopWSL-before-G`; it is not a recovery backup. Do not touch unrelated F: backups.
- Preserve Docker volumes, provider settings and payment history. No resets, global prune, VHDX compaction, charges/refunds, Azure/directory writes or Git writes without explicit scoped approval.
- For older payment-history/currency and continuation limits, consult the existing runbook and Phase 11 deferral record; never infer old order state, force Paid, or retry/refund to resolve uncertainty.
- Canonical Phase 10 details: `docs/internal/phase10-implementation-checklist.md`; architecture and gate definitions: `docs/internal/phase10-preazure-lld.md`.
