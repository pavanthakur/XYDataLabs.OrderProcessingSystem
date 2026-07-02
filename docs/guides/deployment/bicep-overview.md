# Bicep Infrastructure Templates

## Overview

This repository uses Bicep as the Azure infrastructure source of truth and GitHub Actions as the orchestration layer.

That split matters:

- Bicep defines resources, dependencies, outputs, and parameter contracts.
- GitHub Actions decides when to run `what-if`, deployment, and smoke checks.

The legacy App Service template guidance in this folder remains as historical context, but Phase 10 now uses a transport-first Azure deployment model.

## Current Bicep Surfaces

- `infra/main.phase10.bicep` - Phase 10 transport stack for Service Bus, Function App, Container Apps, Log Analytics, Key Vault, and App Insights
- `infra/modules/*.bicep` - reusable building blocks that Phase 10 composes
- `infra/parameters/phase10-*.json` - environment-specific parameter files

## Phase 10 Usage

Use the Phase 10 runbook for the exact deployment flow:

- [docs/runbooks/phase10-azure-smoke.md](../../runbooks/phase10-azure-smoke.md)

Use the Phase 10 quick-start guide when you want the high-level architecture explanation:

- [docs/guides/deployment/azure-deploy-smoke.md](azure-deploy-smoke.md)

## Workflow Guidance

Preferred rule:

- Update Bicep when Azure resources, outputs, or parameters change.
- Update workflow YAML when approval gates, triggers, or job sequencing change.

For Phase 10, it is usually better to extend the existing infra workflow than to add a new parallel workflow, unless the deployment path becomes materially different.

## Validation Guidance

Before and after a Phase 10 deployment:

1. Run `az deployment sub what-if`.
2. Deploy with `az deployment sub create`.
3. Read the deployment outputs.
4. Verify Service Bus, Function App, Container Apps, Log Analytics, Managed Environment, and App Insights.
5. Run the transport smoke and replay smoke.

## References

- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure deployment runbook](../../runbooks/phase10-azure-smoke.md)
