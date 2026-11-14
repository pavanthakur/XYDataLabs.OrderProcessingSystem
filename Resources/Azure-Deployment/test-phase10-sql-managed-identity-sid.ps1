$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot 'setup-phase10-sql-managed-identities.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "SQL managed identity setup script has PowerShell syntax errors: $($parseErrors.Message -join '; ')"
}

$functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Convert-GuidToSqlSidHex'
    }, $true)
if ($null -eq $functionAst) {
    throw 'Could not locate Convert-GuidToSqlSidHex in the SQL managed identity setup script.'
}

. ([scriptblock]::Create($functionAst.Extent.Text))
$actual = Convert-GuidToSqlSidHex -GuidText 'b75e2d83-b793-4f7b-9598-06dc06b616f5'
$expected = '0x832D5EB793B77B4F959806DC06B616F5'
if ($actual -ne $expected) {
    throw "SQL managed identity SID byte order mismatch. Expected '$expected'; got '$actual'."
}

$source = Get-Content -LiteralPath $scriptPath -Raw
if ($source -notmatch 'CREATE USER \[\$DisplayName\] WITH SID = \$managedIdentitySid, TYPE = E') {
    throw 'SQL managed identity setup must create external users with the explicit SQL-compatible SID.'
}
if ($source -notmatch 'Refusing to replace mismatched external user that owns database objects or schemas') {
    throw 'SQL managed identity repair must refuse to drop a mismatched user that owns objects or schemas.'
}
if ($source -notmatch 'Managed identity database principal SID verification failed' -or
    $source -notmatch 'Managed identity database role verification failed') {
    throw 'SQL managed identity setup must verify the resulting SID and least-privilege roles.'
}

Write-Host 'Phase 10 SQL managed identity SID regression passed.' -ForegroundColor Green
