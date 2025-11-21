<#
.SYNOPSIS
  Verify existence and basic configuration of an Azure AD app used for GitHub OIDC.
.DESCRIPTION
  Confirms the Azure AD app exists and that federated credentials appear configured.
  Exit codes:
    0 = pass (app found and basic checks OK)
    1 = error (app not found or API error)
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$AppObjectId
)

function Show-Help { Write-Host "Usage: verify-oidc-credentials.ps1 -AppObjectId <appObjectId>" }

try {
    $az = (Get-Command az -ErrorAction SilentlyContinue)
    if (-not $az) {
        Write-Host "az CLI not found in runner; unable to verify OIDC app via az. Fail-safe: exit 1" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Checking Azure AD app object id: $AppObjectId" -ForegroundColor Cyan
    $app = az ad app show --id $AppObjectId -o json 2>$null | ConvertFrom-Json
    if (-not $app) {
        Write-Host "Azure AD app with id $AppObjectId not found" -ForegroundColor Red
        exit 1
    }

    Write-Host "Found Azure AD app: $($app.displayName)" -ForegroundColor Green

    # Try listing federated credentials (may require permissions)
    $creds = az rest --method get --uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId/federatedIdentityCredentials" -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $creds) {
        Write-Host "Could not retrieve federated credentials (check permissions)." -ForegroundColor Yellow
        # Treat as warning
        exit 1
    }

    Write-Host "Federated credentials retrieved" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error running verify-oidc-credentials: $_" -ForegroundColor Red
    exit 1
}
