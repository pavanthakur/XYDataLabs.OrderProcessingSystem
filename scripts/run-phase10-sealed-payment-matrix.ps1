#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('deterministic','sandbox-positive','sandbox-negative')][string]$Matrix,
    [Parameter(Mandatory)][string]$ExpectedImageManifest,
    [switch]$ApproveExecution
)
$ErrorActionPreference = 'Stop'
if (-not $ApproveExecution) { throw 'Explicit execution approval is required for the selected matrix.' }
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'phase10-docker-image-evidence.ps1')
Assert-Phase10ComposeProject
Assert-Phase10PortOwnership -Ports @(5080, 5022, (Get-Phase10SqlHostPort))
$root = Split-Path -Parent $PSScriptRoot
$results = Join-Path $root 'TestResults'
foreach ($name in @('phase10-docker-acceptance.lock','local-payment-test-state.lock')) {
    if (Test-Path -LiteralPath (Join-Path $results $name)) { throw 'An active acceptance or payment recovery lock exists.' }
}
if (@(Get-ChildItem -LiteralPath $results -Filter 'integration-active-*.lock' -File -ErrorAction SilentlyContinue).Count) {
    throw 'An integration run is active.'
}
$expectedItem = Get-Item -LiteralPath $ExpectedImageManifest -Force
if ($expectedItem.PSIsContainer -or ($expectedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $expectedItem.Length -gt 2MB) {
    throw 'Expected image manifest is not a bounded regular file.'
}
$expected = Get-Content -LiteralPath $expectedItem.FullName -Raw | ConvertFrom-Json
$runId = 'phase10-payment-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff')
$runRoot = Join-Path $results "Phase10/sealed-payments/$runId"
$null = New-Item -ItemType Directory -Path $runRoot
$acceptanceLock = Join-Path $results 'phase10-docker-acceptance.lock'
$lockStream = [IO.File]::Open($acceptanceLock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$lockBytes = [Text.UTF8Encoding]::new($false).GetBytes([IO.Path]::GetFullPath($runRoot))
$lockStream.Write($lockBytes, 0, $lockBytes.Length)
$lockStream.Flush($true)
$sealedRun = $false
$paymentStarted = $false
$restorationVerified = $false
try {
$reportRoot = Join-Path $runRoot 'payments'
$imageArgs = @{
    RunId = $runId; WorkspaceRoot = $root; ArtifactRoot = $runRoot
    ComposeFile = Join-Path $root 'compose/docker-compose.phase10.yml'
    EnvExampleFile = Join-Path $root 'Resources/Docker/.env.local.example'
    EnvFile = Join-Path $root 'Resources/Docker/.env.local'
}
$before = Get-Phase10DockerImageManifest @imageArgs -CapturePoint before -OutputPath (Join-Path $runRoot 'docker-image-identities-before.json')
Assert-Phase10DockerImageManifestMatches -Expected $expected -Actual $before
$seedScript = Join-Path $PSScriptRoot 'test-phase10-local-seed-contract.ps1'
& pwsh -NoProfile -File $seedScript -OutputPath (Join-Path $runRoot 'seed-contract.json')
if ($LASTEXITCODE -ne 0) { throw 'Payment baseline is not safe to run.' }
$previousRoot = $env:PHASE10_PAYMENT_REPORT_ROOT
$mode = if ($Matrix -eq 'deterministic') { 'deterministic' } else { 'sandbox' }
$childArguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'run-local-payment-tests.ps1'), '-Mode', $mode, '-AcceptanceProfile', 'baseline')
if ($Matrix -eq 'sandbox-negative') { $childArguments += '-Negative' }
$runExit = 1
$status = 'failed'
try {
    $env:PHASE10_PAYMENT_REPORT_ROOT = $reportRoot
    $paymentStarted = $true
    & pwsh @childArguments
    $runExit = $LASTEXITCODE
    if ($runExit -eq 0) { $status = 'passed' }
}
finally {
    $env:PHASE10_PAYMENT_REPORT_ROOT = $previousRoot
    if (Test-Path -LiteralPath (Join-Path $results 'local-payment-test-state.lock')) {
        $status = 'failed'
    }
    @{ schema = 'phase10-sealed-payment-run-v1'; runId = $runId; matrix = $Matrix; status = $status; rawExitCode = $runExit } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'payment-run.json')
}
& pwsh -NoProfile -File $seedScript -OutputPath (Join-Path $runRoot 'restoration-contract.json')
if ($LASTEXITCODE -ne 0) { throw 'Payment restoration baseline did not pass.' }
$beforeContract = Get-Content -LiteralPath (Join-Path $runRoot 'seed-contract.json') -Raw | ConvertFrom-Json
$afterContract = Get-Content -LiteralPath (Join-Path $runRoot 'restoration-contract.json') -Raw | ConvertFrom-Json
$beforeProjection = [ordered]@{ scope=$beforeContract.scope; status=$beforeContract.status; activeTenantCount=$beforeContract.activeTenantCount; supportedProviders=@($beforeContract.supportedProviders); tenants=@($beforeContract.tenants) }
$afterProjection = [ordered]@{ scope=$afterContract.scope; status=$afterContract.status; activeTenantCount=$afterContract.activeTenantCount; supportedProviders=@($afterContract.supportedProviders); tenants=@($afterContract.tenants) }
$configurationRestored = (ConvertTo-Json -InputObject $beforeProjection -Depth 12 -Compress) -ceq (ConvertTo-Json -InputObject $afterProjection -Depth 12 -Compress)
if (-not $configurationRestored) {
    $status = 'failed'
}
if ($configurationRestored -and $runExit -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $results 'local-payment-test-state.lock'))) { $restorationVerified = $true }
$after = Get-Phase10DockerImageManifest @imageArgs -CapturePoint after -OutputPath (Join-Path $runRoot 'docker-image-identities-after.json')
Assert-Phase10DockerImageManifestMatches -Expected $before -Actual $after

$hashes = [ordered]@{}
$allowed = @('payment-run.json','seed-contract.json','restoration-contract.json','docker-image-identities-before.json',
    'docker-image-identities-after.json','summary.json','acceptance-validated-rows.json','provider-dependencies.json',
    'case-ledger.json','provider-confirmation.json','positive-sql-proof.json','negative-sql-proof.json')
function Add-PaymentEvidenceTree([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
    $directoryItem = Get-Item -LiteralPath $Directory -Force
    if ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Evidence directory cannot be a reparse point.' }
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Evidence cannot contain reparse points.' }
        if ($item.PSIsContainer) { Add-PaymentEvidenceTree $item.FullName; continue }
        if ($Directory -ne $runRoot -and $item.Name -notin $allowed -and $item.Name -notmatch '^[a-z0-9_-]+-verification-report\.json$') { continue }
        if ($item.Extension -ne '.json') { continue }
        if ($item.Length -gt 2MB -or $hashes.Count -ge 1000) { throw 'Evidence exceeds the standalone seal limits.' }
        $relative = [IO.Path]::GetRelativePath($runRoot, $item.FullName).Replace('\','/')
        $hashes[$relative] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
Add-PaymentEvidenceTree $runRoot
$seal = @{ schema = 'phase10-payment-evidence-v1'; runId = $runId; sha256 = $hashes } | ConvertTo-Json -Depth 4
$stream = [IO.File]::Open((Join-Path $runRoot 'payment-evidence-seal.json'), [IO.FileMode]::CreateNew)
try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($seal)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
} finally { $stream.Dispose() }
Write-Host "Sealed payment evidence: $runRoot"
$sealedRun = $true
if ($status -ne 'passed') { exit 1 }
} finally {
    $lockStream.Dispose()
    if (($sealedRun -and $restorationVerified) -or -not $paymentStarted) {
      if ((Test-Path -LiteralPath $acceptanceLock -PathType Leaf) -and
        (Get-Content -LiteralPath $acceptanceLock -Raw).Trim() -eq [IO.Path]::GetFullPath($runRoot)) {
          Remove-Item -LiteralPath $acceptanceLock -Force
      }
    }
}
