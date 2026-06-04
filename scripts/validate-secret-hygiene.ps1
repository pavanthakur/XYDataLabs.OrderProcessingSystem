[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$extensions = '*.cs', '*.json', '*.yml', '*.yaml', '*.ps1', '*.bicep'
$excludedPathPattern = '\\(\.artifacts|bin|node_modules|obj|publish|dist|coverage|reports|outputs)\\'
$fileNameExclusionPattern = '\.(example|template)(\.[^\\]+)?$'
$patterns = @(
    '(?i)\bpassword\s*=\s*"[^$<{\"]',
    '(?i)\bsecret\s*[:=]\s*"[^$<{\"]',
    '(?i)\bprivatekey\s*[:=]\s*"[^$<{\"]',
    '(?i)\bconnectionstring\b.*password='
)
$allowedLinePatterns = @(
    '::add-mask::',
    'az\s+keyvault\s+secret\s+show',
    'Password=\$[A-Za-z_]',
    'Password=\$\(',
    'Password=\$\{',
    'sql-admin-password',
    'OPENPAY_PRIVATE_KEY',
    'RAZORPAY_PRIVATE_KEY',
    'APP_PRIVATE_KEY'
)

$files = Get-ChildItem -Path $repoRoot -Recurse -File -Include $extensions |
    Where-Object {
        $_.FullName -notmatch $excludedPathPattern -and
        $_.FullName -notmatch $fileNameExclusionPattern
    }

$hits = foreach ($file in $files) {
    Select-String -Path $file.FullName -Pattern ($patterns -join '|') -CaseSensitive:$false
}

$filteredHits = $hits | Where-Object {
    $line = $_.Line
    $path = $_.Path

    if ($path -match '\\tests\\' -and $line -match '\bPrivateKey\s*=') {
        return $false
    }

    if ($path -match '\\tests\\' -and $line -match 'secret\s*=\s*"razorpay-test-secret"') {
        return $false
    }

    foreach ($allowedPattern in $allowedLinePatterns) {
        if ($line -match $allowedPattern) {
            return $false
        }
    }

    return $true
}

if ($filteredHits) {
    $filteredHits |
        Select-Object Path, LineNumber, Line |
        Format-Table -AutoSize

    Write-Host "SECRET SCAN: $($filteredHits.Count) potential hit(s) - review each" -ForegroundColor Red
    exit 1
}

Write-Host 'SECRET SCAN: clean' -ForegroundColor Green
