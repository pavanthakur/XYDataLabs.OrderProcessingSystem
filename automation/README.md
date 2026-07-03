# Payment Automation Workspace

This workspace is intentionally separate from `frontend/` and from the .NET solution. It hosts
browser-driven payment journey automation without coupling that work to the React application or
to backend test projects.

## Current Status

The initial local and Docker pilots are implemented for the React payment flow and OpenPay sandbox 3DS.
Azure App Service execution is now also catalog-driven for `dev`, `stg`, and `prod`, with verification
staying script-first through Application Insights and Azure SQL.

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

Run the Phase 10 Docker Dev HTTP end-to-end hook from the automation workspace:

```powershell
npm --prefix automation run run:docker:dev:http:e2e-hook
```

This command starts the Docker dev HTTP stack if needed, runs the Phase 10 ready/smoke/integration/matrix/full-validation chain, and writes the same log trail used by the VS Code task and runbook.

Use it when you want the browser automation workspace to drive the same Phase 10 end-to-end proof as the script entrypoint, without switching to VS Code tasks manually.

Typical use:

1. Start Docker Desktop.
2. Ensure the Phase 10 Docker dev HTTP stack is reachable, or let the hook start it.
3. Run the command above.
4. Review the `TestResults\Playwright\phase10-docker-http` pointers and the generated logs.
5. Use the cleanup output to confirm the stack returned to a clean state.

Quick start:

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
- Azure target and Azure matrix runs assume the selected Azure App Service environments are already deployed and reachable, and that `az login` plus Azure SQL/Key Vault access are available for verification

## Canonical Planning Reference

- `docs/guides/development/payment-journey-automation-blueprint.md`
