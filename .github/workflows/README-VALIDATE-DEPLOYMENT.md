# Pre-Deployment Validation Workflow

## Overview
Reusable workflow that runs validation checks before infrastructure or application deployments to detect configuration drift, security issues, and breaking changes.

## Features
- **Bicep What-If Analysis**: Preview infrastructure changes before deployment
- **OIDC Credential Verification**: Audit federated identity configuration integrity
- **Configuration Consistency**: Detect sharedsettings drift across environments
- **Artifact Upload**: Preserve validation logs for troubleshooting

## Integration

### Automated (Integrated with infra-deploy.yml)
Pre-validation runs automatically before infrastructure deployments on:
- Push to `dev`, `staging`, or `main` branches
- Manual workflow dispatch (when dry-run disabled)

### Manual Trigger
```bash
# Via GitHub CLI
gh workflow run validate-deployment.yml \
  -f environment=dev \
  -f run-whatif=true \
  -f verify-oidc=true \
  -f check-config=true
```

### Reusable in Other Workflows
```yaml
jobs:
  validate:
    uses: ./.github/workflows/validate-deployment.yml
    with:
      environment: staging
      run-whatif: true
      verify-oidc: false
      check-config: true
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
      AZURE_TENANT_ID: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}
```

## Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `environment` | string | Yes | - | Target environment (dev\|staging\|prod) |
| `run-whatif` | boolean | No | true | Execute Bicep what-if analysis |
| `verify-oidc` | boolean | No | false | Verify OIDC federated credentials |
| `check-config` | boolean | No | true | Validate sharedsettings consistency |

## Secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Azure AD application (service principal) client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

## Exit Codes & Failure Handling

### What-If Analysis
- **Exit 0**: No high-risk changes detected
- **Exit 2**: Deletes or modifications found (review required)
- **Workflow**: Fails on exit 2 (blocks deployment)

### OIDC Verification
- **Exit 0**: All expected credentials present
- **Exit 2**: Missing credentials for dev/staging/main
- **Workflow**: Continues on error (warning only)

### Config Validation
- **Exit 0**: All sharedsettings files aligned
- **Exit 2**: Missing keys or value drift detected
- **Workflow**: Fails on exit 2 (blocks deployment)

## Artifacts
Validation reports uploaded to `validation-report-{environment}` artifact (7-day retention).

## Local Execution

### Prerequisites
```powershell
az login
az account set --subscription <subscription-id>
```

### Run What-If
```powershell
./Resources/Azure-Deployment/validate-parameters-whatif.ps1 `
  -Environment dev `
  -ResourceGroupPrefix 'xyorderprocessing'
```

### Verify OIDC
```powershell
$appId = az ad app list --display-name "GitHub-Actions-OIDC" --query "[0].id" -o tsv
./Resources/Azure-Deployment/verify-oidc-credentials.ps1 -AppObjectId $appId
```

### Check Config Drift
```powershell
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1
```

## Troubleshooting

### "No credentials returned or parse failure"
- Ensure Azure CLI authenticated: `az account show`
- Verify app registration exists: `az ad app list --display-name "GitHub-Actions-OIDC"`
- Check permissions: Directory.Read.All or Application.Read

### "Missing keys or value drift detected"
- Review output table for discrepancies
- Update missing keys in `Resources/Configuration/sharedsettings.{env}.json`
- Commit and re-run validation

### "Unable to parse what-if JSON"
- Check Bicep syntax: `az bicep build -f infra/main.bicep`
- Ensure resource group exists or script creates it
- Review parameter file schema matches main.bicep

## Next Enhancements
- [ ] Add linting step (Bicep/PSScriptAnalyzer)
- [ ] Schema validation for parameter files
- [ ] Automated GitHub secret sync verification
- [ ] Cost estimation integration (Azure Cost Management API)
- [ ] Slack/Teams notification on validation failures

## Related Documentation
- [Validation Scripts](../../Resources/Azure-Deployment/README.md)
- [Infrastructure Deployment](./README-INFRA-DEPLOY.md)
- [Operations Quick Links](../../Documentation/Operations-Quick-Links-README.md)
