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

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-orderprocessing-$envSuffix" } else { $ResourceGroupName }
$namespace = if ([string]::IsNullOrWhiteSpace($ServiceBusNamespaceName)) { "sb-orderprocessing-$envSuffix" } else { $ServiceBusNamespaceName }
$smokeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { "phase10-transport-$envSuffix-$(Get-Date -Format 'yyyyMMddHHmmss')" } else { $RunId }

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
    '--topic', "order-events-$envSuffix",
    '--inventory-subscription', "inventory-order-created-$envSuffix",
    '--notifications-subscription', "notifications-order-created-$envSuffix",
    '--dead-letter-topic', 'order-events-dlq',
    '--dead-letter-subscription', "dlq-replay-$envSuffix",
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
