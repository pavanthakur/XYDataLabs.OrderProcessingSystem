# Active Work

Navigation only, not proof. Verify current Git, runtime and referenced evidence before relying on it.

## Phase 10 checkpoint — 21 November 2026

- Review revision: `6fbc5454d56f4f9159ff027f620bc2135c9fd600`
- Worktree state: DIRTY
- Evidence status: `BLOCKED`
- Evidence revision: `9a433be5`
- Evidence environment: `LOCAL_DOCKER_DESKTOP_G`
- Evidence scope: `Selected Docker E2E, payment, restart, migration and NFR checks; strict clean-source/same-candidate L5-R reconciliation remains incomplete; Azure excluded from this evidence`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261120-232300248/acceptance-packet.json`
- This local Docker evidence is historical and not the Azure deployment revision.
- Current branch/revision last verified: `dev` / `6fbc5454d56f4f9159ff027f620bc2135c9fd600`. Do not treat this run SHA as current if `dev` has advanced.
- Local Docker Phase 10 remains **INCOMPLETE/BLOCKED**. The 20 Nov baseline, payment, persistence and NFR evidence is linked across runs and does not satisfy strict clean-source/same-candidate L5-R reconciliation. Do not rerun successful charges just to refresh evidence.
- Local evidence index: `TestResults/Phase10/local-followup-20261120-b9-current-payments-v12/index.html`; authoritative limitations and run-specific reports remain under ignored `TestResults/`. The deterministic payment runner's customer-growth drift check failed despite restored provider settings; the original seal remains unchanged.
- Baseline payment evidence: six deterministic and six real sandbox positives for TenantA/B/C × Razorpay/OpenPay passed with provider confirmation and SQL correlation. Razorpay decline/dismissal evidence is from an earlier candidate. Do not overclaim that it is current-candidate acceptance.
- Operational/recovery, performance, Functions, persistence, migration and rollback evidence passed in selected profiles, but not as one complete L5-R packet. Full suite identity reconciliation and strict source/image binding remain open.
- Explicit gaps: Razorpay S2S unavailable; OpenPay visible 3DS challenge/negative behavior unverified; order continuation, installments, fulfillment and unresolved-payment recovery are DW-023/DW-024 Phase 11 deferrals. These are not certified.
- Docker storage was last verified on G: with 438.4 GiB free; local SQL guardrail is loopback port `14330`. Never redirect tests to native Windows SQL. The F: retained Docker copy was deleted and is not a recovery option.

## Azure dev

- Workflow 01 deployment run [44910591587](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44910591587) passed on workflow SHA `6fbc5454`; immutable release source `47970357` came from producer run `44878244285`. SQL bootstrap/Entra admin and Key Vault checks, migrations/runtime SQL grants, Functions package/indexing, A/B/C topology, provider aliases and post-deploy smoke passed. It supersedes the prior failed deployment run `44884659409`; that historical failure is not current status.
- Standalone workflow 02 runtime smoke [44912299578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44912299578) passed on `dev` SHA `6fbc5454`. All seven required hosts were healthy/running; tenant topology passed (A/B shared Razorpay, C dedicated OpenPay); live generated dev origins resolved; gateway health/routing, gateway runtime configuration, UI shell and UI same-origin API proxy returned HTTP 200. Summaries are downloaded under ignored `TestResults/Phase10/azure-runtime-smoke-44912299578/`.
- Workflow 02 proves runtime reachability, control-plane health and bootstrap/topology contracts only. It does not prove Azure Service Bus consumption, Functions downstream effects/replay, payment-provider acceptance or full Azure E2E. Workflows 03 (transport) and 04 (sandbox payments) remain separate and have not been run in this sequence. They require their own scoped approval and must not be inferred from 01/02.
- The smoke used OIDC for Azure control-plane reads and HTTP GETs; no messages/orders/payments were created. Do not claim live Azure state beyond the recorded workflow evidence without a fresh read-only check. Keep deployment resources/budget under operator review; cleanup was not part of this work.

## Next actions

1. Review the successful 02 artifact and exact run SHA before any further Azure work.
2. Separately plan/approve workflow 03, reviewing published messages, downstream SQL effects, bounded wait and recovery behavior first.
3. Separately plan/approve workflow 04, confirming sandbox-only credentials, serial tenant/provider matrix, callback/provider/SQL proof and no automatic retry of ambiguous charges.
4. Keep Azure cleanup and workflows 03/04 separate. Do not modify deployment, directory, provider or database settings without specific approval.

See [Phase 10 Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md) and [Phase 10 implementation checklist](../../docs/internal/phase10-implementation-checklist.md). Preserve ignored raw reports and failed/partial evidence; do not commit or push automatically.
