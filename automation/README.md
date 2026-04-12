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
