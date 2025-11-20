# Infrastructure as Code (Bicep)

This directory contains the production-ready Azure infrastructure definition for the Order Processing System.

## Modules

- `main.bicep` – Subscription-scope entrypoint; creates Resource Group and deploys modules.
- `modules/hosting.bicep` – App Service Plan + API and UI Web Apps.
- `modules/insights.bicep` – Application Insights instance.
- `modules/identity.bicep` – (Optional) Creates GitHub OIDC App Registration + federated credentials using an Azure CLI deploymentScript.

## Naming Convention
`{githubOwner}-{baseName}-{component}-xyapp-{environment}` for web apps.
Resource group: `rg-{baseName}-{environment}`
App Service Plan: `asp-{baseName}-{environment}`
Application Insights: `ai-{baseName}-{environment}`

## Parameter Files
Located in `infra/parameters/`:
- `dev.json`
- `staging.json`
- `prod.json`

Adjust `appServiceSku`, `enableIdentity`, or `location` per environment as needed.

## Commands

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
Workflow: `.github/workflows/infra-deploy.yml`
- PR changes to `infra/**` trigger a `what-if`.
- Push to `dev`, `staging`, `main` branches triggers deployment using the corresponding parameter file.

## Identity Notes
The `identity.bicep` module uses `deploymentScripts` and expects a user-assigned managed identity with necessary Graph permissions for production. For now, directory-wide permissions may be required to allow app registration and federated credential creation.

## Transitional Script
Original PowerShell bootstrap (`Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`) now supports:
- `-DryRun` for planning
- `-LogFormat json` for structured logs
Use Bicep for actual infra provisioning going forward.

## Next Hardening Steps
1. Introduce user-assigned managed identity reference in `identity.bicep`.
2. Add diagnostic settings (App Service + Insights) modules.
3. Add alert rules (availability / errors).
4. Parameterize runtime stacks if needed.
5. Add staging/prod traffic slot support.

---
Status: Initial migration complete.
