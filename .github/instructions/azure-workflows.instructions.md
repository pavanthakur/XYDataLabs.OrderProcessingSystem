---
applyTo: "**/.github/workflows/**"
---
# GitHub Actions Conventions — XYDataLabs.OrderProcessingSystem

## Two-Workflow Split
- `azure-initial-setup.yml` — ONE-TIME only: Phase 0 (GitHub App), Phase 1a (OIDC app registration), Phase 1b (secrets)
- `azure-bootstrap.yml` — LEGACY App Service day-to-day: Phase 2 (infra), Deploy API, Deploy UI, Phase X (cleanup)
- `infra-deploy.yml` — CURRENT Phase 10 path: subscription-scoped Container Apps infrastructure for gateway, Orders, Inventory, Notifications, and UI

## OIDC Authentication Pattern (all workflows)
```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: azure/login@v3
    with:
      client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
      tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
      subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}
```
Never use stored passwords or service principal secrets — always OIDC.

## Branch → Environment Mapping
| Branch | Environment | Azure suffix |
|--------|-------------|--------------|
| `dev` | dev | `-dev` |
| `staging` | staging | `-stg` (NOT `-staging`) |
| `main` | prod | `-prod` |

## Deployment Testing Pattern (most common)
Actions → "Azure Bootstrap & Deploy" → Run workflow:
- Branch: `dev`, Environment: `dev`
- ✅ Deploy API — check to push API changes
- ☐ Bootstrap Infrastructure — uncheck (infra already exists)
- ☐ Deploy UI — only if UI changed
- ☐ Phase X Cleanup — NEVER check unless tearing down

## Legacy App Service Names
- API: `pavanthakur-orderprocessing-api-xyapp-dev`
- UI: `pavanthakur-orderprocessing-ui-xyapp-dev`

## Naming Rule for New Azure Assets
- Use the same `appname-env` pattern for any new Azure service, queue, topic, subscription, or cleanup target
- Keep deployment and Phase X cleanup names symmetric so the teardown can safely remove exactly what the deployment created
- Prefer `stg` for staging resource suffixes in Azure resource names when the resource itself uses an abbreviated environment code
- For the current Phase 10 stack, keep the same `appname-env` pattern across Container Apps names, images, and cleanup targets so local Docker and Azure stay aligned

## Required Secrets
- GitHub environment secrets: `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`
- GitHub repository secrets: `APP_ID` + `APP_PRIVATE_KEY` — GitHub App (for configure-github-secrets workflow)

## Deployment Guard
API/UI deploys are blocked if bootstrap job fails. Fix OIDC/bootstrap first.

## Common Errors
| Error | Fix |
|-------|-----|
| `AADSTS700213` | Run "Azure Initial Setup" with `environment=all` |
| `AADSTS700016` | Run `fix-federated-credential.ps1` |
| `DEPLOYMENT BLOCKED` | Run "Azure Initial Setup" first, then bootstrap |
