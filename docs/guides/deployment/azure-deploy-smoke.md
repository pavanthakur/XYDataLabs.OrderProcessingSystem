# Azure Deploy and Smoke Guide

This guide explains the current Azure path in plain terms: Bicep defines the infrastructure, GitHub Actions orchestrate the run, and the runbook/CLI steps verify the result.

## Short Answer

- `Bicep` is the infrastructure source of truth for Azure resources, dependencies, and outputs.
- `GitHub Actions YAML` is the orchestration layer for when and how the deployment runs.
- They are not competing tools. They solve different layers of the same deployment problem.

For Phase 10, the repo uses:

- `infra/main.phase10.bicep` for the transport slice infrastructure
- `infra/parameters/phase10-dev.json`, `infra/parameters/phase10-staging.json`, and `infra/parameters/phase10-prod.json`
- `docs/runbooks/phase10-azure-smoke.md` for the exact deploy, verify, and smoke sequence

Older App Service references in this folder are historical context only; the Phase 10 runbook is the active operational path.

## Why Bicep Was Added

The earlier GitHub workflow approach was fine for orchestration, but it does not replace declarative Azure infrastructure.

Bicep helps because it:

- keeps Azure resources versioned in the repo
- makes dependency order explicit
- produces stable outputs for follow-up verification
- supports `what-if` before deployment
- reduces drift between what the workflow expects and what Azure actually creates

GitHub Actions remains useful for:

- authentication
- environment selection
- approval gates
- calling `what-if`, `create`, and verification commands
- running smoke tests after deployment

## Recommended Strategy

Use a thin workflow and keep the Azure definition in Bicep.

Recommended shape:

1. Keep `infra/main.phase10.bicep` as the source of truth for the transport stack.
2. Keep GitHub Actions focused on orchestration, not resource modeling.
3. Prefer updating the existing infra workflow to accept a Phase 10 mode or template input instead of adding a brand-new workflow unless the job shape is truly different.
4. Use the runbook and prompt below for manual or assisted deploy/test sessions.

## What To Run

### 1. Preview

```powershell
az deployment sub what-if `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json
```

### 2. Deploy

```powershell
az deployment sub create `
  --name phase10-dev-<timestamp> `
  --location centralindia `
  --template-file infra/main.phase10.bicep `
  --parameters @infra/parameters/phase10-dev.json
```

### 3. Verify

Use the output values from the deployment and confirm:

- Service Bus namespace exists
- `order-events` topic exists
- `inventory-order-created` and `notifications-order-created` subscriptions exist
- `order-events-dlq`, `dlq-intake`, and `dlq-replay-requests` exist
- Function App settings include the transport connection string and replay settings
- Container App environment variables match the transport slice
- Log Analytics, Managed Environment, and App Insights are wired

### 4. Smoke Test

Run a publish/consume check and a replay check after deployment.

Details live in:

- [docs/runbooks/phase10-azure-smoke.md](../../runbooks/phase10-azure-smoke.md)

## When To Modify Workflows

Update workflow YAML when you need to:

- expose Phase 10 as a reusable job
- add a manual dispatch for dev/staging/prod
- add approval gates or environment rules
- trigger post-deploy smoke tests automatically

Do not move Azure resource definitions into YAML just because deployment is triggered from GitHub Actions.

## Operational Rule of Thumb

If you are changing:

- resource shape, dependencies, outputs, or parameters -> change Bicep
- job sequencing, approvals, triggers, or environment routing -> change YAML
- verification steps after deployment -> update the runbook and prompt
