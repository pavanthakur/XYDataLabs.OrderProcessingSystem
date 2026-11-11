# Sanitized discovery/TRX reconciliation helpers for Phase 10 .NET suites.
# Raw test names are held only in memory and are never written to evidence.
#Requires -Version 7.0

# dotnet emits UTF-8; a legacy console code page would corrupt non-ASCII test names and break reconciliation.
function Invoke-Phase10Utf8Native {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Command)
    $previous = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { $previous = $null }
    try { & $Command }
    finally { if ($null -ne $previous) { [Console]::OutputEncoding = $previous } }
}

function Get-Phase10DiscoveredDotnetTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestProject,
        [string]$Filter
    )
    $arguments = @('test', $TestProject, '--list-tests', '--verbosity', 'quiet')
    if (-not [string]::IsNullOrWhiteSpace($Filter)) { $arguments += @('--filter', $Filter) }
    $output = @(Invoke-Phase10Utf8Native { & dotnet @arguments 2>&1 })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw 'Current-candidate .NET test discovery failed; details omitted.' }
    $lines = @($output | ForEach-Object { [string]$_ })
    $marker = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*The following Tests are available:') { $marker = $index; break }
    }
    if ($marker -lt 0) { throw 'Current-candidate .NET test discovery output was incomplete.' }
    $names = [Collections.Generic.List[string]]::new()
    $started = $false
    foreach ($line in ($lines | Select-Object -Skip ($marker + 1))) {
        if ([string]::IsNullOrWhiteSpace($line)) { if ($started) { break }; continue }
        if ($line -match '^\s{4}(\S.*)$') { $started = $true; $names.Add($Matches[1].Trim()); continue }
        if ($started) { break }
    }
    if ($names.Count -eq 0 -or @($names | Select-Object -Unique).Count -ne $names.Count) {
        throw 'Current-candidate .NET test discovery returned no tests or duplicate identities.'
    }
    return ,$names.ToArray()
}

function Write-Phase10DiscoveredDotnetResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SuiteId,
        [Parameter(Mandatory)][string[]]$DiscoveredNames,
        [Parameter(Mandatory)][string]$AssemblyPath,
        [Parameter(Mandatory)][string]$AssemblyHashBefore,
        [Parameter(Mandatory)][string]$TrxPath,
        [Parameter(Mandatory)][int]$RunnerExitCode,
        [Parameter(Mandatory)][string]$StartedUtc,
        [Parameter(Mandatory)][string]$FinishedUtc,
        [Parameter(Mandatory)][string]$OutputPath
    )
    if ($SuiteId -notmatch '^(Domain|Application|API|Gateway|Architecture|Integration)$') { throw 'Unsupported .NET suite identifier.' }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($TrxPath, $settings)
    $actual = [Collections.Generic.List[object]]::new()
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        $ns = [Xml.XmlNamespaceManager]::new($document.NameTable)
        $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
        foreach ($item in $document.SelectNodes('//t:UnitTestResult', $ns)) {
            $name = $item.GetAttribute('testName')
            $outcome = $item.GetAttribute('outcome')
            if ([string]::IsNullOrWhiteSpace($name)) { throw 'TRX result was missing a test identity.' }
            $status = switch -Regex ($outcome) {
                '^Passed$' { 'passed'; break }
                '^Failed$|^Error$|^Timeout$|^Aborted$' { 'failed'; break }
                '^NotExecuted$|^Skipped$' { 'skipped'; break }
                default { 'unavailable' }
            }
            $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($name))).ToLowerInvariant()
            $actual.Add(@{ id = "${SuiteId}:$hash"; status = $status })
        }
    } finally { $reader.Dispose() }
    $expectedIds = @($DiscoveredNames | ForEach-Object {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_))).ToLowerInvariant()
        "${SuiteId}:$hash"
    })
    $actualIds = @($actual | ForEach-Object { $_.id })
    $duplicates = @($actualIds | Group-Object | Where-Object Count -gt 1)
    $missing = @($expectedIds | Where-Object { $_ -notin $actualIds })
    $unexpected = @($actualIds | Where-Object { $_ -notin $expectedIds })
    $inventoryInput = [string]::Join("`n", @($expectedIds | Sort-Object -CaseSensitive))
    $inventoryHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($inventoryInput))).ToLowerInvariant()
    $assemblyHashAfter = (Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $allPassed = @($actual | Where-Object { $_.status -ne 'passed' }).Count -eq 0
    $complete = $RunnerExitCode -eq 0 -and $assemblyHashBefore -ceq $assemblyHashAfter -and
        $expectedIds.Count -gt 0 -and @($expectedIds | Select-Object -Unique).Count -eq $expectedIds.Count -and
        $actual.Count -eq $expectedIds.Count -and $duplicates.Count -eq 0 -and
        $missing.Count -eq 0 -and $unexpected.Count -eq 0 -and $allPassed
    $record = @{ schema = 'phase10-dotnet-test-results-v1'; project = $SuiteId; runnerExitCode = $RunnerExitCode; complete = $complete
        startedUtc = $StartedUtc; finishedUtc = $FinishedUtc; assemblySha256 = $assemblyHashAfter; inventorySha256 = $inventoryHash
        expectedIds = $expectedIds; expectedCount = $expectedIds.Count; observedCount = $actual.Count
        missingCount = $missing.Count; unexpectedCount = $unexpected.Count; duplicateCount = $duplicates.Count; tests = @($actual) }
    $json = $record | ConvertTo-Json -Depth 5
    $directory = Split-Path -Parent $OutputPath
    [void][IO.Directory]::CreateDirectory($directory)
    $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    if (-not $complete) { throw "Discovered .NET tests did not reconcile with TRX outcomes: $SuiteId" }
}
