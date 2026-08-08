param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$ServiceBusNamespaceName,
    [string]$ConnectionString,
    [string]$RunId,
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'

$resourceSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$brokerSuffix = $Environment
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-orderprocessing-$resourceSuffix" } else { $ResourceGroupName }
$namespace = if ([string]::IsNullOrWhiteSpace($ServiceBusNamespaceName)) { "sb-orderprocessing-$resourceSuffix" } else { $ServiceBusNamespaceName }
$smokeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { "phase10-transport-$brokerSuffix-$(Get-Date -Format 'yyyyMMddHHmmss')" } else { $RunId }

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    Write-Host "Retrieving Service Bus connection string from auth rule 'phase10-transport'..."
    $ConnectionString = az servicebus namespace authorization-rule keys list `
        --resource-group $resourceGroup `
        --namespace-name $namespace `
        --name phase10-transport `
        --query primaryConnectionString `
        -o tsv
}

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    throw "Service Bus connection string could not be resolved for namespace '$namespace'."
}

$toolProject = Join-Path $PSScriptRoot '..\tools\Phase10.TransportSmoke\Phase10.TransportSmoke.csproj'
$arguments = @(
    'run',
    '--project', $toolProject,
    '--',
    '--environment', $Environment,
    '--namespace', $namespace,
    '--topic', "order-events-$brokerSuffix",
    '--inventory-subscription', "inventory-order-created-$brokerSuffix",
    '--notifications-subscription', "notifications-order-created-$brokerSuffix",
    '--dead-letter-topic', 'order-events-dlq',
    '--dead-letter-subscription', "dlq-replay-$brokerSuffix",
    '--connection-string', $ConnectionString,
    '--run-id', $smokeRunId
)

Write-Host "Running Phase 10 Azure transport smoke for '$Environment'..."
$output = & dotnet @arguments
$exitCode = $LASTEXITCODE

$output | ForEach-Object { Write-Output $_ }

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryDirectory = Split-Path -Parent $SummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $output | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

exit $exitCode
