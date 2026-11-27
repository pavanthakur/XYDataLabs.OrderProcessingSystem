# Active Work

Navigation, not proof. Verify current Git, Azure state and linked evidence before relying on this checkpoint.

## Redis-cost profile implementation — 28 November 2026

- Added an explicit dev-only `in-memory-single-replica-dev` profile for workflow `04` **service-preflight only**. Default remains `managed-redis`; supervised browser/payment handoffs still require that acceptance profile.
- With `deployRedis=false`, Bicep omits the Redis connection and caps the four cache-using Container Apps at one replica so the existing `IDistributedCache` memory fallback is process-local and bounded. Staging/prod are guarded to require Managed Redis.
- Fail-closed guards stop a dev deployment from switching to in-memory while the named Redis resource still exists. `deployRedis=false` never deletes Redis; an existing resource must be removed through separately reviewed cleanup.
- Validation performed locally: Phase 10 Azure static-preflight tests passed (65/65); Bicep build passed; Phase 10 environment contract passed (247 checks); AI-customization validation passed; documentation local-link check passed (201 links); `git diff --check` passed. No Azure workflow, deployment, live resource read, or payment was run. These changes are uncommitted and hosted CI is not run.
- Limitation: this is a lower-cost learning/preflight profile, not Redis, scale-out, payment, or Phase 10 acceptance evidence. Use Managed Redis for those gates.

## Phase 10 Azure-dev checkpoint — 27 November 2026

- Review revision: `a34a046ecc48631c277d5996db25c72aa6e81f93`
- Worktree state: `DIRTY`
- Evidence status: `BLOCKED`
- Evidence revision: `a34a046ecc48631c277d5996db25c72aa6e81f93`
- Evidence environment: `AZURE_DEV`
- Evidence scope: separate RBAC bootstrap identity setup, immutable release build, workflow 01 candidate/preflight/what-if dry-run; no app deployment, payments, transport, or replay acceptance.
- Evidence reference: `TestResults/Phase10/azure-dev-rbac-bootstrap-dryrun-2026-11-27.json`
- Phase 10 remains **OPEN**. The `a34a046e` code candidate was clean when the Azure run started; current worktree changes are documentation-only. Hosted CI Build/Contract, AI Customization, Documentation Links, Drift Scanner and related checks passed on this commit; ADR Markdown was skipped by its opt-in path filter.
- Azure-dev identity bootstrap was completed after scoped approval: app registration `XYDataLabs-OrderProcessing-Dev-RBAC-Bootstrap`, with GitHub `dev` environment federation restricted to this repository's `dev` environment. No client secret was created. GitHub `dev` now has `AZURE_RBAC_BOOTSTRAP_CLIENTID` as a secret and `AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID` as a variable.
- The bootstrap service principal has `Role Based Access Control Administrator` only at `/subscriptions/19f22d2f-1557-479b-a9b7-6dc6af67980c/resourceGroups/rg-orderprocessing-dev`, condition-limited to `Storage Blob Data Owner` role assignment writes/deletes for service principals. Azure read-back matched the repository preflight condition. The earlier temporary conditional grant on the routine deployment principal also remains; do not remove either grant without reviewing exact IDs and separately authorizing removal.
- Immutable release run [45878775895](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/45878775895) succeeded for candidate `a34a046e`; artifact `phase10-release-a34a046ecc48631c277d5996db25c72aa6e81f93` contains the new six-image set and Functions package. The older release from `0c83215f` predates the Functions host-storage RBAC split and must not be used for this deployment.
- Workflow `01` dry-run [45879063751](https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/runs/45879063751) passed release/source validation, origin/preflight, and the exact bootstrap permission check. Bicep subscription what-if succeeded. It proposed 24 creates and one modification (ACA managed environment); the 10 `- Microsoft.*` log entries are provider-registration status lines, not resource deletions. Workflow deploy, cleanup, SQL, Redis and Functions-trigger activation jobs were skipped. **No app/resource deployment was performed by workflow 01.**
- Next decision point: inspect the what-if against the intended clean rebuild, confirm current budget and approved test window, then obtain explicit approval before running `01` with `dryRun=false`. Current dry-run used `deploySql=false`, `deployRedis=false`, `cleanupInfra=false`, `activateExistingFunctionsTriggers=false`, region `centralindia`. It is not authorization to deploy or run transport, replay, or payment tests.
- Prior context: workflows `00` and `00a` created the platform ACR and Dev ACA foundation; generated origin is `salmonpebble-de10fde3.centralindia.azurecontainerapps.io`. The SPA redirect/logout URIs and matching GitHub `dev` origin variables were aligned. Preserve Entra users and API/SPA/OIDC registrations; resource-group cleanup must not delete directory identities/apps.
- Azure budget was last reported as ₹5,000 monthly alert; owner intended ₹6,000, but latest value was not rechecked in this run. A budget is an alert, not a spending cap. Previously agreed 35-hour window/hard stop was 28 Nov 2026 08:32 IST; confirm it is still applicable before any resource creation.
- After deployment: run runtime smoke, then separately approved transport checks; reconcile regular-user isolation and payment evidence only against matching deployed image/config fingerprints; verify replay approver and non-Owner runner before any replay mutation; resolve rollback applicability; then assemble candidate-bound L5-R/L6 results. Keep missing evidence BLOCKED/NOT RUN, never PASS.

See the [Phase 10 checklist](../../docs/internal/phase10-implementation-checklist.md), [Azure smoke runbook](../../docs/runbooks/phase10-azure-smoke.md), and [Member test-user runbook](../../docs/runbooks/phase10-entra-member-test-users.md).
