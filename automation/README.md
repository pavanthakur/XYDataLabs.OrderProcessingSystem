# Payment Automation Workspace

This workspace is intentionally separate from `frontend/` and from the .NET solution. It hosts
browser-driven payment journey automation without coupling that work to the React application or
to backend test projects.

## Current Status

The initial local and Docker pilots are implemented for the React payment flow and OpenPay sandbox 3DS.
Azure execution is catalog-driven for `dev`, `stg`, and `prod`. The active Phase 10 path resolves
Azure Container Apps URLs at workflow runtime, with verification staying script-first through
Application Insights and Azure SQL.

## Initial Scope

- Runtime target resolution
- Tenant execution catalog resolution
- Local browser execution for `local-http` and `local-https`
- Docker browser execution for `docker-dev-http`, `docker-dev-https`, `docker-stg-http`, `docker-stg-https`, `docker-prod-http`, and `docker-prod-https`
- Azure browser execution for `azure-dev`, `azure-stg`, and `azure-prod`
- OpenPay sandbox challenge handling with OTP `999`
- Verification adapter boundary to the existing PowerShell verification scripts
- Per-run report composition under `automation/reports/`
- Service automation adapter registry for later provider/runtime expansion

## Callback acceptance guardrails

- Local Razorpay runs let the application finish `ProcessPayment` and navigate using its persisted provider payment ID. Automation must not invent an ID or force navigation after clicking Pay.
- A visible callback error is a failed journey, even if database verification would pass. No loading panel, an informational banner, or a pending timeout is not proof of success. Completion requires an explicit settled success banner.
- Callback readiness is polled for up to 60 seconds. Pending reconciliation is reported as pending rather than completed; local/Docker callbacks receive no special not-found exception.
- Run `npm --prefix automation run test:callbacks` for browser-free outcome tests and `npm --prefix automation run test:callbacks:browser` for Chromium-backed error, delayed-render, pending-timeout, and conflicting-banner regressions. Install Chromium first with Playwright if absent. PR CI runs the unit guardrails.
- Then run the Docker provider matrix with physical verification. Deterministic local adapters prove local behavior, not real provider sandbox transactions.

## Phase 10 report preview

For an existing run, generate a limited, offline preview without starting tests or
accessing Docker, databases or providers:

```powershell
npm --prefix automation run report:phase10-preview -- <run-directory>
npm --prefix automation run verify:phase10-completion -- <run-directory>
npm --prefix automation run test:phase10-report
```

The command reads `acceptance-packet.json`, `run-summary.json`, and, when
available, `foundations/summary.json`, five foundation TRX files,
`foundations/frontend-vitest.json`, six automation result files, five foundation
.NET discovery records, and `integration/integration-1.trx` plus its sanitized
discovery record from that directory and creates
`index.html`, the compatible `phase10-preview.html` alias, and a sanitized aggregate `phase10-coverage-summary.json`
there. Open `index.html` for the offline report. The preview links only to this fixed-name summary, generated from
normalized counts; it does not link raw coverage, logs or other artifacts.
The files are created exclusively and never overwritten. An interrupted or
failed write can leave an empty preview or partial output; treat it as incomplete
and use a new run directory rather than trusting or overwriting it.
Only generated run IDs matching `phase10-docker-http-YYYYMMDD-HHMMSSfff`
are displayed; custom IDs are shown as UNKNOWN.
The preview is **not** a complete L5-R acceptance dashboard: it cannot certify a run or revision,
collect coverage itself, prove the full Phase 10 expected-suite inventory, or replace L5/L6 gates. Its
overall result remains BLOCKED unless reported evidence contains a failure.
Missing or malformed input is displayed as incomplete; successful rendering
only confirms that the preview file was written.
The Docker E2E hook also attempts this preview after writing its run packet,
including on failure when finalization can execute. A preview-generation failure
marks the hook run failed; a generated preview remains non-certifying and does
not replace independent L5/L6 gates. The hook requires a new run directory and
rejects an already-used run ID rather than overwriting evidence. Forced process
termination can prevent finalization. If the hook warns that it could not
persist a failure, treat any existing packet and summary as untrusted.
After artifact generation and lock/environment cleanup, the hook publishes
`phase10-completion.json` with the run ID, recorded status and SHA-256 hashes of
the packet, JSON summary, preview, sanitized coverage summary, offline index, and
the before/after Docker image identity manifests. New records use
`phase10-completion-v4`; the verifier continues to accept valid v1-v3 records
for their original artifact sets. Historical v1-v3 records do not satisfy the
new image-identity gate.
The manifests require the complete 13-service `xy-phase10` inventory, validate
project/service ownership, and bind image references, local image IDs, available
repository digests, candidate revision, capture stage, and build-log hashes.
Before/after evidence must retain the same service image identities. Repository
digests are local observations when available; they do not prove registry
publication. The preview displays validated identities but remains provisional
and never becomes an acceptance verdict.
Verify the completion record using the command above before
using those artifacts. Missing, malformed or mismatched records and interrupted
finalization are INCOMPLETE. The verifier exits 0 only for a matching record
with recorded status `passed`, 1 for a matching `failed` record, and 2 for
`partial`, incomplete, or verification errors. COMPLETE describes finalization,
not L5/L6 acceptance or a verified revision. Historical runs without a record
remain incomplete under this contract; do not generate a record for them.
The static preview cannot recheck the record when opened and always labels its
contents provisional. Hashes detect inconsistent artifacts, not deliberate
tampering by someone able to rewrite both the record and files; other raw
evidence is not bound by this record. The linked summary contains only
aggregate normalized counts and scope labels; it is not raw coverage or an
independent proof of revision identity. Verification does not prevent later
changes to files.
For a separately approved candidate run, pass the E2E start manifest to NFR so
it validates the exact same local images before and after its drills:

```powershell
pwsh -NoProfile -File scripts/run-phase10-docker-nfr-proof.ps1 `
  -SkipStartIfNeeded `
  -ExpectedImageManifest '<e2e-run-directory>\docker-image-identities-before.json'
```

The wrapper rejects a missing, malformed, dirty-candidate, foreign-project, or
image-mismatched manifest before starting its NFR proof. The acceptance
reconciler independently compares the E2E and NFR image inventories.
Validate the isolated hook finalization (no Docker, database, or payment calls)
with `pwsh -NoProfile -File scripts\tests\test-phase10-report-finalization.ps1`.
Validate hashed .NET discovery/TRX reconciliation and failure preservation with
`pwsh -NoProfile -File scripts\tests\test-phase10-dotnet-inventory.ps1`; this
mocked regression does not run the database-backed integration suite.
The preview displays recorded profile, payment-suite selection, timestamps,
restoration and storage exit status when present. It marks selection UNKNOWN
for steps whose selection is not recorded; it does not infer that they are optional.
It summarizes fixed packet-step and foundation-check inventories separately by
status and shows packet selection counts separately. These are check counts,
not test totals or a complete Phase 10 suite inventory. Duplicate entries count
as BLOCKED; a conflicting failure still drives the overall result to FAIL.
A packet reporting PASS with a selected primary payment suite that is not PASS is
explicitly flagged as contradictory; it does not certify the other steps.
The hook also records Git HEAD and clean/dirty worktree observations at start
and finish without storing changed file names or refreshing the Git index.
Unavailable observations remain UNKNOWN. These snapshots do not prove file contents, continuous worktree
integrity, build provenance, image digests, or the identity of a reused stack.
The foundation section reconciles expected runner checks and their time windows;
it does not prove revision identity.
The expected-result inventory lists five foundation TRX sources, frontend
Vitest, integration TRX, and six automation test checks, with runner status
and reconciled result status shown separately. The five .NET suites discover
test cases from the just-built assemblies before executing the exact same
assemblies, compare hashed discovered identities with TRX, and expose only
hashed IDs/statuses. Frontend Vitest emits a same-run hashed case inventory and
sanitized outcomes. The six automation suites are
checked against `config/phase10-automation-test-inventory.json`; the runner
writes stable hashed test IDs and sanitized outcomes under `automation-tests/`.
Each result records the inventory SHA-256, which must match the report-time
inventory. Missing, duplicate, unexpected, skipped, failed, or stale cases
block or fail that suite. Integration discovery is filtered before execution;
its hashed case IDs and statuses must match the actual TRX `testName` identities,
not merely aggregate counters. These thirteen structured sources are only part
of the Phase 10 inventory; acceptance, scenario, identity,
messaging, persistence and operational gates remain independently inventoried
or explicitly unavailable as described in the Phase 10 contract.
For valid structured evidence, the preview shows up to 100 anonymous hashed IDs
and outcomes per source; raw test names and failure details are not emitted.
Counts cover every reconciled outcome even when the list is truncated. Missing
or invalid sources show UNAVAILABLE. The report does not yet inventory every
packet-level scenario, acceptance case, or operations gate, so passing structured
unit/integration inventories alone cannot establish full acceptance.
Foundation coverage is available only when both the runner and the corresponding
structured test result pass reconciliation; missing, invalid or partial test
results make coverage UNAVAILABLE even if the runner exited successfully.
It also reads the five fixed `foundations/{Domain,Application,API,Gateway,Architecture}.trx`
files to display per-project counts when XML, counters, runner status and timing
reconcile. Missing or invalid TRX counts are UNAVAILABLE, not zero; raw test
names and failure text are not included. Other test formats are not yet collected.
Integration is checked only against the overall run window because the existing
step timestamps do not cover the test execution. Duplicate integration TRX files
are blocked. The foundation runner emits sanitized `frontend-vitest.json` containing
only timestamps, run outcome and test states; the default console log remains
subject to the existing log-redaction policy. Existing historical runs without
that file remain unavailable. No raw test names or failure messages appear in
the structured frontend evidence or preview.
The foundation runner collects Vitest V8 coverage for web-app `src/**/*.ts`
and `src/**/*.tsx`, excluding tests, `src/test`, and declarations. It writes
line/branch counts and detailed HTML to `foundations/frontend-coverage`; it
refuses an existing output directory. The preview displays only aggregate
counts when the frontend check passed and the summary's modification time
matches its test window. This timestamp is not proof of run identity; the
completion record does not bind raw coverage. Shared frontend packages,
backend tests and deployed services are not measured
by this lane. No coverage threshold is enforced. Detailed HTML contains source
and paths and must not be shared until separately reviewed and sanitized.
The foundation runner also collects Coverlet Cobertura XML separately for the
Domain, Application, API, Gateway and Architecture test projects, using
`scripts/phase10-foundation-coverage.runsettings`. It includes matching
`XYDataLabs.OrderProcessingSystem.*` assemblies, excludes test assemblies,
migrations, generated `.g.cs` files and `obj` files, and does not instrument
deployed services. A project may cover multiple assemblies and scopes may
overlap; the preview shows each test project's aggregate separately and never
sums them. Missing, duplicate, malformed, oversized or out-of-window XML and
zero valid lines or branches display as UNAVAILABLE. Timestamp matching does not
prove run or revision identity, and the completion record does not bind raw
coverage. Cobertura XML includes source paths and must not be shared without
review and sanitization. The runner generates a separate detailed HTML report
at `foundations/backend-coverage/<test-project>/html/index.html` using the
repository-local ReportGenerator pinned in `.config/dotnet-tools.json`.
Run `dotnet tool restore` from the repository root before the foundation
runner; no tool restore occurs automatically. Report generation validates the
XML and counts, refuses to overwrite a report, and fails the foundation check
if the tool or its output is missing or its totals do not match the validated
XML class lines. The preview reports Coverlet XML root branch totals; detailed
HTML reports only branches attached to class source lines. Coverlet's root
can include branches that its XML does not attach to any line: the runner
warns when these totals differ. For example, an isolated Application run
reported 1,054 valid root branches and 1,048 line-attached branches. Neither
figure is a merged total or a coverage threshold. A report that does not match
its expected line-attached counts is left for inspection and fails closed.
Detailed HTML contains source and paths
and must not be shared without review and sanitization; it is not linked from
the preview or bound by the completion record. Validate this lane with
`pwsh -NoProfile -File scripts\tests\test-phase10-backend-coverage-html.ps1`.
It defaults to Domain and uses `--no-build --no-restore`; other projects can
be selected with `-Project` when invoking it from PowerShell. These checks do
not prove current-candidate build identity.
The Phase 10 Docker E2E integration step requests Coverlet for the isolated
`Category=Integration` test process using the same scoped runsettings. Other
integration callers do not collect coverage unless `-CollectCoverage` is
explicitly selected. For each filter it writes `integration/coverage-<index>/`
and copies the TRX to `integration/integration-<index>.trx`, preserving the
original and collector attachments. It refuses to overwrite output and fails
the integration step when successful tests lack a single bounded collector
file or TRX. The preview supports the one-filter E2E case only: missing,
duplicate, malformed, failed or outside-run-window evidence is UNAVAILABLE.
It shows integration test-process totals separately, without summing them
with foundation coverage; this does not measure Docker-hosted services. XML
and attachments can contain paths and must not be shared without review and
sanitization; no detailed integration HTML or raw link is generated. The
completion record binds the sanitized summary, not raw integration coverage.
Validate collection without a database using
`pwsh -NoProfile -File scripts\tests\test-phase10-integration-coverage.ps1`;
that test uses existing build outputs and a narrow non-database filter.
Full isolated integration execution still requires separately approved database
access. No coverage threshold is enforced.

## Placeholder

```powershell
npm --prefix automation run placeholder
```

The placeholder command resolves a sample target and invokes the registered no-op service adapter.

## Single-Target Runs

Dry-run the payment automation runner:

```powershell
npm --prefix automation run run:dry
```

Run against a real local target:

```powershell
npm --prefix automation run run -- --target local-http --tenant TenantA
```

Run all supported tenants against one local target:

```powershell
npm --prefix automation run run -- --target local-http
```

Run against a real Docker target:

```powershell
npm --prefix automation run run -- --target docker-dev-http --tenant TenantA
```

Run all supported tenants against one Docker target:

```powershell
npm --prefix automation run run -- --target docker-prod-https
```

Run against a real Azure target:

```powershell
npm --prefix automation run run -- --target azure-dev --tenant TenantA
```

Run all supported tenants against one Azure target:

```powershell
npm --prefix automation run run -- --target azure-prod
```

## Phase 10 Docker Dev HTTP End-to-End Hook

Run the Phase 10 Docker Dev HTTP end-to-end hook from the automation workspace.

Preferred terminal run-hook:

```powershell
npm --prefix automation run xydatalabs-test-docker-local-e2e-dev
```

Equivalent VS Code task:

```text
1 Run: xydatalabs-test-docker-local-e2e-dev (Docker Dev HTTP E2E)
```

This command starts the Docker dev HTTP stack if needed, runs the Phase 10 ready/smoke/integration/matrix/full-validation chain, and writes the same log trail used by the VS Code task and runbook.

Use it when you want the browser automation workspace, VS Code, and direct script path to drive the same Phase 10 end-to-end proof.

Typical use:

1. Start Docker Desktop.
2. Ensure the Phase 10 Docker dev HTTP stack is reachable, or let the hook start it.
3. Run the preferred terminal run-hook or the VS Code task above.
4. Review the `TestResults\Playwright\phase10-docker-http` pointers and the generated logs.
5. Use the cleanup output to confirm the stack returned to a clean state.

Compatibility alias:

```powershell
npm --prefix automation run run:docker:dev:http:e2e-hook
```

Troubleshooting:

- If the command cannot start the stack, check that Docker Desktop is running before retrying.
- If the gateway or UI still time out, confirm the local ports used by the Docker dev HTTP stack are free.
- If you need to debug a specific phase, run the lower-level local stack tasks from VS Code instead of the single hook.

## Local Matrix Run

Run both local profiles in one command and produce an aggregate matrix summary:

```powershell
npm --prefix automation run run:local:matrix
```

Dry-run the matrix without browser execution or verification:

```powershell
npm --prefix automation run run:local:matrix:dry
```

## Docker Matrix Run

Run all supported Docker targets in one command and produce an aggregate matrix summary:

```powershell
npm --prefix automation run run:docker:matrix
```

Dry-run the Docker matrix without browser execution or verification:

```powershell
npm --prefix automation run run:docker:matrix:dry
```

## Docker Validation Bundle

Generate the phase-closeout Docker evidence bundle with the repo-owned PowerShell entry point:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http
```

Widen the bundle to all mapped Docker environments and profiles when the closeout scope requires it:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment all -Profile all
```

Notes:

- The bundle writes to `automation/reports/docker-validation/<bundleId>/`
- The root bundle contains `summary.md` and `summary.json`
- Per-target folders capture Docker startup logs, compose snapshots, inspect output, and referenced automation report paths
- This flow requires the compose-managed `sql-server` container path; Docker validation must not fall back to host SQL
- Local runs may use `Resources/Docker/.env.local` to point `ORDERPROCESSING_SQLSERVER_IMAGE` at a machine-local mirror or pre-pulled tag
- CI/CD runs should set `ORDERPROCESSING_SQLSERVER_IMAGE` explicitly in the pipeline environment so Docker validation always uses the approved registry path
- `-SkipAutomation` is a local debugging mode, not phase-closeout proof when the changed slice requires full Docker automation evidence

## Azure Matrix Run

Run all supported Azure targets in one command and produce an aggregate matrix summary:

```powershell
npm --prefix automation run run:azure:matrix
```

Dry-run the Azure matrix without browser execution or verification:

```powershell
npm --prefix automation run run:azure:matrix:dry
```

Run the Phase 10 dev Azure E2E alias after `01`, `02`, and `03` have passed:

```powershell
npm --prefix automation run xydatalabs-test-azure-e2e-dev
```

GitHub Actions should use `04 Phase 10 Azure Payment Matrix` instead of hardcoded URLs. That
workflow resolves the live Gateway and UI Container Apps FQDNs and injects them through target
override variables:

```text
XYDATALABS_RUNTIME_TARGET_AZURE_DEV_BASE_URL
XYDATALABS_RUNTIME_TARGET_AZURE_DEV_API_BASE_URL
XYDATALABS_RUNTIME_TARGET_AZURE_STG_BASE_URL
XYDATALABS_RUNTIME_TARGET_AZURE_STG_API_BASE_URL
XYDATALABS_RUNTIME_TARGET_AZURE_PROD_BASE_URL
XYDATALABS_RUNTIME_TARGET_AZURE_PROD_API_BASE_URL
```

Notes:

- Supported local targets are `local-http` and `local-https`
- Supported Docker targets are `docker-dev-http`, `docker-dev-https`, `docker-stg-http`, `docker-stg-https`, `docker-prod-http`, and `docker-prod-https`
- Supported Azure targets are `azure-dev`, `azure-stg`, and `azure-prod`
- The local matrix uses distinct verification-safe run prefixes per target so shared DB verification does not cross-contaminate `http` and `https` rows
- The Docker matrix uses distinct verification-safe run prefixes per target so dev, staging, and prod evidence remains isolated across six target runs
- The Azure matrix uses distinct verification-safe run prefixes per target so App Insights and Azure SQL evidence stays isolated across environments
- Live status logs are environment-scoped and written in IST:
  - `TestResults\Playwright\local-http\sequence-summary.log`
  - `TestResults\Playwright\docker-http\sequence-summary.log`
- Local HTTP and local HTTPS remain separate target families; Docker dev HTTP, Docker dev HTTPS, Docker staging HTTP/HTTPS, and Docker prod HTTP/HTTPS remain separate target families
- The runner generates verification-friendly `CustomerOrderId` values using the `OR-<digits>-<dayTag>` prefix convention
- Verification stays script-first through `scripts/verify-payment-run-physical.ps1` for local/Docker and `scripts/verify-payment-run-azure.ps1` for Azure
- Sandbox OTP defaults to `999` when the provider challenge accepts arbitrary three-digit codes
- Reports are written under `automation/reports/<runId>/`
- Single-target local runs auto-start the selected local profile when needed and stop it automatically after verification; use `--keep-local-sessions` to leave local sessions running
- Local matrix runs stop all exercised local profiles automatically after the matrix completes; use `--keep-local-sessions` to opt out
- Docker target and Docker matrix runs assume the selected Docker profile or profiles are already running
- Azure target and Azure matrix runs assume the selected Azure Container Apps environment is already deployed and reachable, SQL and Redis exist for the target environment, and that `az login` plus Azure SQL/Key Vault access are available for verification

## Canonical Planning Reference

Local authenticated customer-directory and tenant-isolation regression:
`npm --prefix automation run test:customer-directory:browser` (from repository root).
See [the fresh Docker runbook](../docs/runbooks/phase10-docker-fresh-ssd.md#manual-customer-directory-checks-and-tenant-sign-in) for per-tenant sign-in, evidence paths, and expected cross-tenant access denial.

- `docs/guides/development/payment-journey-automation-blueprint.md`
