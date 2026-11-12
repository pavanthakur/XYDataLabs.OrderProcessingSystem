# Synthetic regression fixture only; no real test artifacts or secrets are read.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hosted-trx-sanitize-" + [guid]::NewGuid().ToString('N'))
$trxRoot = Join-Path $tempRoot 'trx'
$fixture = Join-Path $trxRoot 'failure.trx'
New-Item -ItemType Directory -Path $trxRoot -Force | Out-Null

try {
    @'
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results><UnitTestResult testName="SyntheticFailure" outcome="Failed">
    <Output><ErrorInfo><Message>password=synthetic-secret</Message><StackTrace>stack-password=synthetic-secret</StackTrace></ErrorInfo><StdOut>token=synthetic-secret</StdOut><Attachments><Attachment><Uri>private-path</Uri></Attachment></Attachments></Output>
  </UnitTestResult></Results>
</TestRun>
'@ | Set-Content -LiteralPath $fixture -Encoding utf8

    & (Join-Path $repoRoot 'scripts/sanitize-hosted-trx.ps1') -ResultsRoot $trxRoot
    $sanitized = Get-Content -LiteralPath $fixture -Raw
    if ($sanitized -match 'synthetic-secret|private-path|<StackTrace|<StdOut|<Attachments') {
        throw 'Sensitive fixture content or free-form output remains in sanitized TRX.'
    }
    if ($sanitized -notmatch 'SyntheticFailure' -or $sanitized -notmatch 'Failure details omitted from artifact') {
        throw 'Sanitization removed test identity or failed-result evidence.'
    }
    Write-Host 'PASS synthetic TRX is sanitized while test identity and failure status remain.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
