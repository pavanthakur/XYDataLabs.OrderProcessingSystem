# Retry Logic Implementation for Azure CLI Connection Errors

## Overview
This document describes the retry logic implementation added to PowerShell deployment scripts to handle transient network errors (ConnectionResetError 10054) when making Azure CLI calls.

## Problem Statement
The PowerShell scripts `enable-managed-identity.ps1` and `populate-keyvault-secrets.ps1` were experiencing intermittent ConnectionResetError (10054) errors:
```
ERROR: ('Connection aborted.', ConnectionResetError(10054, 'An existing connection was forcibly closed by the remote host', None, 10054, None))
```

This is a transient network error that occurs when:
- Network connectivity is temporarily interrupted
- Azure CLI connection is reset by the remote host
- Timeouts occur during Azure API calls
- Load balancers or firewalls drop connections

## Solution
Implemented a retry mechanism with exponential backoff to automatically retry failed Azure CLI commands.

### Retry Function: `Invoke-AzCommandWithRetry`

```powershell
function Invoke-AzCommandWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$InitialDelaySeconds = 2
    )
    
    # Retries with exponential backoff: 2s, 4s, 8s
    # Detects connection errors in command output
    # Returns structured result: @{ Success, Output, ExitCode }
}
```

### Parameters
- **Command**: The Azure CLI command to execute
- **MaxRetries**: Maximum number of retry attempts (default: 3)
- **InitialDelaySeconds**: Initial delay between retries (default: 2 seconds, doubles each retry)

### Behavior
1. Executes the Azure CLI command
2. Captures both stdout and stderr
3. Checks exit code and output for connection errors
4. If connection error detected and retries remain:
   - Displays warning message with retry count
   - Waits with exponential backoff (2s → 4s → 8s)
   - Retries the command
5. Returns structured result with success status and output

### Return Value
```powershell
@{
    Success = $true/$false    # Whether command succeeded (exit code 0)
    Output = "command output"  # stdout/stderr from command
    ExitCode = 0               # Command exit code
}
```

## Scripts Updated

### 1. enable-managed-identity.ps1
**18 Azure CLI commands wrapped with retry logic:**
- Resource group verification
- Key Vault existence check
- App Service existence checks (API and UI)
- Managed Identity assignment (API and UI)
- Access policy checks and grants (API and UI)
- KEY_VAULT_NAME environment variable configuration (API and UI)

### 2. populate-keyvault-secrets.ps1
**11 Azure CLI commands wrapped with retry logic:**
- Key Vault verification
- Key Vault listing
- Application Insights connection string retrieval
- Secret creation (OpenPayAdapter--ApiKey)
- Secret creation (ApplicationInsights--ConnectionString)
- Secret listing for verification
- App Service checks (API and UI)
- KEY_VAULT_NAME environment variable configuration (API and UI)

## Example Usage

### Before (Original Code)
```powershell
$apiIdentity = az webapp identity show -g $rgName -n $apiAppName --query principalId -o tsv 2>$null
if ($LASTEXITCODE -eq 0) {
    # Process result
}
```

### After (With Retry Logic)
```powershell
$identityCmd = "az webapp identity show -g $rgName -n $apiAppName --query principalId -o tsv"
$identityResult = Invoke-AzCommandWithRetry -Command $identityCmd

if ($identityResult.Success) {
    $apiIdentity = $identityResult.Output.Trim()
    # Process result
}
```

## Error Handling

### Connection Errors (Retry Enabled)
The function automatically retries when detecting these patterns:
- `ConnectionResetError`
- `Connection aborted`
- `forcibly closed`

Example output:
```
⚠️  Connection error on attempt 1/3, retrying in 2 seconds...
⚠️  Connection error on attempt 2/3, retrying in 4 seconds...
✅ Command succeeded on attempt 3
```

### Other Errors (No Retry)
Non-connection errors are not retried and propagate to the caller:
- Authentication errors
- Permission denied
- Resource not found
- Invalid parameters

## Security Considerations

### Command Construction
The retry function uses `Invoke-Expression` to execute Azure CLI commands. This is necessary because:
1. Azure CLI commands require shell execution with parameter parsing
2. Commands are constructed within the script from validated parameters
3. Variables come from Azure CLI output or script parameters, not external user input

### Input Validation
- Script parameters are validated using PowerShell's built-in validation attributes
- Azure CLI itself validates all resource names, object IDs, and parameters
- Resource names follow Azure naming conventions enforced by Azure CLI
- Object IDs (Managed Identities) are GUIDs returned by Azure, not user-controlled

### Execution Context
These scripts are designed to be run by:
- Azure administrators with proper permissions
- CI/CD pipelines with service principal authentication
- DevOps engineers managing Azure infrastructure

The scripts require:
- Azure CLI installed and configured
- Authenticated Azure session (`az login`)
- Appropriate Azure RBAC permissions

## Testing

### Unit Tests
`test-retry-logic.ps1` provides basic validation of the retry function:
- Successful command execution
- Exit code handling
- Parameter validation

### Integration Testing
To test the retry logic in a real environment:
```powershell
# Test enable-managed-identity.ps1
./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment dev

# Test populate-keyvault-secrets.ps1
./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev

# Verify results
./Resources/Azure-Deployment/diagnose-keyvault-access.ps1 -Environment dev
./Resources/Azure-Deployment/verify-azure-setup.ps1
```

## Expected Impact

### Before
- Scripts failed immediately on ConnectionResetError
- Manual re-execution required
- Intermittent failures in CI/CD pipelines
- Poor user experience with transient errors

### After
- Automatic retry on connection errors
- Self-healing behavior for transient failures
- Improved reliability in CI/CD pipelines
- Clear progress indication during retries
- Graceful degradation when retries are exhausted

## Monitoring

To monitor retry behavior, check script output for:
```
⚠️  Connection error on attempt X/3, retrying in Y seconds...
```

Frequent retry messages may indicate:
- Network connectivity issues
- Azure service degradation
- Rate limiting or throttling
- Firewall or proxy issues

## Future Improvements

Potential enhancements for future iterations:
1. Configurable retry patterns (linear, exponential, jitter)
2. Per-command retry configuration
3. Retry telemetry and logging
4. Circuit breaker pattern for repeated failures
5. Alternative command execution methods (e.g., direct Azure PowerShell module calls)

## References
- [Azure CLI Documentation](https://learn.microsoft.com/en-us/cli/azure/)
- [Retry Pattern (Azure Architecture)](https://learn.microsoft.com/en-us/azure/architecture/patterns/retry)
- [Exponential Backoff Algorithm](https://en.wikipedia.org/wiki/Exponential_backoff)
