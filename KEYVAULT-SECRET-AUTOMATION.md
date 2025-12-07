# Key Vault Secret Automation

## Overview

Key Vault secrets are now **automatically populated** during the Azure bootstrap deployment process. This eliminates the manual step of adding secrets to Key Vault after infrastructure provisioning.

## What's Automated

The deployment workflow automatically adds the following secrets to Key Vault:

1. **OpenPayAdapter--ApiKey**
   - Required for payment processing integration
   - Uses placeholder value in dev/staging (update before production)
   - Can be overridden via script parameter

2. **ApplicationInsights--ConnectionString**
   - Auto-retrieved from Application Insights resource
   - Used for application telemetry and monitoring
   - No manual configuration needed

## How It Works

### Bootstrap Workflow Integration

The `azure-bootstrap.yml` workflow includes a new step after infrastructure provisioning:

```yaml
- name: Populate Key Vault Secrets
  run: |
    ./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev -BaseName orderprocessing
```

This step runs for all environments (dev, staging, prod) automatically.

### Script Execution Order

1. **Bootstrap Infrastructure** - Creates Key Vault, App Services, App Insights
2. **Provision SQL Database** - Creates SQL Server and Database
3. **Populate Key Vault Secrets** ← **NEW AUTOMATED STEP**
4. **Run Database Migrations** - Applies EF Core migrations
5. **Verify Application Insights** - Validates configuration
6. **Configure App Service Environment** - Sets ASPNETCORE_ENVIRONMENT

## Script Details

### populate-keyvault-secrets.ps1

**Location**: `Resources/Azure-Deployment/populate-keyvault-secrets.ps1`

**Parameters**:
- `Environment` (required): dev, staging, or prod
- `BaseName` (optional): Default 'orderprocessing'
- `OpenPayApiKey` (optional): Custom API key value
- `ApplicationInsightsConnectionString` (optional): Override auto-detection

**Features**:
- ✅ Idempotent - safe to run multiple times
- ✅ Auto-retrieves Application Insights connection string
- ✅ Generates placeholder API key for dev/staging
- ✅ Validates Key Vault exists before adding secrets
- ✅ Comprehensive error handling and logging
- ✅ Lists all secrets in Key Vault after population

## Manual Script Usage

You can also run the script manually if needed:

```powershell
# Basic usage
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 -Environment dev

# With custom API key
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 `
    -Environment prod `
    -OpenPayApiKey "your-actual-api-key"

# Override both secrets
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 `
    -Environment staging `
    -OpenPayApiKey "staging-api-key" `
    -ApplicationInsightsConnectionString "InstrumentationKey=..."
```

## Production Considerations

### OpenPayAdapter API Key

**Development/Staging**: Uses placeholder value `openpay-api-key-placeholder-{env}-{date}`

**Production**: Update the secret with the actual API key:

```powershell
# Option 1: Run script with actual key
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 `
    -Environment prod `
    -OpenPayApiKey "prod-openpay-api-key"

# Option 2: Update via Azure CLI
az keyvault secret set `
    --vault-name kv-orderproc-prod `
    --name "OpenPayAdapter--ApiKey" `
    --value "your-production-api-key"

# Option 3: Update via Azure Portal
# Navigate to Key Vault > Secrets > OpenPayAdapter--ApiKey > New Version
```

### Security Best Practices

1. **Never commit API keys to source control**
2. **Use GitHub Secrets** to pass sensitive values to workflows
3. **Rotate secrets regularly** using Azure Key Vault versioning
4. **Enable Key Vault soft delete** (already configured)
5. **Review access policies** to ensure least privilege

## Verification

After deployment, verify secrets were added:

```powershell
# List secrets in Key Vault
az keyvault secret list --vault-name kv-orderproc-dev --query "[].name"

# Expected output:
# [
#   "ApplicationInsights--ConnectionString",
#   "OpenPayAdapter--ApiKey"
# ]
```

Or check the workflow logs - the script outputs all secrets after population.

## Troubleshooting

### Script Fails with "Key Vault not found"

**Cause**: Key Vault hasn't been created yet or wrong environment specified

**Solution**: 
- Ensure bootstrap infrastructure step completed successfully
- Verify environment name matches (dev/staging/prod)
- Check resource group exists: `az group show --name rg-orderprocessing-dev`

### Script Fails with "Forbidden" or "Access Denied"

**Cause**: Insufficient permissions to add secrets

**Solution**:
- Ensure you have "Key Vault Secrets Officer" role or equivalent
- Check access policies: `az keyvault show --name kv-orderproc-dev`
- In GitHub Actions, ensure Managed Identity has Key Vault access

### Application Insights Connection String Not Retrieved

**Cause**: App Insights resource doesn't exist yet

**Solution**:
- Script will skip this secret if App Insights not found (non-fatal)
- Connection string can be added manually later if needed
- Re-run the script after App Insights is created

### Placeholder API Key in Production

**Warning**: Production should never use placeholder values

**Solution**:
- Update the secret before deploying application code
- Use the manual update commands shown above
- Consider adding a GitHub Secret for production API key

## Related Files

- **Script**: `Resources/Azure-Deployment/populate-keyvault-secrets.ps1`
- **Workflow**: `.github/workflows/azure-bootstrap.yml`
- **Bicep Template**: `bicep/appservice-with-kv.bicep` (Key Vault definition)

## Benefits

✅ **Zero Manual Steps** - Secrets added automatically during deployment  
✅ **Consistent** - Same process across all environments  
✅ **Repeatable** - Idempotent script can be run multiple times  
✅ **Auditable** - All secret operations logged in workflow  
✅ **Secure** - Uses managed identities and Azure RBAC  
✅ **Fast** - Completes in seconds as part of bootstrap  

## Next Steps

After automated secret population:

1. **Verify secrets** using verification commands above
2. **Update production API key** before production deployment
3. **Deploy application code** - secrets are ready for App Services to use
4. **Monitor Key Vault** - Set up alerts for secret access patterns

---

**Last Updated**: 2025-12-06  
**Version**: 1.0  
**Status**: ✅ Automated in azure-bootstrap.yml
