param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile
)

$templateFile = Join-Path $PSScriptRoot '..\..\..\templates\xy-saas\XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs'

if (-not (Test-Path $templateFile)) {
    throw "Template file not found: $templateFile"
}
if (-not (Test-Path $TargetFile)) {
    throw "Target file not found: $TargetFile"
}

$content = Get-Content -Raw $templateFile
Set-Content -LiteralPath $TargetFile -Value $content -Encoding UTF8
Write-Host "Restored $TargetFile from template"
