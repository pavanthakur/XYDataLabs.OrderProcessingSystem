# Bootstrap Enterprise Infrastructure - Workflow Summary

## Overview
**Script**: `bootstrap-enterprise-infra.ps1`  
**Purpose**: Provision complete Azure infrastructure for Order Processing System with GitHub Actions OIDC authentication  
**Execution Time**: ~10-20 minutes (depending on Azure resource provisioning)  
**Idempotent**: Yes - can be safely re-run without duplicating resources

---

## Prerequisites

### Required Tools
- ✅ Azure CLI installed and authenticated (`az login`)
- ✅ PowerShell 5.1+ (Windows) or PowerShell Core (cross-platform)
- ✅ Azure subscription with Contributor or Owner role
- ✅ GitHub CLI (gh) installed (optional - for automatic secret configuration)

### Required Parameters
| Parameter | Default | Description | Example |
|-----------|---------|-------------|---------|
| `SubscriptionId` | (current) | Azure subscription ID | `12345678-abcd-1234-abcd-123456789012` |
| `BaseName` | `orderprocessing` | Base name for all resources | `orderprocessing` |
| `Location` | `centralindia` | Azure region | `eastus`, `centralindia` |
| `Environment` | (required) | Target environment | `dev`, `stg`, or `prod` |
| `ApiSuffix` | `api-xyapp` | API app name suffix | `api-xyapp` |
| `UiSuffix` | `ui-xyapp` | UI app name suffix | `ui-xyapp` |
| `DevSku` | `F1` | Dev tier SKU | `F1` (Free), `B1` (Basic) |
| `StagingSku` | `B1` | Staging tier SKU | `B1` (Basic), `P1v3` (Premium) |
| `ProductionSku` | `P1v3` | Production tier SKU | `P1v3` (Premium) |

**⚠️ BREAKING CHANGE**: Parameter changed from `Environments` (plural, comma-separated) to `Environment` (singular, required). Script now processes one environment per execution.

### Example Execution
```powershell
# Development environment (required parameter)
.\bootstrap-enterprise-infra.ps1 -Environment dev

# Staging with custom location
.\bootstrap-enterprise-infra.ps1 -Environment stg -Location eastus

# Production with specific subscription
.\bootstrap-enterprise-infra.ps1 -Environment prod -SubscriptionId "12345678-abcd-1234-abcd-123456789012"

# IMPORTANT: Script processes ONE environment at a time
# To provision multiple environments, run the script multiple times:
.\bootstrap-enterprise-infra.ps1 -Environment dev
.\bootstrap-enterprise-infra.ps1 -Environment stg
.\bootstrap-enterprise-infra.ps1 -Environment prod
```

---

## Workflow Steps

### Phase 1: Initialization & Validation
**Duration**: ~30 seconds

1. **Subscription Selection**
   - Validates Azure CLI authentication
   - Sets active subscription (if specified)
   - Displays subscription name and ID

2. **Parallel OIDC App Registration** (Background Job)
   - Creates Azure AD App Registration: `GitHub-Actions-OIDC`
   - Creates Service Principal if not exists
   - Runs asynchronously while resource provisioning proceeds

---

### Phase 2: Resource Group & App Service Plan
**Duration**: ~2-5 minutes

3. **Resource Group Creation**
   - **Name Format**: `rg-{BaseName}-{Environment}`
   - **Example**: `rg-orderprocessing-dev`
   - **Tags**: `env={Environment}`, `app={BaseName}`
   - **Action**: Creates if not exists

4. **Resource Group Readiness Gate** ⚠️ CRITICAL
   - **Timeout**: 5 minutes
   - **Check Interval**: 60 seconds
   - **Validation**: `provisioningState == 'Succeeded'`
   - **Exit Condition**: Script aborts if RG not ready (prevents downstream failures)

5. **App Service Plan Creation**
   - **Name Format**: `asp-{BaseName}-{Environment}`
   - **Example**: `asp-orderprocessing-dev`
   - **SKU Mapping**:
     - `dev` → `F1` (Free tier, 1 GB RAM, 60 min/day)
     - `stg` → `B1` (Basic tier, 1.75 GB RAM, always on)
     - `prod` → `P1v3` (Premium tier, 4 GB RAM, autoscale)
   - **Retry Logic**: 3 attempts with 10-second delays

---

### Phase 3: Web App Creation (API + UI)
**Duration**: ~5-10 minutes

6. **API Web App Creation**
   - **Name Format**: `{BaseName}-{ApiSuffix}-{Environment}`
   - **Example**: `orderprocessing-api-xyapp-dev`
   - **Runtime**: .NET 8 (`dotnet:8`)
   - **Retry Logic**: 5 attempts with 15-second delays (synchronous)
   - **Existence Check**: Validates via `az webapp show` before creation
   - **Hardened Error Handling**: Treats CLI exit code ≠ 0 as "not found"

7. **UI Web App Creation**
   - **Name Format**: `{BaseName}-{UiSuffix}-{Environment}`
   - **Example**: `orderprocessing-ui-xyapp-dev`
   - **Runtime**: .NET 8 (`dotnet:8`)
   - **Retry Logic**: 5 attempts with 15-second delays (synchronous)
   - **Existence Check**: Validates via `az webapp show` before creation
   - **Hardened Error Handling**: Treats CLI exit code ≠ 0 as "not found"

8. **Application Insights Creation** (Background Job)
   - **Name Format**: `ai-{BaseName}-{Environment}`
   - **Example**: `ai-orderprocessing-dev`
   - **Type**: Web application monitoring
   - **Runs Asynchronously**: Created in parallel with web apps

---

### Phase 4: Unified Readiness Verification
**Duration**: ~5-10 minutes (or until all resources ready)

9. **Parallel Resource Readiness Checks**
   - **Timeout**: 10 minutes
   - **Check Interval**: 30 seconds
   - **Progress Display**: Visual progress bar with `#` indicators

   #### App Service Plan Readiness
   - **Criteria**: `provisioningState == 'Succeeded'` AND `status == 'Ready'`
   - **CLI Command**: `az appservice plan show`

   #### API Web App Readiness
   - **Criteria**: `state == 'Running'` AND HTTP endpoint responds (200 or 404)
   - **CLI Command**: `az webapp show`
   - **HTTP Check**: `Invoke-WebRequest -Uri https://{apiApp}.azurewebsites.net`
   - **Timeout**: 8 seconds per HTTP request

   #### UI Web App Readiness
   - **Criteria**: `state == 'Running'` AND HTTP endpoint responds (200 or 404)
   - **CLI Command**: `az webapp show`
   - **HTTP Check**: `Invoke-WebRequest -Uri https://{uiApp}.azurewebsites.net`
   - **Timeout**: 8 seconds per HTTP request

10. **Timeout Handling**
    - If 10-minute timeout reached, displays current status
    - Resources may still be provisioning (check Azure Portal)
    - Script continues with verification (does NOT abort)

---

### Phase 5: Resource Verification & Configuration
**Duration**: ~2-3 minutes

11. **Comprehensive Resource Verification**
    - **App Service Plan**: Confirms `Status == 'Ready'`, `State == 'Succeeded'`, displays SKU
    - **Application Insights**: Confirms `ProvisioningState == 'Succeeded'`
    - **API Web App**: Verifies existence and state
    - **UI Web App**: Verifies existence and state

12. **Runtime Configuration**
    - **Target**: .NET 8 (`netFrameworkVersion == 'v8.0'`)
    - **Action**: Configures if not set or incorrect
    - **Validation**: Re-checks after configuration
    - **Fallback**: Displays manual configuration steps if CLI fails

13. **Application Insights Connection String Configuration**
    - **Target**: API and UI web apps
    - **Setting Name**: `APPLICATIONINSIGHTS_CONNECTION_STRING`
    - **Action**: Sets via `az webapp config appsettings set`
    - **Condition**: Skipped if timeout occurred (to avoid hanging)

---

### Phase 6: OIDC Authentication & RBAC Setup
**Duration**: ~2-3 minutes

14. **OIDC Job Completion**
    - Waits for parallel OIDC job (started in Phase 1)
    - Retrieves App Registration details
    - Displays Client ID, Tenant ID, Service Principal Object ID

15. **Federated Credential Configuration**
    - **GitHub Repository**: `getpavanthakur/TestAppXY_OrderProcessingSystem`
    - **Branch Mapping**:
      | Branch | Credential Name | Subject |
      |--------|-----------------|---------|
      | `dev` | `github-dev-oidc` | `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev` |
      | `staging` | `github-staging-oidc` | `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/staging` |
      | `main` | `github-main-oidc` | `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/main` |
    - **Issuer**: `https://token.actions.githubusercontent.com`
    - **Audience**: `api://AzureADTokenExchange`
    - **Idempotent**: Skips if credential already exists

16. **RBAC Role Assignment**
    - **Role**: Contributor
    - **Scope**: Resource Group level (`/subscriptions/{subscriptionId}/resourceGroups/{rg}`)
    - **Assignee**: Service Principal Object ID
    - **Idempotent**: Checks for existing assignment before creating

17. **GitHub Repository Secrets**
    - **Secret Names**:
      - `AZUREAPPSERVICE_CLIENTID` (App Registration Client ID)
      - `AZUREAPPSERVICE_TENANTID` (Azure AD Tenant ID)
      - `AZUREAPPSERVICE_SUBSCRIPTIONID` (Azure Subscription ID)
    - **Clipboard Copy**: Automatically copies secrets to clipboard
    - **Automatic Configuration**: Calls `configure-github-secrets.ps1` if present
    - **Manual Fallback**: Displays GitHub secrets page URL

---

### Phase 7: Post-Deployment Testing
**Duration**: ~30 seconds

18. **Self-Test Execution**
    - **API Health Check**: HTTP GET to `https://{apiApp}.azurewebsites.net`
    - **UI Health Check**: HTTP GET to `https://{uiApp}.azurewebsites.net`
    - **Timeout**: 10 seconds per endpoint
    - **Accepted Status Codes**: 200, 404 (404 is OK - app deployed but no routes configured yet)

---

### Phase 8: Reporting & Logging
**Duration**: ~10 seconds

19. **Summary Report**
    - Displays table of provisioned resources:
      - Environment
      - Resource Group
      - App Service Plan
      - API Web App
      - UI Web App
      - SKU
      - Application Insights
    - Shows total execution time
    - Displays step-by-step status summary (Success/Failed/Warning)

20. **Log File Output**
    - **Log Location**: `logs/bootstrap-{date}.log`
    - **CSV Export**: `logs/step-summary-{datetime}.csv`
    - **Format**: Timestamped entries with severity levels (INFO/WARN/ERROR)

21. **Next Steps Guidance**
    - Lists completed actions (OIDC, branches, secrets)
    - Provides deployment instructions
    - Shows branch-to-environment mapping:
      ```
      dev branch     → orderprocessing-api-xyapp-dev, orderprocessing-ui-xyapp-dev
      staging branch → orderprocessing-api-xyapp-stg, orderprocessing-ui-xyapp-stg
      main branch    → (future production resources)
      ```

---

## Resource Naming Conventions

### Naming Patterns
| Resource Type | Pattern | Example (dev) |
|--------------|---------|---------------|
| Resource Group | `rg-{base}-{env}` | `rg-orderprocessing-dev` |
| App Service Plan | `asp-{base}-{env}` | `asp-orderprocessing-dev` |
| API Web App | `{base}-{apisuffix}-{env}` | `orderprocessing-api-xyapp-dev` |
| UI Web App | `{base}-{uisuffix}-{env}` | `orderprocessing-ui-xyapp-dev` |
| Application Insights | `ai-{base}-{env}` | `ai-orderprocessing-dev` |
| OIDC App Registration | `GitHub-Actions-OIDC` | (shared across environments) |

### Environment Suffixes
- `dev` - Development (F1 Free tier)
- `stg` - Staging (B1 Basic tier)
- `prod` - Production (P1v3 Premium tier)

---

## Error Handling & Retry Logic

### Retry Mechanisms

#### 1. Web App Creation Retry (`New-WebAppWithSuperRetry`)
- **Attempts**: 5
- **Delay**: 15 seconds between attempts
- **Scope**: API and UI web app creation
- **Action**: Returns error object if all attempts fail

#### 2. Generic Azure CLI Retry (`Invoke-AzCommandWithRetry`)
- **Attempts**: 3
- **Delay**: 10 seconds between attempts
- **Scope**: App Service Plan creation, general Azure commands
- **Action**: Returns error object if all attempts fail

#### 3. Resource Group Readiness Wait (`Wait-ForResourceGroupReady`)
- **Timeout**: 5 minutes
- **Check Interval**: 60 seconds
- **Scope**: Resource Group provisioning
- **Action**: Aborts script if RG not ready (critical failure)

#### 4. Unified Readiness Wait (Phase 4)
- **Timeout**: 10 minutes
- **Check Interval**: 30 seconds
- **Scope**: App Service Plan, API Web App, UI Web App
- **Action**: Continues with warnings if timeout reached (non-critical)

### Critical Failure Points (Script Aborts)
1. ❌ Resource Group not ready after 5 minutes
2. ❌ App Service Plan creation fails after 3 retries

### Non-Critical Failures (Script Continues)
1. ⚠️ Web App creation fails (recorded in step status)
2. ⚠️ Application Insights creation fails
3. ⚠️ Runtime configuration fails (manual steps provided)
4. ⚠️ Self-test health checks fail

---

## Output Artifacts

### 1. Log Files
- **Location**: `logs/bootstrap-{date}.log`
- **Format**: Timestamped console output with color coding
- **Contents**: All script actions, errors, warnings, and resource details

### 2. Step Summary CSV
- **Location**: `logs/step-summary-{datetime}.csv`
- **Format**: CSV with columns: Name, Status, Details
- **Contents**: Structured status of each provisioning step

### 3. Clipboard Content
- **Format**: Plain text
- **Contents**: GitHub repository secrets (Client ID, Tenant ID, Subscription ID)

### 4. Console Output
- **Real-time Progress**: Visual progress bars with `#` indicators
- **Color Coding**:
  - 🟢 Green: Success
  - 🟡 Yellow: Warnings, pending actions
  - 🔴 Red: Errors, failures
  - 🔵 Cyan: Informational messages
  - ⚪ Gray: Skipped actions

---

## Verification Checklist

### ✅ Pre-Execution Checklist
- [ ] Azure CLI installed and authenticated (`az account show`)
- [ ] PowerShell 5.1+ available (`$PSVersionTable.PSVersion`)
- [ ] Azure subscription has Contributor or Owner role
- [ ] Correct environment parameter specified (`dev`, `stg`, or `prod`)
- [ ] No conflicting resources with same names in subscription
- [ ] GitHub repository exists: `getpavanthakur/TestAppXY_OrderProcessingSystem`

### ✅ Post-Execution Verification

#### Azure Portal Checks
- [ ] Resource Group created and shows `Succeeded` state
  - Navigate to: https://portal.azure.com → Resource Groups → `rg-orderprocessing-{env}`
- [ ] App Service Plan shows `Ready` status with correct SKU
  - Check: Resource Group → App Service Plan → Overview
- [ ] API Web App shows `Running` state
  - Check: Resource Group → `orderprocessing-api-xyapp-{env}` → Overview
  - Verify URL: `https://orderprocessing-api-xyapp-{env}.azurewebsites.net`
- [ ] UI Web App shows `Running` state
  - Check: Resource Group → `orderprocessing-ui-xyapp-{env}` → Overview
  - Verify URL: `https://orderprocessing-ui-xyapp-{env}.azurewebsites.net`
- [ ] Application Insights created and linked
  - Check: Resource Group → `ai-orderprocessing-{env}` → Overview
  - Verify connection string configured in web app settings

#### Azure AD Checks
- [ ] App Registration exists: `GitHub-Actions-OIDC`
  - Navigate to: Azure Portal → Azure Active Directory → App Registrations
  - Note Client ID matches GitHub secret
- [ ] Service Principal exists
  - Navigate to: Azure AD → Enterprise Applications → Search for App ID
- [ ] Federated credentials configured (3 total)
  - Check: App Registration → Certificates & secrets → Federated credentials
  - Verify credentials: `github-dev-oidc`, `github-staging-oidc`, `github-main-oidc`
- [ ] RBAC role assigned
  - Navigate to: Resource Group → Access control (IAM) → Role assignments
  - Verify: Service Principal has Contributor role

#### Web App Configuration Checks
- [ ] Runtime configured as .NET 8
  - Check: Web App → Configuration → General settings → Stack: `.NET 8 (LTS)`
- [ ] Application Insights connection string set
  - Check: Web App → Configuration → Application settings
  - Verify key: `APPLICATIONINSIGHTS_CONNECTION_STRING`

#### GitHub Checks
- [ ] Repository secrets configured
  - Navigate to: https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions
  - Verify secrets:
    - `AZUREAPPSERVICE_CLIENTID`
    - `AZUREAPPSERVICE_TENANTID`
    - `AZUREAPPSERVICE_SUBSCRIPTIONID`
- [ ] Branches exist: `dev`, `staging`, `main`
  - Check: Repository → Branches
  - Verify protection rules configured (optional)

#### Script Output Checks
- [ ] Log file created in `logs/` directory
- [ ] Step summary CSV created in `logs/` directory
- [ ] All steps show `Success` status (or documented warnings acceptable)
- [ ] Self-test results show API and UI healthy (or 404 acceptable pre-deployment)
- [ ] Total execution time recorded in console output

#### Functional Checks
- [ ] API endpoint responds (may be 404 if no code deployed yet)
  ```powershell
  Invoke-WebRequest -Uri https://orderprocessing-api-xyapp-{env}.azurewebsites.net -Method Get
  ```
- [ ] UI endpoint responds (may be 404 if no code deployed yet)
  ```powershell
  Invoke-WebRequest -Uri https://orderprocessing-ui-xyapp-{env}.azurewebsites.net -Method Get
  ```
- [ ] Application Insights receiving telemetry (after first deployment)
  - Check: Application Insights → Live Metrics

---

## Common Issues & Troubleshooting

### Issue: Resource Group Not Ready After 5 Minutes
**Symptoms**: Script aborts with `[CRITICAL] Resource group not ready`  
**Cause**: Azure Control Plane latency or subscription throttling  
**Resolution**:
1. Check Azure Portal manually for RG status
2. If RG exists and shows `Succeeded`, re-run script (idempotent)
3. If RG shows `Failed`, delete and retry: `az group delete -n rg-orderprocessing-{env}`

### Issue: Web App Creation Fails After 5 Retries
**Symptoms**: `[ERROR] az webapp create failed`  
**Cause**: App Service Plan not fully provisioned, name conflict, or quota exceeded  
**Resolution**:
1. Verify App Service Plan status: `az appservice plan show -g rg-orderprocessing-{env} -n asp-orderprocessing-{env}`
2. Check for name conflicts: `az webapp list --query "[?name=='orderprocessing-api-xyapp-{env}']"`
3. Verify subscription quota: Azure Portal → Subscriptions → Usage + quotas

### Issue: Runtime Configuration Shows Warning
**Symptoms**: `[WARN] Runtime: <unexpected> (expected v8.0)`  
**Cause**: Azure CLI not updating runtime via `az webapp config set`  
**Resolution**:
1. Configure manually in Azure Portal:
   - Navigate to Web App → Configuration → General settings
   - Set Stack to `.NET 8 (LTS)`
   - Click Save

### Issue: OIDC App Registration Fails
**Symptoms**: `[WARN] OIDC setup encountered errors`  
**Cause**: Insufficient permissions to create App Registrations (requires Application Administrator role)  
**Resolution**:
1. Run separate OIDC setup script: `.\setup-github-oidc.ps1 -Branches main,staging,dev`
2. Request Application Administrator role from Azure AD admin
3. Use existing App Registration if available

### Issue: Automatic GitHub Secrets Configuration Fails
**Symptoms**: `[WARN] Automatic secret configuration failed`  
**Cause**: GitHub CLI not installed, not authenticated, or insufficient repository permissions  
**Resolution**:
1. Manual configuration via GitHub UI (secrets copied to clipboard)
2. Install GitHub CLI: `winget install GitHub.cli`
3. Authenticate: `gh auth login`
4. Run manual secret configuration: `.\configure-github-secrets.ps1 -Repository getpavanthakur/TestAppXY_OrderProcessingSystem`

### Issue: Self-Test Health Checks Fail
**Symptoms**: `[FAIL] Post-Deployment Self-Test FAILED`  
**Cause**: Web apps not responding (no code deployed yet, or startup delay)  
**Resolution**:
1. This is **EXPECTED** if no application code deployed yet (404 is acceptable)
2. Wait 2-5 minutes for full app startup
3. Test manually:
   ```powershell
   Invoke-WebRequest -Uri https://orderprocessing-api-xyapp-{env}.azurewebsites.net
   ```
4. Check Web App logs: Azure Portal → Web App → Log stream

### Issue: Timeout During Unified Readiness Wait
**Symptoms**: `[TIMEOUT] Readiness wait reached 10-minute limit`  
**Cause**: Azure resource provisioning slower than expected (region load, SKU tier)  
**Resolution**:
1. Check Azure Portal for actual resource status (may be ready despite timeout)
2. Re-run verification steps manually:
   ```powershell
   az appservice plan show -g rg-orderprocessing-{env} -n asp-orderprocessing-{env}
   az webapp show -g rg-orderprocessing-{env} -n orderprocessing-api-xyapp-{env}
   ```
3. If resources show `Succeeded`/`Running`, continue with deployment (non-critical)

---

## Integration with CI/CD Pipeline

### GitHub Actions Workflow Trigger
After bootstrap completion, GitHub Actions workflows automatically deploy to corresponding environments based on branch:

```yaml
# .github/workflows/deploy-dev.yml (example)
on:
  push:
    branches: [dev]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read
    steps:
      - uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
          tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
          subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}
      
      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v2
        with:
          app-name: orderprocessing-api-xyapp-dev
          package: ./publish
```

### Deployment Flow
1. Developer pushes to `dev` branch
2. GitHub Actions triggers `deploy-dev.yml`
3. OIDC authenticates using `github-dev-oidc` federated credential
4. Workflow deploys to `orderprocessing-api-xyapp-dev` and `orderprocessing-ui-xyapp-dev`
5. Application Insights captures deployment telemetry

---

## Maintenance & Updates

### Re-running the Script
The script is fully idempotent and can be safely re-run:
- Existing resources are detected and skipped
- New resources are created if missing
- No duplicate resources will be created
- OIDC credentials and RBAC assignments are checked before creation

### Adding New Environments
To add a new environment (e.g., `qa`):
1. Run bootstrap: `.\bootstrap-enterprise-infra.ps1 -Environment qa`
2. Add SKU mapping in script if needed (defaults to `B1`)
3. Create corresponding GitHub branch: `qa`
4. Federated credential will be created automatically for `qa` branch

### Updating SKUs
To change environment SKUs:
1. Modify `DevSku`, `StagingSku`, or `ProductionSku` parameters
2. Re-run bootstrap with updated parameters
3. Azure will resize App Service Plan (may incur downtime)

### Cleanup
To remove an environment:
```powershell
# Delete entire resource group (WARNING: Irreversible)
az group delete -n rg-orderprocessing-dev --yes --no-wait

# Remove federated credential
az ad app federated-credential delete --id <app-object-id> --federated-credential-id <cred-id>

# Remove RBAC assignment
az role assignment delete --assignee <sp-object-id> --role Contributor --scope /subscriptions/{sub}/resourceGroups/rg-orderprocessing-dev
```

---

## Security Considerations

### OIDC vs Service Principal Secrets
✅ **OIDC Benefits**:
- No long-lived credentials stored in GitHub
- Automatic token expiration (1 hour)
- Branch-specific authentication scope
- Federated trust via Azure AD

❌ **Service Principal Secrets (Avoided)**:
- Long-lived secrets require rotation
- Broader access scope
- Vulnerable if leaked

### Least Privilege RBAC
- Service Principal has **Contributor** role scoped to **Resource Group** only
- Cannot create/delete resource groups or subscription-level resources
- Cannot manage Azure AD objects outside app registration

### Secret Management
- GitHub secrets never logged or displayed
- Clipboard contains secrets (cleared manually after use)
- Log files do NOT contain secrets (Client ID is non-sensitive)

---

## Appendix: Script Metadata

### Version Information
- **Script Version**: 1.0
- **Last Updated**: 2025-01-16
- **PowerShell Requirement**: 5.1+
- **Azure CLI Requirement**: 2.50.0+

### Helper Functions
1. `Write-Log` - Dual output (console + file) with timestamps
2. `New-WebAppWithSuperRetry` - Web App creation with 5 retries
3. `Test-WebEndpoint` - HTTP health check with timeout
4. `Add-StepStatus` - Step tracking for summary report
5. `Invoke-AzCommandWithRetry` - Generic Azure CLI retry wrapper
6. `Wait-ForWebAppProvisioning` - Dual CLI + HTTP readiness check
7. `Wait-ForResourceGroupReady` - Resource Group readiness gate
8. `Resolve-Sku` - Environment-to-SKU mapping

### Exit Codes
- `0` - Success (all critical steps completed)
- `1` - Critical failure (Resource Group or App Service Plan not ready)

### Log Severity Levels
- **INFO** - Normal operation (Green/Cyan)
- **WARN** - Non-critical issues (Yellow)
- **ERROR** - Critical failures (Red)

---

## Support & References

### Azure Documentation
- [App Service Plans](https://learn.microsoft.com/azure/app-service/overview-hosting-plans)
- [Azure AD Workload Identity](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)
- [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview)

### GitHub Actions
- [OIDC with Azure](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Login Action](https://github.com/Azure/login)
- [Azure Web Apps Deploy Action](https://github.com/Azure/webapps-deploy)

### Internal Scripts
- `setup-github-oidc.ps1` - Manual OIDC configuration
- `configure-github-secrets.ps1` - Automatic GitHub secrets setup
- `teardown-azure-resources.ps1` - Environment cleanup (if available)

---

## Document Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-01-20 | Initial documentation from script analysis | GitHub Copilot |

