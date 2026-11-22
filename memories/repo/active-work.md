# Active Work

Navigation only, not proof. Verify current Git, runtime and referenced evidence before relying on it.

## Phase 10 checkpoint — 22 November 2026

- Review revision: `28de1e896a8aab2ac6b6221fd4e1779078b27736`
- Worktree state: `DIRTY`
- Evidence status: `FAIL`
- Evidence revision: `28de1e8`
- Evidence environment: `LOCAL_DOCKER_DESKTOP_G`
- Evidence scope: `Docker E2E passed; L5-R reconciliation failed on NFR binding/reporting. Azure excluded.`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261122-111249752/phase10-acceptance-reconciliation.json`
- Docker E2E on the clean candidate passed its selected hook: 6 deterministic + 6 sandbox positives across A/B/C × Razorpay/OpenPay, 6 Razorpay decline/dismissal cases, integration 75/75, tenant/identity/order checks, messaging, settings restoration and restart persistence. Provider and SQL proof exists; no live-money payments.
- Reconciliation is **FAIL**, not Phase 10 closure. The NFR lower-level run has no Docker-wrapper seal; its local filter also includes one intentionally skipped Azure-only replay test (28 passed/1 skipped). Other observed NFR checks passed: 100/100 messages, P95 2.413s, replay 3.032s, outage recovery 28.209s with zero loss/duplicates, rollback/restore and security.
- Next: narrowly exclude the Azure-only test from local NFR selection while keeping global skip handling fail-closed; rerun with `run-phase10-docker-nfr-proof.ps1` and reconcile. A changed candidate requires an explicit decision before repeating sandbox payments.
- Docker has 13 project containers running; G: had about 437.6 GiB free. Azure was not touched. Native SQL remains isolated at loopback `14330`; the F: retained copy was deleted.
- DW-023/DW-024 remain Phase 11 deferrals. Razorpay S2S and OpenPay visible-challenge capabilities remain uncertified.

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
