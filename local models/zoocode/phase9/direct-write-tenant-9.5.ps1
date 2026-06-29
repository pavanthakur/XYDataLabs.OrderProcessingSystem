param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile
)

$templateFile = Join-Path $PSScriptRoot '..\..\..\templates\xy-saas\XYDataLabs.OrderProcessingSystem.Domain\Entities\Tenant.cs'

if (-not (Test-Path $templateFile)) {
    throw "Template file not found: $templateFile"
}
if (-not (Test-Path $TargetFile)) {
    throw "Target file not found: $TargetFile"
}

Set-Content -LiteralPath $TargetFile -Value (Get-Content -Raw $templateFile) -Encoding UTF8
Write-Host "Restored $TargetFile from template"
