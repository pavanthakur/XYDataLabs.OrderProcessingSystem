# Active Work

Navigation only, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 23 November 2026 (updated after supervised matrix)

- Review revision: `e5d4450ca7a1db028b34f89b1b6888d04b951d33`
- Worktree state: `CLEAN`
- Evidence status: `HISTORICAL`
- Evidence revision: `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`
- Evidence environment: `AZURE_DEV`
- Evidence scope: `Deployment/runtime/transport and replay evidence remain as recorded. The supervised six-case sandbox matrix passed all tenants/providers with Entra sign-in/sign-out; its durable checkpoint binds six verified/restored receipts to candidate/settings/deployment fingerprints, and live Azure matches the deployment fingerprint. No app-service code differs between deployed source e5c40fbe and reviewed 47212586. Payment gate is PASS for deployed dev; dirty-source overall sign-off remains open.`
- Evidence reference: `TestResults/Phase10/azure-dev-evidence-review-20261123.md`
- Base candidate: `dev` at `e5d4450ca7a1db028b34f89b1b6888d04b951d33`, aligned with `origin/dev`; worktree clean after the evidence update.
- Exact-SHA hosted checks passed on `e5d4450ca7a1db028b34f89b1b6888d04b951d33`: CI/Contract `45108623366`, AI Customization `45108623933`, Documentation Links `45108623721`, Drift Scanner `45108623525`. This is documentation/governance publication only, not Azure or Phase 10 runtime acceptance.
- Current deployed application release: source `e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0`; deployment `45067679429`, runtime smoke `45068970780`, transport smoke `45069084216`, workflow-04 service preflight `45072102164` passed. Transport proves consumer effects and Functions quarantine intake, not approved deployed replay.
- Latest local Docker completion verifier passed for `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261122-123240561/`; the tool explicitly limits this to run finalization, not L5/L6 or revision acceptance.
- Read-only replay preflight `TestResults/Phase10/azure-replay-preflight-20261123-current.json`: **24/24 PASS**, no mutation, runner `99fce3f5-b801-4aa1-b2df-122900204d65`. It verifies the isolated/normal queues, expected single-publisher baseline, Functions normal queue, App Insights query access and scoped runner roles. The supplied runner is also subscription Owner and has API `platform-admin` and `phase10-operator`; use a dedicated non-Owner identity for least-privilege live replay testing. This is readiness only; no duplicate-delivery or exact restoration proof.
- A one-time protected TenantA replay has prior verified SQL evidence under ignored `TestResults/Phase10/azure-dlq-replay-20261123/`. It is not the isolated duplicate-redelivery drill and does not prove all-tenant deployed replay.
- New supervised payment matrix `TestResults/Playwright/azure-https/payment-automation-azure-matrix-2026-11-23T03-05-07-229Z/` passed 6/6 sandbox journeys across TenantA/B/C × Razorpay/OpenPay. Entra access/switch and sign-out passed; provider verification passed and fixture cleanup is `reset` for all six. Razorpay hosted INR challenge passed; OpenPay MXN was configured 3DS-off (challenge not applicable). Durable checkpoint `TestResults/Playwright/azure-https/payment-automation-2026-11-23T03-05-07-229Z/checkpoint.json` records all six as `verified-restored` and binds candidate `ee366fe7...`, deployment `8899692F...`, and settings `F9860861...`; a read-only live Azure query reproduced the deployment fingerprint, and the SQL firewall lease manifest is `removed`. Source diff e5c40fbe→47212586 has no application-service code changes, so this closes the payment gate for deployed dev images; source was dirty, so overall clean-candidate sign-off remains open.
- Entra API app has `platform-admin` and `phase10-operator`; both roles are assigned to the same runner/admin user. The `extn.applicationTenantCode` access-token claim is configured and its user extension property exists. No regular-user claim values or Azure isolation tests were verified. Named TenantA/B/C Entra test users are still needed.
- Workflow 04 run `45072102164` remains a `service-preflight`, not browser payments. The later desktop operator matrix above is separate supervised evidence and is not a hosted workflow payment result.
- The earlier no-charge Entra attempt `payment-automation-azure-matrix-2026-11-22T23-34-39-935Z` timed out before application access and is superseded for admin sign-in by the successful 23 November matrix. It remains historical failure evidence; the successful admin flow does not establish regular-user isolation.
- The checklist now records the 23 November Azure evidence checkpoint. Its update was pushed as `b534e70f`; exact-SHA CI/contract, documentation links and drift checks passed. Detailed read-only findings: `TestResults/Phase10/azure-dev-evidence-review-20261123.md` (ignored local evidence; preserve raw reports).

## Remaining before Phase 10 closure

1. Build the final Phase 10 acceptance packet from the retained matrix checkpoint plus deployment/runtime/transport, Docker/NFR and CI evidence. Preserve the exact dirty-source identity as a limitation; if the reconciler requires a clean source, establish a clean candidate and rerun only affected non-charge gates. Do not repeat successful charges solely to refresh the report.
2. Provide/approve named regular-user Entra accounts and verify API-token tenant claims, own-tenant allow, cross-tenant denial, invalid/expired token rejection and logout.
3. Establish a dedicated non-Owner replay runner with only scoped roles. After separate replay approval, execute the isolated replay and duplicate-delivery/fault-injection cases; verify exact publisher-settings restoration and durable effects. Fresh preflight is mandatory immediately before mutation.
4. Execute/verify Azure recovery and rollback, then reconcile one candidate-bound acceptance packet. An available prior image is not rollback proof.

The supervised matrix created six sandbox test transactions and reports fixture cleanup as reset. No deployment, directory/RBAC change or replay mutation occurred during the documentation follow-up. Keep Phase 10 open; staging/production and approved Phase 11/provider-capability deferrals remain outside this acceptance.

See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
