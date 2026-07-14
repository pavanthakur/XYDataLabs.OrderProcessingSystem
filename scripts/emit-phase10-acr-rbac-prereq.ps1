param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [string]$ResourceGroupPrefix = 'rg-orderprocessing'
)

$resourceGroupName = "$ResourceGroupPrefix-$Environment"
$resourceGroupScope = "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName"

$principalObjectId = $null
try {
    $principalObjectId = (az ad sp show --id $ClientId --query id -o tsv 2>$null).Trim()
} catch {
    $principalObjectId = $null
}

if ([string]::IsNullOrWhiteSpace($principalObjectId)) {
    $principalObjectId = '<service-principal-object-id>'
}

$createCommand = @(
    'az role assignment create',
    "  --assignee-object-id $principalObjectId",
    '  --assignee-principal-type ServicePrincipal',
    '  --role "User Access Administrator"',
    "  --scope `"$resourceGroupScope`""
)

$verifyCommand = @(
    'az role assignment list',
    "  --scope `"$resourceGroupScope`"",
    "  --assignee $principalObjectId",
    '  -o table'
)

$summary = @'
## Dynamic ACR RBAC prerequisite

This helper resolves the current Phase 10 deployment principal after az login, then prints the exact command needed to grant the workflow the minimum scope required for ACR bootstrap.

| Field | Value |
|---|---|
| Environment | __ENV__ |
| Subscription | __SUBSCRIPTION__ |
| Resource group scope | __SCOPE__ |
| Deployment principal object id | __PRINCIPAL__ |

### Grant command

```bash
__CREATE_COMMAND__
```

### Verify command

```bash
__VERIFY_COMMAND__
```

### Why this exists

The Phase 10 ACR bootstrap creates the AcrPull role assignment on the registry. That means the GitHub OIDC deployment principal needs Microsoft.Authorization/roleAssignments/write at the environment resource-group scope the first time the stack is created or recreated.
'@

$summary = $summary.Replace('__ENV__', $Environment)
$summary = $summary.Replace('__SUBSCRIPTION__', $SubscriptionId)
$summary = $summary.Replace('__SCOPE__', $resourceGroupScope)
$summary = $summary.Replace('__PRINCIPAL__', $principalObjectId)
$summary = $summary.Replace('__CREATE_COMMAND__', ($createCommand -join [Environment]::NewLine))
$summary = $summary.Replace('__VERIFY_COMMAND__', ($verifyCommand -join [Environment]::NewLine))

if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary
} else {
    Write-Host $summary
}
