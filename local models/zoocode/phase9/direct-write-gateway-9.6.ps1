param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile
)

if (-not (Test-Path $TargetFile)) {
    throw "Target file not found: $TargetFile"
}

$content = Get-Content -Raw $TargetFile
if ($content -notmatch 'runtime-configuration') {
    $content = $content -replace 'app\.MapGet\("/", \(\) => Results\.Ok\(new \{', 'app.MapGet("/api/v1/info/runtime-configuration", () => Results.Ok(new {'
    $content = $content -replace '"status = "healthy",', '"status = "healthy",`r`n    activeTenantCode = builder.Configuration["Gateway:ActiveTenantCode"] ?? "TenantA",'
}

Set-Content -LiteralPath $TargetFile -Value $content -Encoding UTF8
Write-Host "Updated $TargetFile"
