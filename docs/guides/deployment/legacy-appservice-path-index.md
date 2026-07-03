# Legacy App Service Path

This page exists as a narrow index for the older App Service deployment flow.
It is kept for troubleshooting and historical reference only.

## Active Replacement

- Phase 10 uses the transport-first Azure stack in `infra/main.phase10.bicep`
- The current API/UI endpoints come from the infra deployment summary
- Bootstrap and smoke validation for Phase 10 should use the Container App ingress URLs, not `azurewebsites.net`

## Legacy Helpers

- `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`
- `Resources/Azure-Deployment/configure-app-environment.ps1`
- `Resources/Azure-Deployment/verify-deployment-endpoints.ps1`
- `Resources/Azure-Deployment/wait-appservice-ready.ps1`
- `Resources/Azure-Deployment/manage-appservice-slots.ps1`

## Legacy Workflows

- `.github/workflows/deploy-api-to-azure.yml`
- `.github/workflows/deploy-ui-to-azure.yml`

## Legacy URLs

- API: `https://<owner>-orderprocessing-api-xyapp-<env>.azurewebsites.net`
- UI: `https://<owner>-orderprocessing-ui-xyapp-<env>.azurewebsites.net`

If you are not maintaining the old App Service path, you can ignore this index and use the Phase 10 docs instead.
