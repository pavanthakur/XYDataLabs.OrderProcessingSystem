# Verification Scripts

This directory contains automated verification scripts for validating Azure infrastructure setup.

## Key Vault Verification Scripts

These scripts validate the Key Vault setup created by PR#54 and the GitHub workflow automation from PR#5.

### PowerShell Script

**File**: `Verify-KeyVaultSetup.ps1`

**Requirements**:
- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Azure PowerShell module (`Az`)

**Installation** (if needed):
```powershell
Install-Module -Name Az -Repository PSGallery -Force
```

**Usage**:
```powershell
# Basic usage
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"

# With custom Key Vault name
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev" -KeyVaultName "custom-kv-name"

# For staging environment
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-staging" -Environment "staging"
```

**What It Checks**:
- ✅ Key Vault existence and configuration
- ✅ Soft delete settings (90-day retention)
- ✅ Required secrets (OpenPayAdapter--ApiKey, ApplicationInsights--ConnectionString)
- ✅ App Service managed identity configuration
- ✅ Key Vault access policies and permissions
- ✅ App Settings with Key Vault references

**Output**:
- Detailed step-by-step verification results
- Color-coded status indicators (Green = Pass, Red = Fail, Yellow = Warning)
- Actionable remediation commands for any issues found
- Summary report with overall status

### Bash/Azure CLI Script

**File**: `verify-keyvault-setup.sh`

**Requirements**:
- Bash shell (Linux, macOS, WSL, Git Bash)
- Azure CLI (`az`)
- `jq` (for JSON parsing)

**Installation** (if needed):
```bash
# Install Azure CLI (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install jq
sudo apt-get install jq      # Ubuntu/Debian
sudo yum install jq          # CentOS/RHEL
sudo dnf install jq          # Fedora
brew install jq              # macOS
```

**Usage**:
```bash
# Make script executable (first time only)
chmod +x verify-keyvault-setup.sh

# Basic usage
./verify-keyvault-setup.sh rg-orderprocessing-dev dev

# For staging environment
./verify-keyvault-setup.sh rg-orderprocessing-staging staging

# For production
./verify-keyvault-setup.sh rg-orderprocessing-prod prod
```

**What It Checks**:
- Same checks as PowerShell script
- Provides equivalent verification functionality
- Uses Azure CLI commands instead of PowerShell cmdlets

**Output**:
- Similar format to PowerShell script
- Color-coded terminal output
- Exit code 0 = success, 1 = failure (useful for CI/CD)

## Authentication

Before running these scripts, you must be authenticated to Azure:

**PowerShell**:
```powershell
Connect-AzAccount
```

**Azure CLI**:
```bash
az login
```

## Common Scenarios

### First-Time Setup Verification

After deploying your infrastructure for the first time:

```powershell
# Run verification
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"

# If secrets are missing (expected), add them:
az keyvault secret set --vault-name kv-orderproc-dev \
  --name "OpenPayAdapter--ApiKey" --value "your-api-key"

az keyvault secret set --vault-name kv-orderproc-dev \
  --name "ApplicationInsights--ConnectionString" --value "your-connection-string"

# Run verification again to confirm
.\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
```

### Troubleshooting Failed Deployment

If deployment failed or Key Vault references aren't working:

```bash
# Run verification to identify issues
./verify-keyvault-setup.sh rg-orderprocessing-dev dev

# Follow the remediation commands provided in the output
```

### Regular Health Check

Set up a regular verification schedule:

```powershell
# Create a scheduled task to run weekly
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
  -Argument "-File C:\path\to\Verify-KeyVaultSetup.ps1 -ResourceGroupName 'rg-orderprocessing-prod' -Environment 'prod'"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "KeyVault-Weekly-Check"
```

### CI/CD Integration

Integrate into your pipeline:

**Azure DevOps**:
```yaml
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'Your-Service-Connection'
    ScriptType: 'FilePath'
    ScriptPath: '$(Build.SourcesDirectory)/Scripts/Verify-KeyVaultSetup.ps1'
    ScriptArguments: '-ResourceGroupName "rg-orderprocessing-$(Environment)" -Environment "$(Environment)"'
    azurePowerShellVersion: 'LatestVersion'
```

**GitHub Actions**:
```yaml
- name: Verify Key Vault Setup
  run: |
    ./Scripts/verify-keyvault-setup.sh rg-orderprocessing-${{ github.event.inputs.environment }} ${{ github.event.inputs.environment }}
```

## Exit Codes

Both scripts return exit codes for automation:

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | All checks passed |
| 1 | Failure | One or more critical checks failed |

Example usage in CI/CD:
```bash
./verify-keyvault-setup.sh rg-orderprocessing-dev dev
if [ $? -eq 0 ]; then
  echo "Verification passed, proceeding with deployment"
else
  echo "Verification failed, stopping deployment"
  exit 1
fi
```

## Output Examples

### Successful Verification

```
╔════════════════════════════════════════════════════════════╗
║   Key Vault Verification - Order Processing System        ║
║   Environment: dev                                         ║
╚════════════════════════════════════════════════════════════╝

🔐 Checking Azure authentication...
✅ Logged in as: user@example.com
   Subscription: My Azure Subscription

📦 Step 1: Checking Key Vault existence...
✅ Key Vault 'kv-orderproc-dev' found
   Location: centralindia
   Vault URI: https://kv-orderproc-dev.vault.azure.net/

🔧 Step 2: Checking Key Vault configuration...
   Soft Delete Enabled: true
   Soft Delete Retention: 90 days
   ✅ Matches PR#54 specification (90 days)

🔑 Step 3: Checking required secrets...
   ✅ Secret 'OpenPayAdapter--ApiKey' exists
   ✅ Secret 'ApplicationInsights--ConnectionString' exists

🌐 Step 4: Checking App Service configuration...
   📱 App Service: myorg-orderprocessing-api-xyapp-dev
      ✅ System-Assigned Managed Identity enabled
      ✅ Managed Identity has Key Vault access
      ✅ Found 2 Key Vault reference(s)

✅ Overall Status: SUCCESS
   All critical checks passed!
```

### Failed Verification with Remediation

```
❌ Secret 'OpenPayAdapter--ApiKey' NOT FOUND
   Action required: Create this secret in Key Vault

⚠️  Missing Secrets - Manual Action Required:
   Run the following commands to add missing secrets:
   az keyvault secret set --vault-name kv-orderproc-dev --name "OpenPayAdapter--ApiKey" --value "<your-value>"
```

## Documentation

For more information:

- **Comprehensive Guide**: `../Documentation/KEY-VAULT-VERIFICATION-GUIDE.md`
- **Quick Checklist**: `../Documentation/KEY-VAULT-QUICK-CHECKLIST.md`
- **PR Summary**: `../Documentation/PR-54-AND-PR-5-SUMMARY.md`

## Troubleshooting

### Script Execution Issues

**PowerShell Execution Policy Error**:
```powershell
# Allow script execution for current session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**Azure Module Not Found**:
```powershell
# Install Azure PowerShell module
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber
```

**Permission Denied (Bash)**:
```bash
# Make script executable
chmod +x verify-keyvault-setup.sh
```

### Authentication Issues

**Not Logged In**:
```powershell
# PowerShell
Connect-AzAccount

# Azure CLI
az login
```

**Wrong Subscription**:
```powershell
# PowerShell
Set-AzContext -SubscriptionName "Your Subscription Name"

# Azure CLI
az account set --subscription "Your Subscription Name"
```

### Insufficient Permissions

If you get "access denied" errors:
- Verify you have at least **Reader** role on the resource group
- For Key Vault access, you need permission to list access policies
- For App Service configuration, you need permission to view app settings

Contact your Azure administrator to grant necessary permissions.

## Contributing

If you enhance these scripts or find issues:
1. Test your changes thoroughly
2. Update this README with any new features or requirements
3. Update the corresponding documentation files
4. Submit a pull request with a clear description

## Support

For issues or questions:
1. Check the [KEY-VAULT-VERIFICATION-GUIDE.md](../Documentation/KEY-VAULT-VERIFICATION-GUIDE.md) troubleshooting section
2. Review the [PR-54-AND-PR-5-SUMMARY.md](../Documentation/PR-54-AND-PR-5-SUMMARY.md)
3. Check GitHub Actions workflow logs
4. Contact the DevOps team
