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
- Current local branch/HEAD: `dev` / `6e03e4885c9a48d331beb20c3f94be02698e3637` (handoff commit, not pushed). The Azure workflow runs below used GitHub `dev` SHA `6fbc5454d56f4f9159ff027f620bc2135c9fd600`, which remains the deployed/tested code revision; the local commit only updated this handoff.
- Local Docker Phase 10 remains **INCOMPLETE/BLOCKED**. The 20 Nov baseline, payment, persistence and NFR evidence is linked across runs and does not satisfy strict clean-source/same-candidate L5-R reconciliation. Do not rerun successful charges just to refresh evidence.
- Local evidence index: `TestResults/Phase10/local-followup-20261120-b9-current-payments-v12/index.html`; authoritative limitations and run-specific reports remain under ignored `TestResults/`. The deterministic payment runner's customer-growth drift check failed despite restored provider settings; the original seal remains unchanged.
- Baseline payment evidence: six deterministic and six real sandbox positives for TenantA/B/C × Razorpay/OpenPay passed with provider confirmation and SQL correlation. Razorpay decline/dismissal evidence is from an earlier candidate. Do not overclaim that it is current-candidate acceptance.
- Operational/recovery, performance, Functions, persistence, migration and rollback evidence passed in selected profiles, but not as one complete L5-R packet. Full suite identity reconciliation and strict source/image binding remain open.
- Explicit gaps: Razorpay S2S unavailable; OpenPay visible 3DS challenge/negative behavior unverified; order continuation, installments, fulfillment and unresolved-payment recovery are DW-023/DW-024 Phase 11 deferrals. These are not certified.
- Docker storage was last verified on G: with 438.4 GiB free; local SQL guardrail is loopback port `14330`. Never redirect tests to native Windows SQL. The F: retained Docker copy was deleted and is not a recovery option.

## Azure dev

- Workflow 01 deployment run [44910591587](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44910591587) passed on workflow SHA `6fbc5454`; immutable release source `47970357` came from producer run `44878244285`. SQL bootstrap/Entra admin and Key Vault checks, migrations/runtime SQL grants, Functions package/indexing, A/B/C topology, provider aliases and post-deploy smoke passed. It supersedes the prior failed deployment run `44884659409`; that historical failure is not current status.
- Standalone workflow 02 runtime smoke [44912299578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44912299578) passed on `dev` SHA `6fbc5454`. All seven required hosts were healthy/running; tenant topology passed (A/B shared Razorpay, C dedicated OpenPay); live generated dev origins resolved; gateway health/routing, gateway runtime configuration, UI shell and UI same-origin API proxy returned HTTP 200. Summaries are downloaded under ignored `TestResults/Phase10/azure-runtime-smoke-44912299578/`.
- Workflow 03 transport smoke [44913188578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913188578) passed on `dev` SHA `6fbc5454`: broker topology, one fan-out message with Inventory/Notifications 1/1 durable effects, malformed-message DLQ forwarding and Functions quarantine persistence passed; a second fan-out reached 2/2 effects. Its owned temporary SQL firewall rule was verified removed. It did not prove DLQ replay. Evidence is under ignored `TestResults/Phase10/azure-transport-smoke-44913188578/`.
- Workflow 04 service preflight [44913439630](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913439630) passed on `dev` SHA `6fbc5454`: Key Vault reads, App Insights Logs access, Azure SQL read access to shared and dedicated databases, A/B/C provider topology and firewall-lease cleanup. It ran with `servicePreflightOnly=true`; it created no orders or payments. Evidence is under ignored `TestResults/Phase10/azure-payment-preflight-44913439630/`.
- The full local headed payment-matrix attempt `payment-automation-azure-matrix-2026-11-21T14-25-18-432Z` did **not** reach fixture/order/payment mutation: the Entra browser token was unavailable within five minutes. The report records `operatorAuthPreflight=FAIL`, 0/6 cases and no order/payment attempted. Both operator/fixture locks are absent. Do not retry until the operator completes normal sign-in in the launched headed Playwright window. GitHub-hosted workflow 04 full-payment mode does not supply required `--headed --operator-assisted-entra` flags; do not treat its service preflight as payment acceptance.
- Workflow 02 used OIDC/control-plane reads and HTTP GETs. Workflow 03 intentionally published transport test messages and wrote downstream/Functions quarantine state; it did not replay messages. Workflow 04 preflight did not create orders/payments. Report only each run's recorded scope. Keep deployment resources/budget under operator review; cleanup was not part of this work.

## Next actions

1. Complete normal Entra sign-in in the supported headed local operator runner, then run the serial TenantA/B/C × Razorpay/OpenPay sandbox matrix once with provider/SQL/callback verification and exact provider-setting restoration. Do not bypass MFA or retry an ambiguous charge.
2. Keep approved DLQ replay separate; workflow 03 did not prove replay. Keep Azure cleanup separate as well.
3. Do not run staging/prod or modify deployment, directory, provider or database settings without specific approval.

See [Phase 10 Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md) and [Phase 10 implementation checklist](../../docs/internal/phase10-implementation-checklist.md). Preserve ignored raw reports and failed/partial evidence; do not commit or push automatically.
