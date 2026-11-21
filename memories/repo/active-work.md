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
- Reviewed automation candidate: `dev` / `1afc4edd`; build/contract CI, AI customization, docs links and drift scan passed on that SHA. The Azure workflows below used `6fbc5454`; the immutable app release source was `47970357`.
- Local Docker Phase 10 remains **INCOMPLETE/BLOCKED**. The 20 Nov baseline, payment, persistence and NFR evidence is linked across runs but does not satisfy strict clean-source/same-candidate L5-R reconciliation. Do not rerun successful charges just to refresh evidence.
- Local evidence index: `TestResults/Phase10/local-followup-20261120-b9-current-payments-v12/index.html`; authoritative limitations and run-specific reports remain under ignored `TestResults/`. The deterministic payment runner's customer-growth drift check failed despite restored provider settings; the original seal remains unchanged.
- Baseline payment evidence: six deterministic and six real sandbox positives for TenantA/B/C × Razorpay/OpenPay passed with provider confirmation and SQL correlation. Razorpay decline/dismissal evidence is from an earlier candidate. Do not overclaim that it is current-candidate acceptance.
- Operational/recovery, performance, Functions, persistence, migration and rollback passed selected profiles, not one complete L5-R packet. Suite identity reconciliation and strict source/image binding remain open.
- Explicit gaps: Razorpay S2S unavailable; OpenPay visible 3DS challenge/negative behavior unverified; order continuation, installments, fulfillment and unresolved-payment recovery are DW-023/DW-024 Phase 11 deferrals. These are not certified.
- Docker storage was last verified on G: with 438.4 GiB free; local SQL guardrail is loopback port `14330`. Never redirect tests to native Windows SQL. The F: retained Docker copy was deleted and is not a recovery option.

## Azure dev

- Workflow 01 [44910591587](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44910591587) passed on workflow SHA `6fbc5454`, deploying immutable app source `47970357` (producer `44878244285`). SQL/Key Vault, migrations, Functions, tenant topology and post-deploy smoke passed.
- Workflow 02 [44912299578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44912299578) passed on `6fbc5454`: required hosts, generated dev URLs, gateway and same-origin UI/API checks passed. Details: `TestResults/Phase10/azure-runtime-smoke-44912299578/`.
- Workflow 03 [44913188578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913188578) passed transport, fan-out effects and Functions quarantine/DLQ intake; temporary SQL firewall cleanup passed. It did **not** prove approved replay. Details: `TestResults/Phase10/azure-transport-smoke-44913188578/`.
- Workflow 04 [44913439630](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913439630) passed service-only Key Vault, App Insights, SQL and tenant/provider preflight (`servicePreflightOnly=true`, no orders/payments). Details: `TestResults/Phase10/azure-payment-preflight-44913439630/`.
- Azure-dev positive payment matrix: **PASS 6/6, resumed**, `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-21T17-21-05-312Z/summary.json`. Four prior cases were carried forward; TenantC/Razorpay was checked read-only and only TenantC/OpenPay ran fresh. Entra preflight, sign-out and restoration passed. Not uninterrupted/hosted acceptance. OpenPay 3DS was temporarily off; inspected baseline on, then restored.
- Workflow results are bounded to their recorded scopes; Azure cleanup was not verified.

### Azure-dev replay preflight — 22 November 2026

- Sanitized live read-only inventory: `TestResults/Phase10/azure-dev-preflight-20261122-readonly.json`.
- The recorded Azure read-only inventory confirms the enabled dev subscription, existing dev environment and normal replay queue, but no isolated drill queue.
- The initial adapter used a fabricated run-specific namespace; corrected source now resolves FQDN, topic and dev-only queue fields from `runtime-targets.json`. IaC/parameter contracts create `dlq-replay-drill-requests-dev` only in dev and define optional queue Receiver + business-topic Sender roles for an explicitly supplied runner principal. Grants default absent; the live namespace inventory above predates this source change and no Azure resource/RBAC has been updated.
- The recorded deployment has four replay publishers against the normal queue; undeployed IaC enables only Orders. Workflow 01 validates optional dev variable `PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID` in what-if/deploy and explicitly selects type `User`; absent means no drill RBAC. Pause all publishers and route one request; Function stays on its normal queue.
- Recorded live preflight remains BLOCKED (5/21). Controller no longer silently exits; Route binds paused revisions/images and updates verify exact ready revisions. Mocked entrypoint lifecycle/recovery passed. Normal restore requires zero pending requests; safe restore keeps replay paused.
- Replay harness calls actual Function core; validates CLI identity, dev preflight/manifest, and dedicated DB against its Key Vault reference in memory. Send-gap uses distinct broker ID/stable envelope ID; PASS requires duplicate traces and exactly-once SQL effects. Restore report checks guarded fields and zero pending requests. Evidence paths reject traversal/reparse points; preflight checks App Insights Logs. Local selection: 9 passed, 1 expected live opt-in skip; no Azure operation.
- No deploy/RBAC/approval/broker/replay/effect ran. Live work still needs approved IaC deployment, scoped runner RBAC, `phase10-operator`, named A/B/C Entra users, and a retained rollback image.

## Next actions

1. Replay/inbox 11/11 with run-owned DB cleanup and unchanged provider metadata; harness 9 pass/1 live opt-in skip. Entrypoint, preflight and config tests passed; env contract 245/245, docs 197/197. Legacy workflow-config failures and ownership runner-DB guard remain. Review the fixes before committing; no live replay proved.
2. Next replay action: clear the live preflight blockers only after separately approved IaC deployment and scoped runner identity. Then run the protected API approval, one-request pause/route, each opt-in failure case, exact restoration and effect verification. Normal deployed Function replay, Entra regular-user isolation/expiry, payment negatives, Azure NFR/rollback remain open. Do not repeat successful payment cases just to refresh evidence.
3. Do not run staging/prod or modify deployment, directory, provider or database settings without specific approval.

See [Phase 10 Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md) and [Phase 10 implementation checklist](../../docs/internal/phase10-implementation-checklist.md). Preserve ignored raw reports and failed/partial evidence; do not commit or push automatically.
