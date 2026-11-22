# Active Work

Navigation only, not proof. Verify current Git, runtime and referenced evidence before relying on it.

## Phase 10 checkpoint — 22 November 2026

- Review revision: `d7ced7cc7373c89534f0c74ea72217c20b8bdd27`
- Worktree state: `DIRTY`
- Current uncommitted change: Key Vault snapshot normalization; see Azure deployment retry checkpoint below.
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

- Workflow 01 [45009489149](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/45009489149) failed: the Key Vault API requires `properties.accessPolicies`. Other modules, including Container Apps, Functions, monitoring, Service Bus, identity and the RG, succeeded first. Dev is partially updated; SQL/Redis were disabled. A later read saw seven policies (no before/after proof).
- Fix `244fc6f6` snapshots policies for what-if/deploy and fails closed on read errors. After shortening this handoff, clean candidate `d7ced7cc` passed CI/Contract `45011590723`, AI customization `45011590737`, and Drift `45011590722`. Immutable release `45012244450` passed. What-if `45012479244` passed (10 modify, 18 unchanged, 1 unsupported additive policy, 7 ignored); Key Vault parent was no-change and SQL resources were ignored.
- Actual redeploy `45012798453` failed at Key Vault with `accessPolicies[0].Permissions.certificates` invalid; other modules again succeeded first. Azure CLI’s live policy snapshot has seven entries; absent certificate/key/storage permissions and `applicationId` are serialized as null. The current uncommitted fix normalizes only these optional nulls, preserves all non-null grants, and fails closed on malformed data. Local regression suite passed 94/94; both Bicep builds and live-snapshot normalization passed (7 policies, 15 granted permission entries). Dev remains partially deployed; SQL/Redis stayed disabled.
- Next: review and commit/push the normalizer, wait for exact-SHA hosted CI, rebuild immutable images/package, run what-if and verify Key Vault parent is unchanged, then redeploy with cleanup/SQL/Redis off. Run runtime smoke only after a successful deploy; do not yet claim Azure acceptance.

### Azure-dev replay preflight — 22 November 2026

- Sanitized live read-only inventory: `TestResults/Phase10/azure-dev-preflight-20261122-readonly.json`.
- Inventory confirms dev and the normal replay queue exist, but the isolated drill queue does not. Updated code uses runtime-target queue metadata; IaC creates the dev-only queue and optional scoped Sender/Receiver roles, but no Azure resource/RBAC change has run.
- Current deployment has four publishers on the normal queue; only Orders is configured for the isolated drill. Workflow pauses/reroutes one publisher while Functions stays on normal intake.
- Live replay preflight is BLOCKED (5/21). Local controller/harness checks passed 9 with one expected live-opt-in skip. No broker replay or downstream effect ran. Remaining: isolated queue and scoped runner grant, `phase10-operator`, named Entra test users, and a retained rollback image.

## Next actions

1. Review and approve the Azure-dev deployment/replay prerequisites, then run only the approved Azure-dev workflow sequence and record each gate independently. The local Docker PASS above does not substitute for Azure evidence.
2. Keep staging/prod untouched until dev gates, restoration and cost/cleanup decisions are reviewed.
3. Do not repeat successful local sandbox payments solely to refresh evidence. Preserve Phase 11 and provider-capability deferrals as uncertified.

See [Phase 10 Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md) and [Phase 10 implementation checklist](../../docs/internal/phase10-implementation-checklist.md). Preserve ignored raw reports and failed/partial evidence; do not commit or push automatically.
