#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$ArtifactDirectory
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath($RepositoryRoot)
if (-not $ArtifactDirectory) {
    $ArtifactDirectory = Join-Path $repo ('TestResults/AIGovernance/regression-' + [guid]::NewGuid().ToString('N'))
}
$artifact = [IO.Path]::GetFullPath($ArtifactDirectory)
$resultsRoot = [IO.Path]::GetFullPath((Join-Path $repo 'TestResults')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $artifact.StartsWith($resultsRoot, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
    throw 'Regression artifacts must remain under repository TestResults.'
}
[void][IO.Directory]::CreateDirectory((Join-Path $artifact 'logs'))
$baseline = Join-Path $artifact 'baseline'
[void][IO.Directory]::CreateDirectory($baseline)
$utf8 = [Text.UTF8Encoding]::new($false)
$results = [Collections.Generic.List[object]]::new()
$runError = $null
$expectedCount = 29
$validator = Join-Path $repo 'scripts/validate-ai-customization.ps1'

function Write-FixtureFile([string]$Fixture, [string]$RelativePath, [string]$Text) {
    $target = Join-Path $Fixture $RelativePath
    [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
    [IO.File]::WriteAllText($target, $Text, $utf8)
}
function Change-Fixture([string]$Fixture, [string]$Path, [string]$Old, [string]$New) {
    $text = [IO.File]::ReadAllText((Join-Path $Fixture $Path))
    if (-not $text.Contains($Old)) { throw "Fixture mutation did not match expected source: $Path" }
    Write-FixtureFile $Fixture $Path $text.Replace($Old, $New)
}

# Copy only reviewed guidance and public reference files, never local secrets or runtime data.
$sourceFiles = @('AGENTS.md','ARCHITECTURE.md','scripts/README.md','scripts/validate-ai-customization.ps1',
    'memories/repo/active-work.md','frontend/apps/web/package.json','automation/config/runtime-targets.json')
foreach ($directory in @('.github','docs')) {
    $sourceFiles += @(Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File -Filter '*.md' |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName) })
}
foreach ($relative in $sourceFiles | Sort-Object -Unique) {
    $source = Join-Path $repo $relative
    Write-FixtureFile $baseline $relative ([IO.File]::ReadAllText($source))
}

# Test provenance is synthetic, independent of the next real session's revision/status.
# The real handoff is validated separately by the owning validator/CI step.
$handoffPath = 'memories/repo/active-work.md'
$fixtureHandoff = [IO.File]::ReadAllText((Join-Path $baseline $handoffPath))
$fixtureFields = [ordered]@{
    'Review revision'='802bdfe'; 'Worktree state'='DIRTY'; 'Evidence status'='HISTORICAL'
    'Evidence revision'='UNKNOWN'; 'Evidence environment'='fixture-only'; 'Evidence scope'='structural-only'
    'Evidence reference'='TestResults/governance-fixture-evidence.json'
}
foreach ($field in $fixtureFields.Keys) {
    $pattern = '(?m)^- ' + [regex]::Escape($field) + ':[^\r\n]*'
    if ([regex]::Matches($fixtureHandoff, $pattern).Count -ne 1) { throw 'Fixture baseline needs exactly one provenance field per key.' }
    $fixtureHandoff = [regex]::Replace($fixtureHandoff, $pattern, ('- ' + $field + ': `' + $fixtureFields[$field] + '`'))
}
Write-FixtureFile $baseline $handoffPath $fixtureHandoff

function Test-Case {
    param([string]$Name, [scriptblock]$Mutate, [string]$ExpectedCode, [string]$SensitiveCanary)
    $fixture = Join-Path $artifact ('fixtures/' + $Name)
    [void][IO.Directory]::CreateDirectory((Split-Path $fixture -Parent))
    Copy-Item -LiteralPath $baseline -Destination $fixture -Recurse
    try {
        if ($Mutate) { & $Mutate $fixture }
    } catch {
        if ($Name -eq 'symlink-boundary' -and $_.Exception.Message -eq 'SYMLINK_UNAVAILABLE') {
            $results.Add([pscustomobject]@{ name=$Name; status='not-tested'; reason='Symbolic-link creation unavailable; no elevation attempted.' })
            Write-Output "NOT TESTED $Name"; return
        }
        throw
    }
    $output = (& pwsh -NoProfile -File $validator -RepositoryRoot $fixture 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    $expectedExit = if ($ExpectedCode) { 1 } else { 0 }
    $passed = $exitCode -eq $expectedExit -and (-not $ExpectedCode -or $output.Contains($ExpectedCode))
    if ($SensitiveCanary -and $output.Contains($SensitiveCanary)) { $passed = $false }
    $safeOutput = if ($SensitiveCanary) { $output.Replace($SensitiveCanary, '[REDACTED]') } else { $output }
    [IO.File]::WriteAllText((Join-Path $artifact "logs/$Name.log"), $safeOutput, $utf8)
    $status = if ($passed) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{name=$Name;status=$status;exitCode=$exitCode;expectedExit=$expectedExit;expectedDiagnostic=$ExpectedCode;log="logs/$Name.log"})
    Write-Output "$($status.ToUpperInvariant()) $Name"
}

try {
    Test-Case 'valid-historical-unavailable' {} ''
    Test-Case 'missing-shared-entry' { param($f) Move-Item -LiteralPath (Join-Path $f 'AGENTS.md') -Destination (Join-Path $f 'AGENTS.saved.md') } 'AI101'
    Test-Case 'oversized-shared-entry' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + (' ' * 6145)) } 'AI104'
    Test-Case 'oversized-copilot-entry' { param($f) Write-FixtureFile $f '.github/copilot-instructions.md' (([IO.File]::ReadAllText((Join-Path $f '.github/copilot-instructions.md'))) + (' ' * 6145)) } 'AI104'
    Test-Case 'oversized-handoff' { param($f) Write-FixtureFile $f 'memories/repo/active-work.md' (([IO.File]::ReadAllText((Join-Path $f 'memories/repo/active-work.md'))) + (' ' * 8193)) } 'AI104'
    Test-Case 'missing-client-route' { param($f) Change-Fixture $f '.github/copilot-instructions.md' 'prompts/README.md' 'prompts/MISSING.md' } 'AI105'
    Test-Case 'missing-heading-target' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[bad](docs/AI-OPERATING-MODEL.md#nonexistent-heading)") } 'AI105'
    Test-Case 'repository-traversal' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[bad](../outside.md)") } 'AI102'
    Test-Case 'encoded-traversal' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[bad](%2e%2e%2foutside.md)") } 'AI102'
    Test-Case 'windows-rooted-reference' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[bad](C:\outside.md)") } 'AI102'
    Test-Case 'unc-reference' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[bad](\\server\outside.md)") } 'AI102'
    Test-Case 'valid-backslash-reference' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n[ok](memories\repo\active-work.md)") } ''
    Test-Case 'duplicate-prompt-heading' { param($f) Write-FixtureFile $f '.github/prompts/README.md' (([IO.File]::ReadAllText((Join-Path $f '.github/prompts/README.md'))) + "`n### ``/XYDataLabs-day-start``") } 'AI106'
    Test-Case 'missing-canonical-prompt' { param($f) Change-Fixture $f '.github/prompts/README.md' '### `/XYDataLabs-day-start`' '### `/unlisted-day-start`' } 'AI106'
    Test-Case 'duplicate-agent-row' { param($f) Write-FixtureFile $f '.github/prompts/README.md' (([IO.File]::ReadAllText((Join-Path $f '.github/prompts/README.md'))) + "`n| Azure duplicate | ``.github/agents/azure-devops.agent.md`` | duplicate |") } 'AI106'
    Test-Case 'contradictory-skill-label' { param($f) Change-Fixture $f '.github/skills/README.md' '| CQRS Backend Implementation |' '| Azure Deployment Operations |' } 'AI107'
    Test-Case 'duplicate-skill-name' { param($f) Change-Fixture $f '.github/skills/cqrs-backend-implementation/SKILL.md' 'name: cqrs-backend-implementation' 'name: azure-deployment-operations' } 'AI106'
    Test-Case 'empty-frontmatter-description' { param($f) $path='.github/prompts/XYDataLabs-day-start.prompt.md'; $text=[IO.File]::ReadAllText((Join-Path $f $path)); Write-FixtureFile $f $path ([regex]::Replace($text,'(?m)^description:.*$','description: ""')) } 'AI112'
    Test-Case 'unconditional-git-directive' { param($f) Write-FixtureFile $f '.github/prompts/XYDataLabs-new-feature.prompt.md' (([IO.File]::ReadAllText((Join-Path $f '.github/prompts/XYDataLabs-new-feature.prompt.md'))) + "`ngit add -A`n") } 'AI110'
    Test-Case 'missing-evidence-section' { param($f) Change-Fixture $f 'AGENTS.md' '## Evidence And Limits' '## Unlisted Context' } 'AI110'
    Test-Case 'missing-evidence-field' { param($f) Change-Fixture $f 'memories/repo/active-work.md' '- Evidence status:' '- Unlisted evidence status:' } 'AI108'
    Test-Case 'malformed-evidence-revision' { param($f) Change-Fixture $f 'memories/repo/active-work.md' '- Evidence revision: `UNKNOWN`' '- Evidence revision: `invalid`' } 'AI108'
    Test-Case 'duplicate-evidence-field' { param($f) Write-FixtureFile $f 'memories/repo/active-work.md' (([IO.File]::ReadAllText((Join-Path $f 'memories/repo/active-work.md'))) + "`n- Evidence status: ``HISTORICAL``") } 'AI108'
    Test-Case 'unknown-current-pass' { param($f) Change-Fixture $f 'memories/repo/active-work.md' '- Evidence status: `HISTORICAL`' '- Evidence status: `CURRENT_PASS`' } 'AI109'
    Test-Case 'missing-current-pass-artifact' { param($f) Change-Fixture $f 'memories/repo/active-work.md' '- Evidence status: `HISTORICAL`' '- Evidence status: `CURRENT_PASS`'; Change-Fixture $f 'memories/repo/active-work.md' '- Evidence revision: `UNKNOWN`' '- Evidence revision: `802bdfe`'; Change-Fixture $f 'memories/repo/active-work.md' '- Worktree state: `DIRTY`' '- Worktree state: `CLEAN`' } 'AI109'
    Test-Case 'bound-current-metadata-structure-only' {
        param($f)
        Change-Fixture $f 'memories/repo/active-work.md' '- Evidence status: `HISTORICAL`' '- Evidence status: `CURRENT_PASS`'
        Change-Fixture $f 'memories/repo/active-work.md' '- Evidence revision: `UNKNOWN`' '- Evidence revision: `802bdfe`'
        Change-Fixture $f 'memories/repo/active-work.md' '- Worktree state: `DIRTY`' '- Worktree state: `CLEAN`'
        Change-Fixture $f 'memories/repo/active-work.md' '- Evidence reference: `TestResults/governance-fixture-evidence.json`' '- Evidence reference: `TestResults/structural-fixture.json`'
        Write-FixtureFile $f 'TestResults/structural-fixture.json' '{"synthetic":true,"runtimeCertification":false}'
    } ''
    Test-Case 'external-evidence-reference' { param($f) Change-Fixture $f 'memories/repo/active-work.md' '- Evidence reference: `TestResults/' '- Evidence reference: `C:/outside/' } 'AI108'
    $canary = 'ghp_' + ('Z' * 36)
    Test-Case 'sanitized-sensitive-diagnostic' { param($f) Write-FixtureFile $f 'AGENTS.md' (([IO.File]::ReadAllText((Join-Path $f 'AGENTS.md'))) + "`n$canary") } 'AI111' $canary
    Test-Case 'symlink-boundary' {
        param($f)
        $outside = Join-Path (Split-Path $f -Parent) 'owned-outside-reference'
        [void][IO.Directory]::CreateDirectory($outside)
        $link = Join-Path $f '.github/prompts/outside-link'
        try { [void](New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop) }
        catch {
            # Directory junctions are reparse points too and can be created on Windows
            # without the symlink privilege. Use one for the same boundary assertion.
            try { [void](New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop) }
            catch { throw 'SYMLINK_UNAVAILABLE' }
        }
    } 'AI103'
} catch {
    $runError = 'Regression runner aborted; inspect safe case logs and command exit status.'
    throw
} finally {
    $failed = @($results | Where-Object status -eq 'failed').Count
    $notTested = @($results | Where-Object status -eq 'not-tested').Count
    $status = if ($failed -or $runError -or $results.Count -ne $expectedCount) { 'failed' } elseif ($notTested) { 'partial' } else { 'passed' }
    [IO.File]::WriteAllText((Join-Path $artifact 'summary.json'), (@{status=$status;expectedCount=$expectedCount;actualCount=$results.Count;error=$runError;kind='structural-regression';runtimeAcceptance='not-tested';results=@($results)} | ConvertTo-Json -Depth 8), $utf8)
    Write-Output "Structural regression summary: $status; failed=$failed; not-tested=$notTested; artifacts=$artifact"
}
if ($failed -or $notTested -or $runError -or $results.Count -ne $expectedCount) { exit 1 }
# Expected-failure validator subprocesses leave LASTEXITCODE=1. Do not leak that
# value into a successful GitHub pwsh step after all required cases passed.
exit 0
