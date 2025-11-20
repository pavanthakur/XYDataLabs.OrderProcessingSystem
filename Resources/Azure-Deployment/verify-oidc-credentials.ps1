<#!
.SYNOPSIS
    Verifies GitHub OIDC federated credentials exist for expected environments.
.DESCRIPTION
    Checks Azure AD application (service principal) federated identity credentials for dev, staging, main (prod) or a supplied list.
    Useful when manual changes or bootstrap script failures suspected.
.PARAMETER AppObjectId
    The Azure AD application object Id hosting federated credentials.
.PARAMETER ExpectedEnvironments
    Array of environment names expected (default: dev, staging, main).
.EXAMPLE
    ./verify-oidc-credentials.ps1 -AppObjectId 00000000-0000-0000-0000-000000000000
.NOTES
    Requires Azure CLI (az) logged in and Directory.Read.All / Application.Read permissions.
!#>
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)][string]$AppObjectId,
    [string[]]$ExpectedEnvironments = @('dev','staging','main')
)
$ErrorActionPreference = 'Stop'

Write-Host "Querying federated credentials for AppObjectId: $AppObjectId" -ForegroundColor Cyan
$raw = az ad app federated-credential list --id $AppObjectId --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to retrieve federated credentials. Check permissions." }
$creds = $raw | ConvertFrom-Json
if (!$creds) { Write-Error "No credentials returned or parse failure." }

# Extract environments from subject (repo) and audience issuer claims when using GitHub OIDC
# Typically credential.name or subject patterns used: repo:<org>/<repo>:environment:<env>
$mapped = @()
foreach ($c in $creds) {
    $subject = $c.subject
    $name = $c.name
    $env = $null
    if ($subject -match 'environment:([^:]+)$') { $env = $Matches[1] }
    elseif ($name -match 'env-(.+)$') { $env = $Matches[1] }
    else { $env = 'unknown' }
    $mapped += [PSCustomObject]@{ Name=$name; Environment=$env; Subject=$subject; Issuer=$c.issuer }
}

Write-Host "\nDiscovered Credentials:" -ForegroundColor White
$mapped | Sort-Object Environment | Format-Table Name,Environment,Issuer -AutoSize

$missing = @()
foreach ($e in $ExpectedEnvironments) {
    if (-not ($mapped.Environment -contains $e)) { $missing += $e }
}

if ($missing.Count -gt 0) {
    Write-Host "\nMissing federated credentials for: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Suggested remediation: run setup-github-oidc.ps1 or manually add via Azure Portal -> App Registrations -> (App) -> Federated Credentials." -ForegroundColor Yellow
    exit 2
}
Write-Host "\nAll expected environments present." -ForegroundColor Green
exit 0
