# Phase 10 fresh Docker storage on G:

## Current non-Azure acceptance evidence (12 November 2026)

**L6 gate C is PASS under DW-028 Option A for `494ab4fd`, not an outstanding Docker/hosted-parity blocker.** The separately named combined `l6-ci-parity-and-azure` report gate remains NOT-RUN for Azure acceptance; do not interpret it as reopening non-Azure L6 C. See the 12 November checkpoint in the [canonical Phase 10 checklist](../internal/phase10-implementation-checklist.md) for same-candidate hosted run links. Planned no-PR CI improvements are separate prospective work, not a reason to repeat accepted payment runs.

Non-Azure local acceptance **PASSED** on clean committed candidate `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`. The cold-build Docker E2E run is `TestResults/Playwright/phase10-docker-http/phase10-docker-http-20261111-230915653/`; the same-candidate NFR run is `TestResults/Phase10/docker-preazure/phase10-docker-nfr-20261111-234505649/`. The reconciled verdict is `phase10-acceptance-reconciliation.json` in the E2E run, and its sanitized tracked projection is `TestResults/Phase10/accepted/phase10-local-acceptance-494ab4fd.json`. All 13 local service image IDs matched across E2E/NFR. E2E passed foundations, integration, deterministic and sandbox payments (three tenants × both providers), messaging/Functions, persistence after Docker Desktop restart, and settings restoration. NFR passed all seven categories; the 100-message burst had 100/100 messages and effects at 2.273 s P95, replay visibility was 1.080 s, outage recovery was 26.201 s with zero lost/duplicate effects, and the Inventory rollback/restore drill passed. This is bounded **non-Azure local acceptance**, not full Phase 10 or Azure acceptance. Under DW-028 Option A, workflow `99` remains a manual local check; its safety guard is unchanged and hosted parity is excluded. DW-023/DW-024, visible OpenPay 3DS challenge, Razorpay S2S, Azure deployment, and ACA revision rollback remain uncertified. Preserve raw reports; do not reset volumes or retry charges.

The cold build completed without build errors but retained analyzer/package warnings (CA1062, CA1825, CA2000, MA0005, MA0047, MA0074, NU1701); they were not suppressed and remain for separate review, so this run is not warning-free.

This procedure replaces disposable local Docker state, not Azure resources. Keep the old disk offline until acceptance passes. Do not migrate a 642 GB disk onto a drive with 471 GB free.

## Safety and prerequisites

- Source and reports remain on Q:. New storage is `G:\DockerStorage\DockerDesktopWSL` on NTFS.
- The operator deleted `F:\DockerRetained\DockerDesktopWSL-before-G`. It is **not available for recovery**. The original F: retention/switch instructions below are historical, not steps to repeat on the current G: installation.
- Docker Desktop must use Linux containers and WSL2. Use PowerShell 7, the SDK selected by `global.json`, Node 20+ and npm, and Playwright Chromium.
- Configure `Resources/Docker/.env.local` privately. Never overwrite an existing file. The example supplies emulator defaults, but secrets must not remain placeholders.
- Full-stack mode requires `LOCAL_SERVICEBUS_ENABLED=true`, `SERVICEBUS_EMULATOR_ACCEPT_EULA=Y` after accepting the emulator licence, and a local emulator SQL password.
- Preserve the configured payment adapter mode. Deterministic local mode proves local behavior, not real provider sandbox acceptance. Real provider mode requires sandbox credentials and connectivity; report incomplete journeys as incomplete, not PASS.
- The Compose project is now `xy-phase10`. Older `compose-*` and `docker-*` containers are not adopted or deleted. Port conflicts fail without touching them.
- Application SQL publishes only on `127.0.0.1:14330` by default, configured by `LOCAL_SQL_HOST_PORT` in the example/local environment files or process environment. Internal container connections remain `sql-server:1433`. SSMS from Windows must use `tcp:127.0.0.1,14330`. Native Windows SQL on 1433 is not stopped or cleaned.
- Before host-side bootstrap verification, integration tests, or NFR database work, the script checks the labeled SQL container's published port and compares its hostname with `SERVERPROPERTY('MachineName')` reached through the host connection. A wrong server blocks the operation; accepting a password is not identity verification.

## 1. Inspect and record (no Docker mutations)

From the repository root:

```powershell
pwsh -NoProfile -File scripts/test-phase10-docker-safety.ps1
pwsh -NoProfile -File scripts/inspect-phase10-docker-storage.ps1 -Mode BeforeSwitch -ManifestPath TestResults/DockerStorage/before-G.json
docker version
docker compose version
dotnet --list-sdks
node --version
```

The preflight checks G: readiness, NTFS, free space, local configuration, the configured disk path, and Linux engine access. It records only allowlisted metadata and inventory; no full Docker settings, container inspection, or environment dumps. Each diagnostic Docker process has a 30-second limit. An optional manifest is the only write; it must be a new file under repository `TestResults`. A successful preflight does **not** verify reset/retention safety.

## 2. Retain the old disk — operator-controlled gate

### Approved reinstall alternative

If the installed version's purge scope cannot be verified, do not claim it is verified. Obtain explicit approval to preserve the disks offline and reinstall Docker Desktop instead. This is the selected procedure for the current G: setup. Use a procedure evidence file documenting that approval, offline checks, the installed version, and the official [backup](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/), [uninstall](https://docs.docker.com/desktop/uninstall/), and [installation](https://docs.docker.com/desktop/setup/install/windows-install/#data-root-and-disk-location) steps.

Run the retention command below with `-ReinstallProcedureApproved` **instead of** `-ResetProcedureVerified`; never supply both. After verified offline retention, uninstall through the signed installed Docker uninstaller in an administrator terminal. Stage and verify a replacement installer before uninstalling. Do not use the older purge dialog or perform broad residual-folder cleanup. Install with `--backend=wsl-2` and `--wsl-default-data-root=G:\DockerStorage\DockerDesktopWSL`, then verify the actual disk location and empty inventory before building. Retained settings conflicts must be investigated, not bypassed through registry edits or broad deletion. The current reinstall stages the same 4.50.0.209931 version to avoid an unrequested upgrade.

### Original reset alternative (not selected)

Before moving anything, verify the installed Docker version's supported reset/reinitialization procedure targets only its configured original storage, not the retained directory. The project intentionally does not automate or assert that version-specific behavior. If it cannot be verified, **stop here**. Do not purge, unregister distributions, or hand-edit Docker's settings to force progress.

After verification:

1. Record the exact reset procedure and Docker version alongside the manifest. Ensure no build, test, or other Docker operation is active.
2. Quit Docker Desktop fully. Save work in other WSL sessions first: `wsl --shutdown` stops **all** WSL distributions, not just Docker. Run it only after acknowledging that interruption.
3. Resolve the old source to exactly `F:\DockerStorage\DockerDesktopWSL`; reject junctions/reparse points in source, destination, and parents. Confirm the retention destination does not exist and remains on the same F: volume.
4. Verify both recorded VHDX files can be opened exclusively and immediately close the handles. If either is locked, stop; do not force dismount.
5. Use the guarded retention command below to move the source folder on the same F: volume. Do not copy the 642 GB disk to G:. The command checks offline state, exact paths and inventory, refuses reparse paths/overwrites, checks exclusive VHDX access, verifies retained file sizes, and writes a new `.retained.json` receipt. It does not test recovery or reset Docker.
6. Follow the verified Docker Desktop reset/reinitialization procedure to create empty storage at its configured location. Only then use **Settings > Resources > Advanced > Disk image location** to relocate that empty storage to G:.
7. If Docker cannot initialize, stop and retain F: untouched. Do not substitute an unverified recovery procedure.

Only after documenting and verifying the version-specific procedure, and quitting Docker/WSL, run:

```powershell
# procedure-evidence.txt must already contain the verified steps and installed version.
pwsh -NoProfile -File scripts/retain-phase10-docker-storage.ps1 -ManifestPath TestResults/DockerStorage/before-G.json -ProcedureEvidencePath TestResults/DockerStorage/procedure-evidence.txt -ResetProcedureVerified -WhatIf
# Repeat without -WhatIf to request interactive confirmation for the offline move.
```

Do not set `-ResetProcedureVerified` merely to bypass the gate. It records operator verification; it is not an automated verification of Docker's closed-source reset implementation.

Validate the empty target **before rebuilding**:

```powershell
pwsh -NoProfile -File scripts/inspect-phase10-docker-storage.ps1 -Mode AfterSwitch -ManifestPath TestResults/DockerStorage/empty-G.json
```

Acceptance requires the exact configured G: path, actual VHDX files there, and no images, containers, or volumes. Docker's Linux `Docker Root Dir` alone does not establish which Windows drive holds the VHDX. Leave the retained folder alone.

## 3. Build, seed, and validate

```powershell
npm --prefix automation ci
Push-Location automation
npx playwright install chromium
Pop-Location
# Daily: preserve SQL data and explicitly run deterministic regression.
pwsh -NoProfile -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -PaymentSuite deterministic
```

For a deliberately fresh acceptance, run only after reviewing the impact and confirming the script's project-scoped reset prompt:

```powershell
pwsh -NoProfile -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -ResetData -ColdBuild -PaymentSuite both
```

`-ResetData` deletes only the named `xy-phase10` application SQL and Azurite volumes; `-ColdBuild` passes `--no-cache` to all locally built application, Functions, and Azurite images and prevents compose from selecting a cached/stale image. It is not Docker Desktop storage reinitialization or a global prune. The hook writes before/after storage reports. `LOCAL_SERVICEBUS_ENABLED=true` enables the emulator and Functions.

Integration tests use a GUID-scoped shared/dedicated SQL database pair, separate from the application databases. The runner verifies Docker's actual loopback SQL identity before creation, writes an ownership manifest under `TestResults`, runs tests, then drops only databases it created. If interrupted, review the manifest and use the separate confirmation-gated recovery command; never delete by prefix alone:

```powershell
$env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = '<private local Docker SQL connection string>'
pwsh -NoProfile -File scripts/cleanup-integration-test-databases.ps1 -ManifestPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\Integration\<run-manifest>.json' -WhatIf
# After reviewing the exact manifest/server/database names, repeat without -WhatIf to confirm.
Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
```

Application tenant/provider settings are fingerprinted before and after integration; the report contains only `unchanged: true|false`, never provider credentials. A changed fingerprint fails the run and must be investigated, not hidden by reseeding.

Normal startup no longer tears down SQL. It still applies the existing baseline bootstrap; it is not a database restore or a guarantee that seed-owned rows remain unchanged. Read the resulting logs before calling a run accepted.

### Manual customer-directory checks and tenant sign-in

The seeded `tenant-admin` now has explicit `platform-admin` access and can select any active tenant in one login. Ordinary tenant users remain restricted to their own tenant. See [tenant identity and access](../guides/configuration/tenant-identity-access.md) for account roles, seed reconciliation, runtime configuration and Azure prerequisites.

Open `http://localhost:5022/customers`. Use **Sign out**, then **Sign in**, to switch accounts in the same browser. Use `tenant-a-user`, `tenant-b-user`, or `tenant-c-user` with the private local password. Customer entry and refresh resolve the signed-in user's authorized tenant; the displayed configured tenant remains the deployment default.

Run the local-only browser regression after restoring the baseline:

```powershell
npm --prefix automation run test:customer-directory:browser
```

This checks admin switching A/B/C, same-browser and cross-tab logout, then all three regular accounts with filtered selectors and direct cross-tenant denial. Evidence is written beneath `TestResults/DockerStorage/` (or the E2E run's `customer-directory/` directory). The E2E wrapper runs this gate before payment validation. An empty customer array can be legitimate; a failed request is not an empty search result.

Integration seed fixtures must create orders through `Order.Create`, not insert unrecognized status strings. A raw `Pending` order status is invalid and can break customer-directory queries that include orders. Run destructive fixture suites only against an explicitly verified disposable test database, not the database being used for manual browser testing.

Run the existing messaging/durability proof separately:

```powershell
pwsh -NoProfile -File scripts/run-phase10-docker-nfr-proof.ps1
```

For the focused live-emulator acceptance without the broader rollback/performance prerequisites:

```powershell
dotnet build tools/Phase10.NfrProbe --no-restore
pwsh -NoProfile -File scripts/test-local-messaging.ps1 -ArtifactDirectory TestResults/DockerStorage/messaging-acceptance
```

This publishes three events and verifies both consumers' inbox/effect rows. A malformed message must be broker-dead-lettered and forwarded into Functions quarantine; a separate approved replay must finish with persisted replay state and downstream effects. Replay enablement is temporary and restored afterward. Probe tenant IDs are resolved from the active registry, never assumed to be `1`. Functions explicitly registers event-contract assemblies so cold-worker replay does not depend on incidental assembly loading.

Inspect the proof artifacts: consumers, DLQ/replay, and Functions processing must be demonstrated, not inferred from running containers. The proof's existing rollback lane requires a retained previous inventory image; a genuinely fresh disk will not have one. Record missing rollback evidence as incomplete, not PASS; do not invent an older image tag.

Restart Docker Desktop, verify the application SQL volume is still attached, repeat smoke checks, and check a known local test row survives. Then exercise the explicit disposable reset and repeat E2E:

The restart-only acceptance command checks for unrelated running containers, records known Paid orders in both databases, restarts Desktop without deleting data, and verifies the same SQL volume, rows, G: location and native Windows SQL listener:

```powershell
pwsh -NoProfile -File scripts/test-phase10-docker-persistence.ps1 -RestartDesktop
```

```powershell
# Destructive: prompts before deleting only xy-phase10 trial SQL/Azurite data.
pwsh -NoProfile -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -ResetData
```

Only an intentionally unattended, separately authorized reset may use `-Confirm:$false`. `-WhatIf` is non-mutating. Never combine reset with reuse. Old `-CleanImages`/`-RemoveVolumes` startup shortcuts are rejected.

## 4. Daily use and space budget

### Corrected repeatable acceptance (2026-11-10)

No additional reset is needed to repair the payment fixture. Use:

```powershell
pwsh -NoProfile -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -ColdBuild -PaymentSuite both -AcceptanceProfile baseline -VerifyPersistence
```

This preserves SQL/Azurite volumes, cold-builds current images, runs foundations and isolated integration, verifies integration did not alter application metadata, applies only the snapshotted local OpenPay 3DS-off baseline, and read-validates every active tenant and both providers. It then runs identity and the complete deterministic UI/payment matrix before permitting real sandbox journeys. Messaging/Functions and the explicitly selected Desktop restart run in the same orchestration. The selected baseline requires every active tenant × Razorpay hosted and OpenPay with 3DS off; optional extended capabilities remain separately BLOCKED/NOT-RUN, never PASS. Final storage/restoration reports are written even after failure. No reset, global prune or VHDX compaction is implied. Azure deployment and directory changes are excluded.

### Image-bound acceptance sequence — pending on a clean candidate

The command above is the E2E stage. Record its exact new run directory from the output; do not use a mutable `latest` pointer. After E2E completes and restoration is verified, pass that run's `docker-image-identities-before.json` to NFR so the NFR wrapper refuses to start a different stack or accept a dirty/different candidate:

```powershell
$e2eRun = 'TestResults/Playwright/phase10-docker-http/<exact-e2e-run-id>'
$expectedImages = Join-Path $e2eRun 'docker-image-identities-before.json'
pwsh -NoProfile -File scripts/run-phase10-docker-nfr-proof.ps1 `
  -SkipStartIfNeeded `
  -ExpectedImageManifest $expectedImages `
  -BurstMessageCount 100 `
  -MaximumP95Seconds 30
```

Record the exact NFR wrapper run directory printed by the command, then verify and reconcile only those two run directories against the full candidate SHA:

```powershell
$nfrRun = 'TestResults/Phase10/docker-preazure/<exact-nfr-run-id>'
npm --prefix automation run verify:phase10-completion -- $e2eRun
npm --prefix automation run reconcile:phase10-acceptance -- `
  --e2e $e2eRun `
  --nfr $nfrRun `
  --expected-commit '<full-clean-candidate-sha>'
```

The v4 image-bound sequence **passed** for candidate `494ab4fdf0d7027bf9a506931fe903d4cea1fdbe`: both manifests cover the 13 expected project-owned services and reconcile within and across runs; the sealed report, coverage, restoration, NFR categories, and rollback evidence all passed. Re-run the checks above for a new candidate; do not reuse or overwrite sealed run artifacts to make a report pass. The prior `f2bd3587` and `58c361a9` evidence remains historical and does not satisfy this current gate.

`Resources/Configuration/tenant-bootstrap.local.json` is the versioned, non-secret local bootstrap contract for required seed tenants, provider defaults, and key references. Shared `dbo.Tenants` remains authoritative for tenant identity, active status, tier, and provider route; provider settings come from the tenant's resolved business database. Dedicated stores resolve through explicit Compose configuration references, not tenant-name rules. TenantC remains a regression case: its route lives in the shared registry and provider rows in its dedicated business DB. Do not add duplicate shared provider rows to make a join succeed.

Normal bootstrap inserts missing seed data only; it does not rewrite credentials, routes, existing tenant statuses or deactivate additional tenants. A metadata mismatch fails validation instead of being hidden by reseeding.

### Offline Phase 10 report

The Docker hook writes `index.html` alongside its acceptance artifacts. Open it with:

```powershell
$run = 'TestResults/Playwright/phase10-docker-http/<run-id>'
Invoke-Item (Join-Path $run 'index.html')
```

To render an existing, unrendered run without starting tests or accessing Docker, SQL, or providers (the output files are create-once; use a fresh copy/run directory if outputs already exist):

```powershell
npm --prefix automation run report:phase10-preview -- TestResults/Playwright/phase10-docker-http/<run-id>
npm --prefix automation run verify:phase10-completion -- TestResults/Playwright/phase10-docker-http/<run-id>
```

For reviewed sharing, first verify the completion record and inspect the exact allowlisted report files. Do not ZIP the entire run folder: raw logs, screenshots and provider artifacts may need separate sanitization. From the repository root, create a ZIP containing only the sanitized summary set:

```powershell
$run = 'TestResults/Playwright/phase10-docker-http/<run-id>'
$zip = "TestResults/Phase10-report-$((Split-Path $run -Leaf)).zip"
Compress-Archive -LiteralPath @(
    (Join-Path $run 'index.html'),
    (Join-Path $run 'phase10-preview.html'),
    (Join-Path $run 'phase10-coverage-summary.json'),
    (Join-Path $run 'phase10-completion.json'),
    (Join-Path $run 'acceptance-packet.json'),
    (Join-Path $run 'run-summary.json')
) -DestinationPath $zip -NoClobber
```

This is a provisional reporting view, not a PASS certificate or Phase 10 closure. The report's completeness, individual outcomes and acceptance status are distinct; retain raw failure evidence separately and do not package it unless reviewed.

### Manual browser handoff: simulation versus sandbox

Every positive automated payment journey uses an isolated authenticated browser session and the user path **customer directory → fresh uniquely provisioned customer → Create order → select a product → Initiate payment**. It creates a new test customer through the existing API for each journey before returning to the UI, so it does not exhaust seeded customers or reuse a paid order. Payment completion is not order fulfillment; do not mark orders fulfilled to bypass eligibility rules (DW-023/DW-024 remain deferred).

| Tenant | Login | Provider cases | Currency |
|---|---|---|---|
| Every discovered active tenant (includes A/B/C) | tenant-admin | Razorpay hosted / flag false; OpenPay / flag false | INR; MXN |

```powershell
# Complete deterministic matrix for all active tenants and both providers.
pwsh -NoProfile -File scripts/run-local-payment-tests.ps1 -Mode deterministic -AcceptanceProfile baseline
# Targeted C/Razorpay regression; settings and adapter mode restore afterward.
pwsh -NoProfile -File scripts/run-local-payment-tests.ps1 -Mode deterministic -TenantCode TenantC -ProviderType Razorpay
```

For operator-only manual switching, first ensure no tests are running, then prepare an owned snapshot and keep its exact manifest until restoration:

```powershell
# Optional extended challenge-capability test only; normal OpenPay baseline is 3DS-off.
pwsh -NoProfile -File scripts/local-payment-test-state.ps1 -Action Prepare -TenantCode TenantA -ProviderType OpenPay -ThreeDs true -ManifestPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\DockerStorage\manual-UNIQUE-RUN.json'
# Test once, then restore the SAME manifest, not a guessed baseline provider.
pwsh -NoProfile -File scripts/local-payment-test-state.ps1 -Action Restore -ManifestPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\DockerStorage\manual-UNIQUE-RUN.json'
```

Normal manual UI mode is sandbox. Sign in with the private configured local test password; verify the UI's effective mode/provider before submitting. Simulation completes locally without a provider handshake; sandbox must show provider interaction and authoritative confirmation. Use only official provider test cards, never real cards. Expiry must be in the future; the harness generates a future year rather than retaining the obsolete OpenPay 12/26. Challenge UI/OTP depends on the provider fixture; saved-card/contact OTP is not evidence of payment authentication. Provider S2S entitlement and unsupported challenge-negative cases remain explicit gaps.

Each UI-created smoke order writes a sanitized `manual-data-sheet.json` with tenant/login, provider/mode, customer and product IDs, order/reference, amount and currency. Final callback/provider-confirmation and SQL evidence remain alongside it. Never share passwords, tokens, CVV, card-entry screenshots or raw checkout traces. A new order/reference is required for every case; do not retry an ambiguous charge.

The required baseline configures OpenPay 3DS off. It therefore tests OpenPay sandbox payment completion and does not claim a visible challenge. The optional `-AcceptanceProfile extended` suite tests OpenPay 3DS-on separately; successful callback/payment without an observed challenge remains unverified challenge acceptance, not a challenge PASS. Do not issue another charge merely to chase an OTP screen.

Raw journey reports remain unchanged. `acceptance-validated-rows.json` and `acceptance-executive-summary.md` include later dependency/SQL/challenge gates. For older/raw failed cases whose exception obscured the saved order ID, a supplemental **read-only** audit can correlate the recorded real-provider payment IDs and fetch status with SQL Paid orders; it does not certify a visible challenge or relabel the original result:

```powershell
pwsh -NoProfile -File scripts/audit-phase10-sandbox-evidence.ps1 -SummaryPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\ACTUAL-FINISHED-SANDBOX\summary.json' -OutputPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\UNIQUE-SUPPLEMENTAL-AUDIT.json'
```

### Real sandbox payment acceptance

Normal local Docker and non-Docker configuration uses real sandbox adapters. `localhost` is not permission to mock checkout or device collection. The UI reads the actual resolved adapter through authenticated `/api/v1/Payments/runtime`; missing or inconsistent runtime evidence blocks payment configuration. Razorpay script failures remain errors, never simulated successes.

The current Razorpay integration accepts **INR only**. An MXN order must not be silently charged as INR: the server rejects it before payment/provider side effects, and the runtime publishes `supportedCurrencies` for the UI to disable incompatible checkout. The new-order form displays and explicitly submits the compatible currency (INR for Razorpay; the existing MXN default remains for OpenPay). Existing order amounts/currencies are never rewritten. Provider order responses must carry their actual amount/currency and match the saved terms before checkout/S2S can proceed. Newer Razorpay UI builds fail closed against a Payments runtime missing currency capability metadata; promote matching UI/Payments builds together. This is a project integration limit, not a statement that Razorpay globally supports only INR.

Run the local all-tenant incompatible-currency regression **sequentially**, after other payment fixtures finish:

```powershell
npm --prefix automation run test:payment-currency:browser
```

It discovers every active tenant, temporarily routes each to Razorpay, checks UI blocking and direct-API HTTP400 for Razorpay/MXN, physically verifies no attempts/transactions/payin logs and unchanged order terms, restores provider flags, then exercises browser order creation using each tenant's configured provider/currency without charging. If an earlier sandbox payment was already captured in a different currency, retain it for an explicit reconciliation/disposition decision; do not retry, overwrite currency, force Paid or issue a refund automatically.

For manual testing, sign in as `tenant-admin`, choose the tenant, open **Payments**, select a customer and an eligible existing order, then **Continue to payment**. Confirm the mode says `sandbox` before entering provider test data. New customers/orders are read without the old five-minute directory cache. The saved order supplies the immutable reference, amount and currency. Existing paid or zero-value orders cannot be selected.

```powershell
# Required positives: every active tenant × Razorpay hosted / OpenPay 3DS off.
pwsh -NoProfile -File scripts/run-local-payment-tests.ps1 -Mode sandbox -AcceptanceProfile baseline
# Optional capability suite adds OpenPay 3DS-on cases; this does not replace the baseline.
pwsh -NoProfile -File scripts/run-local-payment-tests.ps1 -Mode sandbox -AcceptanceProfile extended
# Separate real Razorpay failure/dismissal cases; unsupported OpenPay negative fixtures remain explicit gaps.
npm --prefix automation run test:payments:sandbox:negative
# Explicit simulation suite; wrapper returns the running Payments service to sandbox afterward.
pwsh -NoProfile -File scripts/run-local-payment-tests.ps1 -Mode deterministic
# Controlled challenge/error/timeout and false-success regression tests (no provider handshake claim).
npm --prefix automation run test:provider-challenges:browser
npm --prefix automation run test:payment-evidence
```

The sandbox suite requires test credentials, rejects live or simulated mode, and requires provider-confirmed final status, amount/currency, local transaction evidence and server create/fetch-operation evidence. An authorization is pending capture, not a completed payment. Reports distinguish configured 3DS from observed challenge: Razorpay hosted checkout can authenticate while its direct/S2S flag is false. OpenPay uses its real device collector on localhost. Confirmation polls are bounded; charge creation is not automatically repeated after an ambiguous timeout.

Payment completion also requires the matching order to reach `Paid` through the success event/outbox/consumer path. Immediate provider success must raise the same domain event as callback success. A successful or unresolved existing attempt blocks another charge; only a definitively failed attempt permits a new attempt. Old trial orders with inconsistent historical state are not silently rewritten by startup or seeding.

Provider/3DS fixture changes are serialized and snapshotted before writes. Reports and recovery manifests are under `TestResults/DockerStorage/`; a failed/interrupted restoration leaves `TestResults/local-payment-test-state.lock`. Do not delete that lock to bypass recovery. After ensuring no test is still running, restore its recorded manifest:

```powershell
pwsh -NoProfile -File scripts/local-payment-test-state.ps1 -Action Restore -ManifestPath 'Q:\GIT\TestAppXY_OrderProcessingSystem\TestResults\DockerStorage\payment-state\ACTUAL-MANIFEST.json'
```

No provider credentials or seeded accounts are rewritten by fixtures. The local acceptance operation snapshots existing OpenPay 3DS flags before setting them false for every active tenant; it does not alter routes or other provider settings. Required Razorpay S2S entitlement and provider-documented OpenPay negative fixtures are extended capability gaps and do not invalidate a fully passing selected baseline. They remain BLOCKED/NOT-RUN in the packet, not PASS. Never interpret this as production certification or real bank/SMS OTP. Diagnostics omit input values, sensitive callback parameters and checkout session query strings; never publish raw provider traces.

The deterministic suite reports only its simulation regression scope; its success does not satisfy sandbox capability or negative-scenario acceptance. Older simulation reports included unrelated capability gaps in their overall status. Inspect their individual case results instead of relabelling those historical files.

```powershell
# Start/update without deleting SQL storage.
pwsh -NoProfile -File scripts/start-phase10-docker-dev.ps1 -Action up -Profile apps
# Validate an already-running stack.
pwsh -NoProfile -File scripts/run-phase10-docker-dev-e2e-hook.ps1 -ReuseExistingStack
# Stop project containers; preserve named volumes.
pwsh -NoProfile -File scripts/start-phase10-docker-dev.ps1 -Action down
# Read-only report; warns below 100 GiB free and reports SQL allocation/log rotation.
pwsh -NoProfile -File scripts/inspect-phase10-docker-storage.ps1 -Mode Report
# Equivalent report plus cleanup actions; report is the default.
pwsh -NoProfile -File scripts/maintain-phase10-docker-storage.ps1 -Action Report
```

Startup blocks a full build below 50 GiB free on its configured Docker disk drive. All 13 Compose services rotate container logs at 10 MB × 3 files. The storage report includes Windows free space, Docker images/containers/volumes, the selected builder cache, actual VHDX paths/sizes, SQL data/log allocation and effective container log configuration. It warns when application SQL allocation exceeds 20 GiB; it never shrinks databases. The SQL volume persists normal restarts; explicit reset removes it.

Startup, database bootstrap, and the E2E wrapper redact configured local secret values from captured command output. Keep reports private anyway: application/test tools can generate their own artifacts, and redaction is not a substitute for avoiding credentials in application logs.

For opt-in cache cleanup, report first, then select only the known local `desktop-linux` builder. The command targets BuildKit's 20 GB maximum-used-space policy and prompts before pruning:

```powershell
pwsh -NoProfile -File scripts/maintain-phase10-docker-storage.ps1 -Action PruneBuildCache -WhatIf
# Review the target, then repeat without -WhatIf and confirm.
pwsh -NoProfile -File scripts/maintain-phase10-docker-storage.ps1 -Action PruneBuildCache
```

Build cache belongs to the selected shared builder, not just this repository, and GC applies only to eligible cache. The 20 GB setting is not a total Docker or disk cap. Project image cleanup is separately gated and requires the rollback image manifest created before a cold build; it removes only unreferenced `xy-phase10`-labelled images. The report previews image IDs and references. Current images, recorded rollback images, third-party infrastructure images, volumes, databases, reports and unrelated containers are excluded. No global system/volume prune or scheduled deletion is installed. Do not use `docker system prune -a --volumes`.

```powershell
# Substitute the exact path from the E2E run you reviewed.
pwsh -NoProfile -File scripts/maintain-phase10-docker-storage.ps1 -Action PruneImages -RollbackManifestPath 'TestResults/Playwright/phase10-docker-http/<runId>/rollback-images.json' -WhatIf
# Repeat without -WhatIf only after confirming the listed image IDs/references are disposable.
pwsh -NoProfile -File scripts/maintain-phase10-docker-storage.ps1 -Action PruneImages -RollbackManifestPath 'TestResults/Playwright/phase10-docker-http/<runId>/rollback-images.json'
```

### Returning VHDX space to Windows (manual, separately confirmed)

Pruning Docker objects can free space inside Docker's Linux disk without immediately shrinking the Windows VHDX. Use the latest storage report to resolve the actual data disk; expected for this G: layout is `G:\DockerStorage\DockerDesktopWSL\disk\docker_data.vhdx`. Do not select the small `main\ext4.vhdx`. Docker documents that its WSL backend's data disk is the VM image and recommends stopping Docker before direct backup; Microsoft says `compact vdisk` is for dynamically expanding disks and requires the VHD to be detached or attached read-only ([Docker backup guidance](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/), [Microsoft `compact vdisk`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/compact-vdisk)).

This is intentionally not automated. Before proceeding, record free-space and exact VHDX size, confirm all data is disposable or separately backed up, quit Docker Desktop, acknowledge that `wsl --shutdown` interrupts every WSL distribution, run it only if acceptable, and verify the exact VHDX is offline/unlocked. Follow the compaction procedure validated for the installed Docker Desktop/Windows versions. If the exact disk cannot safely be detached/read-only or the procedure is uncertain, stop; do not compact, unregister WSL, or delete the VHDX. After compaction, restart Docker and verify the G: backing path, SQL persistence/readiness, and Windows free-space delta. Docker-reclaimed bytes and Windows-returned bytes are different measurements; no recovery amount is guaranteed.

## 5. Retire F: only after acceptance

Record cold-build, seed, smoke/integration/payment results, messaging/Functions evidence, restart persistence, explicit reset/reseed, and actual disk usage in the acceptance packet. Mark external failures honestly. Preserve the old disk if any required acceptance remains incomplete.

Deleting the retained folder requires **separate user approval**. Resolve the exact retained folder against the manifest, verify it is not Docker's active location, reject reparse points, and delete only that folder. Never remove `F:\DockerStorage`, `F:\DockerRetained`, a drive root, or unrelated backups recursively. No automatic F: deletion command is provided.

### Historical acceptance checkpoint — 9 November 2026

Superseded for current status by the 12 November acceptance checkpoint at the top of this runbook. The dated results and remaining steps below are historical, not instructions to repeat accepted Docker/payment testing.

The user confirmed they independently deleted `F:\DockerRetained\DockerDesktopWSL-before-G`. It is no longer a recovery option; do not assume unrelated F: backups contain this Docker disk. Ask for immediate confirmation before testing the destructive project reset on G:.

Nine real-sandbox and nine deterministic primary journeys passed provider/payment and Paid-order checks, including physical SQL uniqueness checks. Desktop restart preserved known Paid orders in both databases, the SQL volume, G: location and native Windows SQL listener. Real Razorpay S2S entitlement and OpenPay negative fixtures remain unverified; reset/reseed acceptance remains pending. These gaps prevent overall completion. Detailed artifacts are under `TestResults/DockerStorage/`.

The G: backing disks measured about 34.6 GiB, but drive-wide free space was only about 90 GiB: the below-100-GiB warning applies. Unrelated OS-backup folders and an ISO also exist on G:; they were not altered or recursively inventoried. Container log rotation is bounded for all 13 services, but neither this nor SQL reset caps unrelated drive usage.
