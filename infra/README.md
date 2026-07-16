# Infrastructure as Code (Bicep)

This directory contains the production-ready Azure infrastructure definition for the Order Processing System.

## Modules

- `main.bicep` – Legacy subscription-scope hosting entrypoint; creates Resource Group and deploys the App Service-based modules.
- `main.phase10.platform.bicep` – Persistent Phase 10 platform foundation entrypoint; creates the shared platform resource group, Azure Container Registry, and AcrPull managed identity once.
- `main.phase10.acr.bicep` – Phase 10 ACR bootstrap module; creates the Azure Container Registry and AcrPull managed identity for a resource-group scoped caller when the platform foundation owns the scope.
- `main.phase10.bicep` – Phase 10 transport entrypoint; creates the app environment Resource Group and deploys the transport-first Service Bus / Log Analytics / ACA / Functions modules, then consumes the Service Bus transport connection output from the Service Bus module for runtime wiring.
- `modules/acr.phase10.bicep` – Azure Container Registry plus the runtime pull identity used by Container Apps.
- `modules/hosting.bicep` – App Service Plan + API and UI Web Apps with connection string configuration.
- `modules/insights.bicep` – Application Insights instance.
- `modules/loganalytics.phase10.bicep` – Log Analytics workspace for the Phase 10 transport slice.
- `modules/sql.bicep` – Azure SQL Server and Database with firewall rules.
- `modules/identity.bicep` – (Optional) Creates GitHub OIDC App Registration + federated credentials using an Azure CLI deploymentScript.

## Naming Convention
Legacy App Service naming used `{githubOwner}-{baseName}-{component}-xyapp-{environment}` for web apps.
Phase 10 transport infra now uses shorter container app names with environment suffixes and publishes ingress URLs from deployment outputs. The platform ACR uses Azure-safe alphanumeric naming derived from `xyops{githubOwner}{baseName}platform`.
Resource group: `rg-{baseName}-{environment}`
App Service Plan: `asp-{baseName}-{environment}`
Application Insights: `ai-{baseName}-{environment}`

## Parameter Files
Located in `infra/parameters/`:
- `dev.json`
- `staging.json`
- `prod.json`
- `phase10-dev.json`
- `phase10-staging.json`
- `phase10-prod.json`

Adjust `appServiceSku`, `enableIdentity`, or `location` per environment as needed.

## Commands

### Phase 10 Transport Stack
```powershell
az deployment sub what-if --location centralindia --template-file infra/main.phase10.bicep --parameters @infra/parameters/phase10-dev.json
```

### Phase 10 Platform Foundation
```powershell
az deployment sub what-if --location centralindia --template-file infra/main.phase10.platform.bicep --parameters location=centralindia baseName=orderprocessing githubOwner=<github-owner> platformSuffix=platform
```

### Validate (What-If)
```powershell
az deployment sub what-if --location centralindia --template-file infra/main.bicep --parameters @infra/parameters/dev.json
```

### Deploy
```powershell
az deployment sub create --location centralindia --template-file infra/main.bicep --parameters @infra/parameters/dev.json --name infra-dev-$(Get-Date -Format yyyyMMddHHmmss)
```

### Outputs
```powershell
az deployment sub show --name <deploymentName> --query "properties.outputs"
```

## GitHub Actions
Workflow: `.github/workflows/phase10-deploy-orchestrator.yml` (current wrapper) / `.github/workflows/infra-deploy.yml` (internal reusable workflow)

### Phase 10 workflow ownership

`phase10-deploy-orchestrator.yml` is the Phase 10 operator entrypoint for Azure runtime resources. It calls `infra-deploy.yml`, which is the internal lifecycle owner for the Azure runtime stack and the replacement for the old App Service bootstrap/deploy lane.

- `dryRun=true` performs what-if validation
- `dryRun=false` and `cleanupInfra=false` deploys or updates the Phase 10 stack
- `dryRun=false` and `cleanupInfra=true` destroys the environment-scoped Phase 10 stack

Supporting workflows:
- `azure-initial-setup.yml` sets up GitHub App / OIDC / environment secrets
- `build-phase10-images.yml` publishes the runtime images to ACR when called by the wrapper
- `phase10-deploy-orchestrator.yml` is the current manual entrypoint
- `phase10-docker-dev-http-e2e.yml` verifies the local Docker and CI validation path
- `phase10-retention-cleanup.yml` handles historical GHCR retention, ACR stale-tag cleanup, and stale GitHub artifact cleanup

Legacy compatibility workflows:
- `azure-bootstrap.yml`
- `deploy-api-to-azure.yml`
- `deploy-ui-to-azure.yml`

### Trigger behavior
- PR changes to `infra/**` trigger a `what-if`.
- Manual workflow dispatch performs infrastructure deployment using the selected environment parameter file.
- Manual workflow dispatch with `cleanupInfra=true` performs the Phase X teardown path and deletes the environment-scoped resource group.

## Identity Notes
The `identity.bicep` module uses `deploymentScripts` and expects a user-assigned managed identity with necessary Graph permissions for production. For now, directory-wide permissions may be required to allow app registration and federated credential creation.

## Transitional Script
Original PowerShell bootstrap (`Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`) now supports:
- `-DryRun` for planning
- `-LogFormat json` for structured logs
Use Bicep for actual infra provisioning going forward.

## Database Configuration

The SQL module provisions:
- Azure SQL Server with admin credentials
- SQL Database (configurable service objective)
- Firewall rule to allow Azure services
- Connection string automatically configured in App Services

Phase 10 note:
- The active `main.phase10.bicep` entrypoint does not invoke `modules/sql.bicep` today.
- Phase 10 is intentionally transport-first and currently deploys Service Bus, Log Analytics, Application Insights, Container Apps, Functions, Key Vault, and the container images.
- The persistent ACR registry and runtime pull identity are deployed once by `main.phase10.platform.bicep`.
- If you need SQL Server or Redis in Azure, treat that as a separate later-phase addition or legacy bootstrap responsibility, not an output of the current Phase 10 wrapper.
- For a production-grade containerized solution, use ACR for runtime images, Managed Identity for Azure access, and Front Door/WAF for public ingress when you need a controlled external endpoint.

**Security Note**: SQL admin credentials are stored as secure parameters. In production, consider using:
- Azure Key Vault for credential management
- Managed Identity for SQL authentication
- More restrictive firewall rules

## Next Hardening Steps
1. Move SQL credentials to Azure Key Vault
2. Implement Managed Identity for SQL connections
3. Introduce user-assigned managed identity reference in `identity.bicep`.
4. Add diagnostic settings (App Service + Insights + SQL) modules.
5. Add alert rules (availability / errors / database performance).
6. Parameterize runtime stacks if needed.
7. Add staging/prod traffic slot support.
8. Add more restrictive SQL firewall rules for production.

---
Status: Initial migration complete.
