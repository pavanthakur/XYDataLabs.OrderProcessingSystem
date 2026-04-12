# Payment Automation Workspace

This workspace is intentionally separate from `frontend/` and from the .NET solution. It hosts
browser-driven payment journey automation without coupling that work to the React application or
to backend test projects.

## Current Status

The initial local pilot is now implemented for the React payment flow and OpenPay sandbox 3DS.
The workspace still preserves the contract seams needed for later fixture provisioning, Azure
execution, and additional payment-provider adapters.

## Initial Scope

- Runtime target resolution
- Tenant execution catalog resolution
- Local browser execution for `local-http` and `local-https`
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

## Local Matrix Run

Run both local profiles in one command and produce an aggregate matrix summary:

```powershell
npm --prefix automation run run:local:matrix
```

Dry-run the matrix without browser execution or verification:

```powershell
npm --prefix automation run run:local:matrix:dry
```

Notes:

- Supported first targets are `local-http` and `local-https`
- The local matrix uses distinct verification-safe run prefixes per target so shared DB verification does not cross-contaminate `http` and `https` rows
- The runner generates verification-friendly `CustomerOrderId` values using the `OR-<digits>-<dayTag>` prefix convention
- Verification stays script-first through `scripts/verify-payment-run-physical.ps1`
- Sandbox OTP defaults to `999` when the provider challenge accepts arbitrary three-digit codes
- Reports are written under `automation/reports/<runId>/`
- Local runs now stop the exercised local profile automatically after verification; use `--keep-local-sessions` to leave local sessions running
- Local matrix runs stop all exercised local profiles automatically after the matrix completes; use `--keep-local-sessions` to opt out

## Canonical Planning Reference

- `docs/guides/development/payment-journey-automation-blueprint.md`
