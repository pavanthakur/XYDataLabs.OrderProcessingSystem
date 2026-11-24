# Active Work

Navigation, not proof. Verify Git, Azure state and referenced evidence before relying on this checkpoint.

## Phase 10 Azure-dev checkpoint — 23 November 2026

- Review revision: d2fea63e6239e571dd92bb1811fc40659552b37a
- Worktree state: DIRTY
- Evidence status: BLOCKED
- Evidence revision: e5c40fbe6bbe91bd5a3a7b763e8fc218a23e3fd0
- Evidence environment: AZURE_DEV
- Evidence scope: Azure dev UI rollback and invalid-credential denial checks passed. Prior six sandbox journeys passed but used a dirty runner checkout. Regular-user isolation, non-Owner replay, signed expired-token check and final packet remain open; this is not Phase 10 acceptance.
- Evidence reference: TestResults/Phase10/azure-ui-rollback-20261123T153801198Z.json
- Base `dev` SHA `d2fea63e6239e571dd92bb1811fc40659552b37a` matches `origin/dev`. CI/Contract `45109596111`, AI Customization `45109595981`, and Drift Scanner `45109595799` passed on that SHA; this does not cover current uncommitted docs.
- Azure deployment `45067679429`, runtime smoke `45068970780`, and transport smoke `45069084216` passed on `e5c40fbe`. Workflow 04 `45072102164` was service-preflight, not hosted payments. Admin sign-in/switch/sign-out passed in the separate desktop matrix.
- Local Docker completion verifier passed for `phase10-docker-http-20261122-123240561`; it explicitly is not L5/L6 acceptance.
- Read-only replay preflight is 24/24 PASS at `TestResults/Phase10/azure-replay-preflight-20261123-current.json`. Live scoped RBAC shows only principal `99fce3f5-b801-4aa1-b2df-122900204d65` has isolated-queue Receiver and business-topic Sender, and that principal is subscription Owner. No replay mutation was run. A non-Owner runner is required.
- One protected TenantA replay passed earlier, but it does not prove duplicate delivery or exact settings restoration. Named non-admin Entra users for A/B/C are not configured/evidenced; admin access is not isolation proof.
- UI rollback follow-up passed: prior digest `sha256:3fe1d7dabb213ae1e3cf1def93d14cfef1eb3f4de242eefd0baf3374b945884e` was deployed temporarily and exact original `sha256:f2e9eacb36d51738fc97d753557791c02389e278a5a0bd20441f76c9301fd9c5` restored. Both revisions were ready/running; `/`, customer SPA route and Entra runtime-config checks passed. Scope was stateless UI only—no SQL/backend/payment change and no proof of stateful recovery. Evidence: `TestResults/Phase10/azure-ui-rollback-20261123T153801198Z.json`.
- Anonymous and malformed-Bearer calls to the protected customer list returned 401 for all three tenant headers (6/6). Evidence: `TestResults/Phase10/azure-invalid-credential-smoke-20261123T154645791Z.json`. This is not a signed expired-token or regular-user isolation test.
- No staging/prod action, directory/RBAC change, replay mutation, payment retry, SQL/schema change, or Azure cleanup occurred. The Azure-dev UI image was temporarily changed and restored during the rollback drill.

## Remaining before Phase 10 closure

1. Entra regular-user isolation tooling is implemented. Apply sent initial invitations/set claims for TenantB/C; TenantA already existed. After no email was received, the operator authorized resending to all tenants; Graph accepted three requests, but mail delivery was not verified. TenantA's direct My Apps attempt then returned `AADSTS500200` for its personal Microsoft account. The Azure-dev resource group is now absent, so live app/runtime discovery is unavailable. Under approval, a guarded TenantA-only redemption reset created a no-email link in a local Windows ACL-restricted file; sanitized report `TestResults/Phase10/entra-test-users/20261124T061640Z-4863ce1a/provisioning-summary.json` confirms no URL in evidence, no email, no claim/role changes. Await TenantA redemption and Verify before creating B/C links. Do not paste redemption links into chat. Signed expired-token denial and headed regular-user isolation remain unrun.
2. Establish a dedicated non-Owner replay runner with least-privilege queue/topic and publisher-control permissions. Run a fresh preflight, then the isolated duplicate/recovery drill; prove no duplicate/cross-tenant effects and exact settings restoration. Stop if restoration is unverified.
3. Decide whether L6 requires stateful-service rollback/recovery beyond the passed stateless UI image rollback. If yes, select a compatible digest and explicitly scope the service and state-preservation proof before mutation.
4. Reconcile L5-R/L6 into one packet bound to the actual source, deployment digests, configuration and artifacts. Preserve dirty-source provenance and mark unavailable evidence BLOCKED/NOT RUN. Do not repeat successful sandbox charges solely for report freshness.

Phase 10 remains OPEN. DW-023/DW-024 and unsupported payment capabilities remain deferred/unverified; they are not blockers for the bounded payment baseline. See [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md) and [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md).
