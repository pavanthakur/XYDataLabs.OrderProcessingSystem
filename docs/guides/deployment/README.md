# Deployment Guides

Canonical deployment and infrastructure guidance for Azure bootstrap, provisioning, and validation.

Use these documents:

- `quick-start-azure-bootstrap.md` — legacy bootstrap workflow reference; the current Phase 10 Azure container-app path uses `infra-deploy.yml`, `build-phase10-images.yml`, and the Phase 10 runbook
- `azure-deployment-guide.md` — detailed Azure deployment guide with the current Phase 10 path up front and legacy App Service history below
- `workflow-separation-architecture.md` — rationale and structure for splitting one-time setup from day-to-day bootstrap workflows in the legacy App Service model; Phase 10 uses the container-app deployment path instead
- `azure-guides-overview.md` — Azure learning and deployment guide navigation hub retained as a canonical overview
- `bootstrap-script-flow.md` — detailed bootstrap script execution flow and sequencing guide
- `sku-upgrade-slot-testing.md` — App Service SKU upgrade and slot testing guidance for the archived App Service path
- `aca-migration-plan.md` — Azure Container Apps migration roadmap and planning guide
- `azure-deployment-scripts-index.md` — index and usage guide for Azure deployment scripts
- `infrastructure-overview.md` — infrastructure-as-code overview for the canonical infra subtree
- `bicep-overview.md` — Bicep deployment overview for the canonical Bicep subtree
- `azure-deploy-smoke.md` — deploy, verify, and smoke-test quick start for the active Azure surface
- `retry-logic-implementation.md` — deployment retry strategy and implementation reference

Phase 10 cleanup and provisioning now use the same wrapper-driven path:
- `phase10-deploy-orchestrator.yml` for the manual operator entrypoint
- `infra-deploy.yml` for the internal deploy/cleanup implementation
- `dryRun=true` for what-if validation
- `dryRun=false` and `cleanupInfra=false` for deployment
- `dryRun=false` and `cleanupInfra=true` for destructive teardown of the environment-scoped stack

This is the replacement for the old App Service-era bootstrap/deploy split:
- `azure-bootstrap.yml` remains only as a historical compatibility reference
- `deploy-api-to-azure.yml` and `deploy-ui-to-azure.yml` remain only as historical compatibility references
- platform resources such as Service Bus, App Insights, Key Vault, and the Container Apps environment belong to `infra-deploy.yml`
