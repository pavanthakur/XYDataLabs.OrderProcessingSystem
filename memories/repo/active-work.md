# Active Work

Navigation only, not proof. Verify current Git, runtime and referenced evidence before relying on it.

## Phase 10 checkpoint — 22 November 2026

- Review base revision: `f09dd3a3d6048d1750f60875186b4515e81f6143`
- Worktree state: `DIRTY`
- Evidence status: `HISTORICAL`
- Evidence revision: `e73eb8c7dc3dba23b539e04c93821ff6818a8b94`
- Evidence environment: `LOCAL_DOCKER_DESKTOP_G`
- Evidence scope: `PASS for non-Azure local acceptance only; not Azure or full Phase 10 certification.`
- Evidence reference: `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261122-123240561/phase10-acceptance-reconciliation.json`
- Acceptance began and ended on clean revision `e73eb8c7dc3dba23b539e04c93821ff6818a8b94`; this handoff edit makes the current worktree dirty. No application or image inputs changed after the runs. NFR evidence is under `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261122-131843713/`.
- The sealed Docker E2E passed: 6 deterministic and 6 sandbox positive journeys across TenantA/B/C × Razorpay/OpenPay; 6 Razorpay negative/cancellation cases; 75 integration tests; tenant/identity/order checks; messaging and Functions effects; restoration; and Docker restart persistence. All 13 image identities matched.
- The Docker NFR wrapper seal and local replay selection passed. Performance was 100/100 messages/effects with P95 2.7232s; replay visibility 4.037s; outage recovery 28.793s with zero loss/duplicates; retained Inventory image rollback/restoration and security checks passed. Its dynamic payment category was intentionally skipped; the linked sealed E2E payment matrix covers the required local baseline. Reconciliation returned `PASS (scope: non-azure-local)`.
- Hosted CI on this candidate: CI/Contract, AI Customization, and Drift Scanner passed; ADR Markdown was skipped by path scope. Workflow 99 remains manual local-only under DW-028 Option A. No Azure operation occurred in these runs; this local PASS is not Azure or full Phase 10 certification.
- Remaining: perform separately approved Azure gates and reconcile their evidence before full Phase 10 closure. DW-023/DW-024 remain approved Phase 11 deferrals; Razorpay S2S and OpenPay visible-challenge/negative capabilities are uncertified. Order-payment success does not certify fulfillment or unresolved-payment recovery.
- Docker was left running; prior pre-run storage observation was about 437.6 GiB free on G: (not remeasured after the runs). Native SQL remains isolated at loopback `14330`; the F: retained copy was deleted.

## Azure dev

- Workflow 01 [44910591587](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44910591587) passed on workflow SHA `6fbc5454`, deploying immutable app source `47970357` (producer `44878244285`). SQL/Key Vault, migrations, Functions, tenant topology and post-deploy smoke passed.
- Workflow 02 [44912299578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44912299578) passed on `6fbc5454`: required hosts, generated dev URLs, gateway and same-origin UI/API checks passed. Details: `TestResults/Phase10/azure-runtime-smoke-44912299578/`.
- Workflow 03 [44913188578](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913188578) passed transport, fan-out effects and Functions quarantine/DLQ intake; temporary SQL firewall cleanup passed. It did **not** prove approved replay. Details: `TestResults/Phase10/azure-transport-smoke-44913188578/`.
- Workflow 04 [44913439630](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/44913439630) passed service-only Key Vault, App Insights, SQL and tenant/provider preflight (`servicePreflightOnly=true`, no orders/payments). Details: `TestResults/Phase10/azure-payment-preflight-44913439630/`.
- Azure-dev positive payment matrix: **PASS 6/6, resumed**, `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-21T17-21-05-312Z/summary.json`. Four prior cases were carried forward; TenantC/Razorpay was checked read-only and only TenantC/OpenPay ran fresh. Entra preflight, sign-out and restoration passed. Not uninterrupted/hosted acceptance. OpenPay 3DS was temporarily off; inspected baseline on, then restored.
- Workflow results are bounded to their recorded scopes; Azure cleanup was not verified.

### Azure deployment retry checkpoint — 22 November 2026

- Workflow 01 run [45009489149](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/45009489149) failed in nested deployment `keyvault-phase10-dev`: Azure rejected the Key Vault parent PUT because `properties.accessPolicies` was omitted. This disproves the prior assumption that omission preserves policies through the provider API.
- ARM operation inventory shows other independent modules succeeded before the Key Vault module failed, including Container Apps, Functions, ACA environment, App Insights, Service Bus, Log Analytics, identity and the resource group. Treat Azure dev as partially updated and not runtime-accepted until a successful redeploy and smoke. `deploySql=false`, `deployRedis=false`; no SQL password rotation was requested.
- A read-only follow-up saw the existing Key Vault and seven access policies; this is a current count, not a before/after preservation proof.
- Working-tree fix requires a live Key Vault access-policy snapshot, passes it to both legacy and Phase 10 templates in what-if and deploy, uses `[]` only for confirmed not-found, and fails closed on other read errors. Additive `accessPolicies/add` remains. Targeted 42-test suite, both Bicep builds, Azure static preflight, docs links and `git diff --check` passed locally. Fix is not yet committed, pushed, or deployed; no post-fix what-if exists.
- Next: review/stage only the eight intended fix/checkpoint files, commit and push to `dev` under the existing authorization, wait for hosted checks and immutable image release, then rerun dry-run with the exact dev parameters. Inspect the new Key Vault and SQL deltas before another deployment; only then redeploy without cleanup, SQL or Redis, and rerun runtime/transport/payment gates as separately authorized.

### Azure-dev replay preflight — 22 November 2026

- Sanitized live read-only inventory: `TestResults/Phase10/azure-dev-preflight-20261122-readonly.json`.
- The recorded Azure read-only inventory confirms the enabled dev subscription, existing dev environment and normal replay queue, but no isolated drill queue.
- The initial adapter used a fabricated run-specific namespace; corrected source now resolves FQDN, topic and dev-only queue fields from `runtime-targets.json`. IaC/parameter contracts create `dlq-replay-drill-requests-dev` only in dev and define optional queue Receiver + business-topic Sender roles for an explicitly supplied runner principal. Grants default absent; the live namespace inventory above predates this source change and no Azure resource/RBAC has been updated.
- The recorded deployment has four replay publishers against the normal queue; undeployed IaC enables only Orders. Workflow 01 validates optional dev variable `PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID` in what-if/deploy and explicitly selects type `User`; absent means no drill RBAC. Pause all publishers and route one request; Function stays on its normal queue.
- Recorded live preflight remains BLOCKED (5/21). Controller no longer silently exits; Route binds paused revisions/images and updates verify exact ready revisions. Mocked entrypoint lifecycle/recovery passed. Normal restore requires zero pending requests; safe restore keeps replay paused.
- Replay harness calls actual Function core; validates CLI identity, dev preflight/manifest, and dedicated DB against its Key Vault reference in memory. Send-gap uses distinct broker ID/stable envelope ID; PASS requires duplicate traces and exactly-once SQL effects. Restore report checks guarded fields and zero pending requests. Evidence paths reject traversal/reparse points; preflight checks App Insights Logs. Local selection: 9 passed, 1 expected live opt-in skip; no Azure operation.
- No deploy/RBAC/approval/broker/replay/effect ran. Live work still needs approved IaC deployment, scoped runner RBAC, `phase10-operator`, named A/B/C Entra users, and a retained rollback image.

## Next actions

1. Review and approve the Azure-dev deployment/replay prerequisites, then run only the approved Azure-dev workflow sequence and record each gate independently. The local Docker PASS above does not substitute for Azure evidence.
2. Keep staging/prod untouched until dev gates, restoration and cost/cleanup decisions are reviewed.
3. Do not repeat successful local sandbox payments solely to refresh evidence. Preserve Phase 11 and provider-capability deferrals as uncertified.

See [Phase 10 Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md) and [Phase 10 implementation checklist](../../docs/internal/phase10-implementation-checklist.md). Preserve ignored raw reports and failed/partial evidence; do not commit or push automatically.
