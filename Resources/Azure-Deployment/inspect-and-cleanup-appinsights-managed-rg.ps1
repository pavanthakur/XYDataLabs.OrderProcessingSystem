param(
    [Parameter(Mandatory = $true)] [string] $ManagedResourceGroupName,
    [Parameter(Mandatory = $true)] [string] $AppInsightsResourceGroup,
    [Parameter(Mandatory = $true)] [string] $AppInsightsName,
    [Parameter(Mandatory = $false)] [switch] $MigrateToDedicatedWorkspace,
    [Parameter(Mandatory = $false)] [string] $LogAnalyticsWorkspaceName = "",
    [Parameter(Mandatory = $false)] [string] $Location = "centralindia",
    [Parameter(Mandatory = $false)] [switch] $DeleteManagedGroup
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Err($msg) { Write-Host $msg -ForegroundColor Red }

Write-Info "Inspecting managed resource group '$ManagedResourceGroupName'..."
$rg = az group show -n $ManagedResourceGroupName --only-show-errors | ConvertFrom-Json
if (-not $rg) { Write-Err "Resource group '$ManagedResourceGroupName' not found."; exit 1 }

$managedBy = az group show -n $ManagedResourceGroupName --query managedBy -o tsv --only-show-errors
Write-Info "ManagedBy: $managedBy"

Write-Info "Listing resources in '$ManagedResourceGroupName'..."
$resources = az resource list -g $ManagedResourceGroupName --query "[].{name:name,type:type,location:location,kind:kind}" -o json --only-show-errors | ConvertFrom-Json
$resources | ForEach-Object { Write-Host (" - {0} [{1}]" -f $_.name, $_.type) }

Write-Info "Getting Application Insights '$AppInsightsName' in '$AppInsightsResourceGroup'..."
$ai = az monitor app-insights component show -g $AppInsightsResourceGroup -n $AppInsightsName --only-show-errors | ConvertFrom-Json
if (-not $ai) { Write-Err "Application Insights '$AppInsightsName' not found in '$AppInsightsResourceGroup'."; exit 1 }

$aiWorkspaceId = az monitor app-insights component show -g $AppInsightsResourceGroup -n $AppInsightsName --query workspaceResourceId -o tsv --only-show-errors
Write-Info "Current linked workspace: $aiWorkspaceId"

if ($MigrateToDedicatedWorkspace) {
    if (-not $LogAnalyticsWorkspaceName -or $LogAnalyticsWorkspaceName.Trim().Length -eq 0) {
        Write-Err "-MigrateToDedicatedWorkspace requires -LogAnalyticsWorkspaceName."
        exit 1
    }

    Write-Info "Ensuring Log Analytics workspace '$LogAnalyticsWorkspaceName' in RG '$AppInsightsResourceGroup' (location: $Location)..."
    az monitor log-analytics workspace show -g $AppInsightsResourceGroup -n $LogAnalyticsWorkspaceName --only-show-errors 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating workspace..."
        az monitor log-analytics workspace create -g $AppInsightsResourceGroup -n $LogAnalyticsWorkspaceName -l $Location --only-show-errors 1>$null
    } else {
        Write-Info "Workspace already exists."
    }

    $workspaceId = az monitor log-analytics workspace show -g $AppInsightsResourceGroup -n $LogAnalyticsWorkspaceName --query id -o tsv --only-show-errors
    Write-Info "Linking App Insights to workspace: $workspaceId"
    az monitor app-insights component update -g $AppInsightsResourceGroup -n $AppInsightsName --workspace $workspaceId --only-show-errors 1>$null
    Write-Ok "App Insights now linked to dedicated workspace."
}

if ($DeleteManagedGroup) {
    Write-Warn "About to delete managed resource group '$ManagedResourceGroupName'. This is safe only after App Insights is linked to a different workspace and nothing else depends on it."
    Write-Warn "Press Ctrl+C to abort within 10 seconds..."
    Start-Sleep -Seconds 10

    az group delete -n $ManagedResourceGroupName --yes --no-wait --only-show-errors
    Write-Ok "Deletion requested for '$ManagedResourceGroupName'."
}

Write-Ok "Done."