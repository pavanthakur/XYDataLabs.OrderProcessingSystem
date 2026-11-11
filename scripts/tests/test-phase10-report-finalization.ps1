#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hook = Join-Path $root 'scripts\run-phase10-docker-dev-e2e-hook.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($hook, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Hook syntax is invalid.' }
$tryNode = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })[-1]
$finalCode = $tryNode.Finally.Statements.Extent.Text -join [Environment]::NewLine
$terminal = @($ast.EndBlock.Statements)[-1].Extent.Text
$completionFunction = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-Phase10Completion'
}, $true)
. ([scriptblock]::Create($completionFunction.Extent.Text))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('phase10-finalization-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)

function pwsh { $global:LASTEXITCODE = 0; '{}' }
function Protect-Phase10Log { process { $_ } }
function Get-Phase10GitSnapshot { return @{ commit=('a' * 40); worktree='clean' } }
function Remove-Item {
    param([string]$LiteralPath, [switch]$Recurse, [switch]$Force)
    if ($script:failLockRemoval -and $LiteralPath -eq $acceptanceLockPath) { throw 'synthetic lock cleanup failure' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force
}
function Write-RunSummary {
    param([System.Collections.IDictionary]$Summary)
    if ($script:summaryFailures -gt 0) { $script:summaryFailures--; throw 'synthetic summary failure' }
    $Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runSummaryJsonPath
}
function Invoke-Phase10Preview {
    param([string]$Directory)
    if ($script:previewFailure) { throw 'synthetic reporter failure' }
    if (-not (Test-Path -LiteralPath (Join-Path $Directory 'acceptance-packet.json')) -or
        -not (Test-Path -LiteralPath $runSummaryJsonPath)) { throw 'Packet and summary must precede preview.' }
    $path = Join-Path $Directory 'phase10-preview.html'
    if ($script:oversizedPreview) { [IO.File]::WriteAllBytes($path, [byte[]]::new(2MB + 1)) }
    else { Set-Content -LiteralPath $path -Value 'preview' }
    Set-Content -LiteralPath (Join-Path $Directory 'index.html') -Value 'offline report'
    if (-not $script:missingCoverageSummary) {
        Set-Content -LiteralPath (Join-Path $Directory 'phase10-coverage-summary.json') -Value '{}'
    }
    $services = @('sql-server','redis','azurite','servicebus-sql','servicebus-emulator','keycloak-local','orders','payments','inventory','notifications','gateway','ui','functions')
    foreach ($point in @('before','after')) {
        if ($script:missingImageManifest -and $point -eq 'after') { continue }
        $images = @()
        for ($index = 0; $index -lt $services.Count; $index++) {
            $images += @{ project='xy-phase10'; service=$services[$index]; containerId=$index.ToString('x').PadLeft(12,'0');
                imageReference="$($services[$index]):dev"; imageId=('sha256:' + ($index + 1).ToString('x').PadLeft(64,'0')); repositoryDigests=@() }
        }
        @{ schema='phase10-docker-image-identities-v1'; runId=(Split-Path -Leaf $Directory); capturePoint=$point;
            candidate=@{ commit=('a' * 40); worktree='clean'; dirtyStatusSha256=$null }; buildLogsSha256=@{}; images=$images } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory "docker-image-identities-$point.json")
    }
}

try {
    $createRun = $ast.EndBlock.Statements | Where-Object {
        $_.Extent.Text -eq 'New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null'
    }
    if (@($createRun).Count -ne 1) { throw 'Run directory creation guard was not found.' }
    $runRoot = Join-Path $tempRoot 'existing-run'
    [void][IO.Directory]::CreateDirectory($runRoot)
    $marker = Join-Path $runRoot 'existing.txt'
    Set-Content -LiteralPath $marker -Value 'preserve'
    $rejected = $false
    try { & ([scriptblock]::Create($createRun.Extent.Text)) } catch { $rejected = $true }
    if (-not $rejected -or (Get-Content -LiteralPath $marker) -ne 'preserve') {
        throw 'Existing run directory was not rejected intact.'
    }
    Write-Host 'PASS existing-run-directory'
    foreach ($case in @(
        @{ name='success'; input='passed'; previewFailure=$false; expected='passed' },
        @{ name='partial'; input='partial'; previewFailure=$false; expected='partial' },
        @{ name='execution-failed'; input='failed'; previewFailure=$false; expected='failed' },
        @{ name='preview-failed'; input='passed'; previewFailure=$true; expected='failed' },
        @{ name='both-failed'; input='failed'; previewFailure=$true; expected='failed' },
        @{ name='summary-failed'; input='passed'; previewFailure=$false; expected='failed'; summaryFailures=1 },
        @{ name='malformed-child'; input='passed'; previewFailure=$false; expected='failed'; malformed=$true },
        @{ name='completion-failed'; input='passed'; previewFailure=$false; expected='failed'; existingMarker=$true },
        @{ name='cleanup-failed'; input='passed'; previewFailure=$false; expected='failed'; failLock=$true },
        @{ name='oversized-preview'; input='passed'; previewFailure=$false; expected='failed'; oversized=$true },
        @{ name='missing-coverage-summary'; input='passed'; previewFailure=$false; expected='failed'; missingCoverage=$true },
        @{ name='missing-image-manifest'; input='passed'; previewFailure=$false; expected='failed'; missingImage=$true }
    )) {
        $workspaceRoot = Join-Path $tempRoot $case.name
        $runRoot = Join-Path $workspaceRoot 'TestResults\run'
        [void][IO.Directory]::CreateDirectory($runRoot)
        $runSummaryJsonPath = Join-Path $runRoot 'run-summary.json'
        $runSummaryPath = Join-Path $runRoot 'run-summary.md'
        $latestFailurePointerPath = Join-Path $workspaceRoot 'TestResults\latest-failure.txt'
        $acceptanceLockPath = Join-Path $workspaceRoot 'TestResults\acceptance.lock'
        Set-Content -LiteralPath $acceptanceLockPath -Value 'owned'
        $acceptanceLockOwned = $true
        $runFailed = $false
        $storageReportScript = 'mock-storage'
        $script:previewFailure = $case.previewFailure
        $script:oversizedPreview = [bool]$case.oversized
        $script:missingCoverageSummary = [bool]$case.missingCoverage
        $script:missingImageManifest = [bool]$case.missingImage
        $script:failLockRemoval = [bool]$case.failLock
        $script:summaryFailures = if ($case.summaryFailures) { $case.summaryFailures } else { 0 }
        $runSummary = [ordered]@{
            runId='run'; runRoot=$runRoot; status=$case.input; startedUtc=[DateTime]::UtcNow.ToString('o')
            reusedExistingStack=$true; gitProvenance=@{ start=@{commit=('a' * 40);worktree='clean'}; finish=$null }
            error=$(if ($case.input -eq 'failed') {'original failure'} else {$null})
        }
        $completionPath = Join-Path $runRoot 'phase10-completion.json'
        if ($case.existingMarker) { Set-Content -LiteralPath $completionPath -Value 'invalid existing record' }
        $previousPhase10RunId = 'prior-id'
        $previousPhase10RunRoot = 'prior-root'
        $env:PHASE10_RUN_ID = 'current-id'
        $env:PHASE10_RUN_ROOT = 'current-root'
        if ($case.malformed) { Set-Content -LiteralPath (Join-Path $runRoot 'e2e-summary.json') -Value '{invalid' }
        $observed = $null
        try {
            try {
                if ($case.input -eq 'failed') { throw 'original failure' }
            } finally {
                & ([scriptblock]::Create($finalCode))
            }
            & ([scriptblock]::Create($terminal))
        } catch { $observed = $_.Exception.Message }
        $packetPath = Join-Path $runRoot 'acceptance-packet.json'
        $packet = if (Test-Path -LiteralPath $packetPath) { Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json } else { $null }
        $saved = Get-Content -LiteralPath $runSummaryJsonPath -Raw | ConvertFrom-Json
        $persistedExpected = if ($case.existingMarker -or $case.oversized -or $case.missingCoverage -or $case.missingImage) { 'passed' } else { $case.expected }
        if (($null -ne $packet -and $packet.status -ne $persistedExpected) -or $saved.status -ne $persistedExpected) { throw "$($case.name): status was not preserved." }
        if (((Test-Path -LiteralPath $acceptanceLockPath) -ne [bool]$case.failLock) -or $env:PHASE10_RUN_ID -ne 'prior-id' -or $env:PHASE10_RUN_ROOT -ne 'prior-root') {
            throw "$($case.name): cleanup did not complete."
        }
        if ($case.input -eq 'failed' -and $observed -ne 'original failure') { throw "$($case.name): original failure was masked." }
        if ($case.expected -eq 'failed' -and -not $observed) { throw "$($case.name): failure did not propagate." }
        if ($case.previewFailure -and ($packet.reportPreview -ne 'failed' -or -not (Test-Path -LiteralPath $latestFailurePointerPath))) {
            throw "$($case.name): preview failure evidence is missing."
        }
        if ($case.expected -ne 'failed' -and (-not (Test-Path -LiteralPath (Join-Path $runRoot 'phase10-preview.html')) -or
            -not (Test-Path -LiteralPath (Join-Path $runRoot 'index.html')))) {
            throw "$($case.name): preview missing."
        }
        if ($case.name -in @('success', 'partial', 'execution-failed')) {
            $completion = Get-Content -LiteralPath $completionPath -Raw | ConvertFrom-Json
            if ($completion.schema -ne 'phase10-completion-v4' -or $completion.runId -ne 'run' -or $completion.status -ne $case.expected) {
                throw "$($case.name): completion record is invalid."
            }
            foreach ($name in @('acceptance-packet.json', 'run-summary.json', 'phase10-preview.html', 'phase10-coverage-summary.json', 'index.html',
                'docker-image-identities-before.json', 'docker-image-identities-after.json')) {
                if ($completion.sha256.$name -ne (Get-FileHash -LiteralPath (Join-Path $runRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()) {
                    throw "$($case.name): completion hash mismatch."
                }
            }
            Push-Location (Join-Path $root 'automation')
            try {
                & node --import tsx 'src\cli\verify-phase10-completion.ts' $runRoot
                $expectedExit = if ($case.expected -eq 'passed') { 0 } elseif ($case.expected -eq 'failed') { 1 } else { 2 }
                if ($LASTEXITCODE -ne $expectedExit) { throw "$($case.name): verifier returned $LASTEXITCODE." }
            } finally { Pop-Location }
        } elseif ($case.existingMarker) {
            if ((Get-Content -LiteralPath $completionPath -Raw).Trim() -ne 'invalid existing record') { throw 'Existing record overwritten.' }
        } elseif (Test-Path -LiteralPath $completionPath) { throw "$($case.name): incomplete finalization published a record." }
        Write-Host "PASS $($case.name)"
    }
    $script:missingImageManifest = $false
    $workspaceRoot = $root
    $actualRoot = Join-Path $tempRoot 'actual-preview'
    [void][IO.Directory]::CreateDirectory($actualRoot)
    $previewFunction = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Phase10Preview'
    }, $true)
    . ([scriptblock]::Create($previewFunction.Extent.Text))
    Invoke-Phase10Preview -Directory $actualRoot
    $previewPath = Join-Path $actualRoot 'phase10-preview.html'
    $original = Get-Content -LiteralPath $previewPath -Raw
    if ($original -notmatch 'Overall: BLOCKED') { throw 'Actual preview was not generated as blocked.' }
    $failed = $false
    try { Invoke-Phase10Preview -Directory $actualRoot } catch { $failed = $true }
    if (-not $failed -or (Get-Content -LiteralPath $previewPath -Raw) -ne $original) {
        throw 'Existing preview was overwritten or did not fail.'
    }
    Write-Host 'PASS actual-preview-and-no-overwrite'
    function npm { $global:LASTEXITCODE = 1; 'simulated missing dependency' }
    $missingRoot = Join-Path $tempRoot 'missing-dependency'
    [void][IO.Directory]::CreateDirectory($missingRoot)
    $failed = $false
    try { Invoke-Phase10Preview -Directory $missingRoot } catch { $failed = $true }
    if (-not $failed -or (Test-Path -LiteralPath (Join-Path $missingRoot 'phase10-preview.html'))) {
        throw 'Missing dependency did not fail preview generation.'
    }
    Write-Host 'PASS missing-dependency'
    $snapshotFunction = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-Phase10GitSnapshot'
    }, $true)
    . ([scriptblock]::Create($snapshotFunction.Extent.Text))
    $snapshot = Get-Phase10GitSnapshot -Directory $root
    if ($snapshot.commit -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$' -or $snapshot.worktree -notin @('clean', 'dirty')) {
        throw 'Git snapshot failed for the repository.'
    }
    $missing = Get-Phase10GitSnapshot -Directory (Join-Path $tempRoot 'nonexistent')
    if ($null -ne $missing.commit -or $missing.worktree -ne 'unknown') { throw 'Unavailable Git evidence did not remain unknown.' }
    Write-Host 'PASS git-provenance'
    $foundationPath = Join-Path $root 'scripts\run-phase10-foundation-tests.ps1'
    $foundationAst = [Management.Automation.Language.Parser]::ParseFile($foundationPath, [ref]$null, [ref]$null)
    $foundationTry = @($foundationAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })[-1]
    $foundationFinal = $foundationTry.Finally.Statements.Extent.Text -join [Environment]::NewLine
    foreach ($completed in @($true, $false)) {
        $artifact = Join-Path $tempRoot "foundation-$completed"
        [void][IO.Directory]::CreateDirectory($artifact)
        $results = @()
        $runnerCompleted = $completed
        Push-Location $artifact
        & ([scriptblock]::Create($foundationFinal))
        $summary = Get-Content -LiteralPath (Join-Path $artifact 'summary.json') -Raw | ConvertFrom-Json
        $expectedStatus = if ($completed) { 'passed' } else { 'failed' }
        if ($summary.status -ne $expectedStatus) { throw 'Incomplete foundation runner reported success.' }
    }
    Write-Host 'PASS foundation-interruption-summary'
} finally {
    $script:failLockRemoval = $false
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
