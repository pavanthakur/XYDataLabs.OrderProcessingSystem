---
applyTo: "**/.github/workflows/**"
---
# GitHub Actions Conventions — XYDataLabs.OrderProcessingSystem

## Two-Workflow Split
- `azure-initial-setup.yml` — ONE-TIME only: Phase 0 (GitHub App), Phase 1a (OIDC app registration), Phase 1b (secrets)
- `azure-bootstrap.yml` — DAY-TO-DAY: Phase 2 (infra), Deploy API, Deploy UI, Phase X (cleanup)

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

## App Service Names
- API: `pavanthakur-orderprocessing-api-xyapp-dev`
- UI: `pavanthakur-orderprocessing-ui-xyapp-dev`

## Required Repository Secrets
- `AZUREAPPSERVICE_CLIENTID` — OIDC client ID
- `AZUREAPPSERVICE_TENANTID` — Azure tenant ID
- `AZUREAPPSERVICE_SUBSCRIPTIONID` — subscription ID
- `APP_ID` + `APP_PRIVATE_KEY` — GitHub App (for configure-github-secrets workflow)

## Deployment Guard
API/UI deploys are blocked if bootstrap job fails. Fix OIDC/bootstrap first.

## Common Errors
| Error | Fix |
|-------|-----|
| `AADSTS700213` | Run "Azure Initial Setup" with `environment=all` |
| `AADSTS700016` | Run `fix-federated-credential.ps1` |
| `DEPLOYMENT BLOCKED` | Run "Azure Initial Setup" first, then bootstrap |
