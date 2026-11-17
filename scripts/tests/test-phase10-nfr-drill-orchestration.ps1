$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../phase10-nfr-drill-contract.ps1')
$tokens = $null
$parseErrors = $null
$runner = Join-Path $PSScriptRoot '../run-phase10-local-nfr-proof.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'NFR runner parse failed.' }
$function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ConsumerOutageBacklogDrill' }, $true)
if ($null -eq $function) { throw 'NFR drill function is missing.' }
# Load only the actual function definition, never the runner's runtime setup.
. ([scriptblock]::Create($function.Extent.Text))
function Get-Phase10ComposeArguments { return @('compose') }
function docker {
    if ($args -contains 'stop') { $global:LASTEXITCODE = if ($script:processCase -or $script:successCase) { 0 } else { 1 }; return }
    $script:actions.Add('consumer-start')
    $global:LASTEXITCODE = $script:startExit
}
function Start-Process {
    param(
        [string]$FilePath,
        [switch]$PassThru,
        [string]$WorkingDirectory,
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError,
        [string[]]$ArgumentList
    )
    $fake = [pscustomobject]@{ Handle = 1; HasExited = ($script:successCase -eq $true); ExitCode = $(if ($script:successCase) { 0 } else { 1 }); KilledTree = $false }
    $fake | Add-Member ScriptMethod Refresh {}
    $fake | Add-Member ScriptMethod Kill { param($entireTree) $this.KilledTree = $entireTree; if ($script:killFails) { throw 'Mock process-tree failure' }; $this.HasExited = $true }
    $fake | Add-Member ScriptMethod WaitForExit { param($milliseconds) return $this.HasExited }
    $script:fakeProbe = $fake
    # Simulate publication without starting a process or touching a broker.
    $messageCount = 25
    $messageIndex = [Array]::IndexOf($ArgumentList, '--message-count')
    if ($messageIndex -ge 0) { $messageCount = [int]$ArgumentList[$messageIndex + 1] }
    Set-Content (Join-Path $nfrRoot 'consumer-outage-drill-probe.out.log') "Published $messageCount OrderCreatedV1"
    if ($script:successCase) {
        $resultIndex = [Array]::IndexOf($ArgumentList, '--result-path')
        $probeResult = @{
            InventoryEffectCount = $messageCount
            NotificationEffectCount = $messageCount
            InventoryInboxCount = $messageCount
            NotificationsInboxCount = $messageCount
            P95Seconds = 1.25
        } | ConvertTo-Json
        Set-Content -LiteralPath $ArgumentList[$resultIndex + 1] -Value $probeResult
    }
    return $fake
}
function Wait-ForUrl {
    param($Url, $TimeoutSeconds)
    $script:actions.Add($Url)
    if ($script:readinessFails) { throw 'Mock readiness failure' }
}
$previousSql = $env:PHASE10_NFR_SQL_CONNECTION_STRING
$previousBus = $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING
$nfrRoot = Join-Path ([IO.Path]::GetTempPath()) ('phase10-drill-mock-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($nfrRoot)
try {
    foreach ($case in @(
        @{ StartExit = 0; ReadinessFails = $false; ExpectedRestore = 'passed' },
        @{ StartExit = 1; ReadinessFails = $false; ExpectedRestore = 'failed' },
        @{ StartExit = 0; ReadinessFails = $true; ExpectedRestore = 'failed' },
        @{ StartExit = 0; ReadinessFails = $false; ExpectedRestore = 'passed'; ProcessCase = $true; KillFails = $false },
        @{ StartExit = 0; ReadinessFails = $false; ExpectedRestore = 'failed'; ProcessCase = $true; KillFails = $true },
        @{ StartExit = 0; ReadinessFails = $false; ExpectedRestore = 'passed'; SuccessCase = $true; PreviousEnvironmentAbsent = $true }
    )) {
        $script:actions = [Collections.Generic.List[string]]::new()
        $script:startExit = $case.StartExit
        $script:readinessFails = $case.ReadinessFails
        $script:processCase = $case.ProcessCase -eq $true
        $script:successCase = $case.SuccessCase -eq $true
        $script:killFails = $case.KillFails -eq $true
        $script:fakeProbe = $null
        $script:Phase10NfrRestorationFailed = $false
        if ($case.PreviousEnvironmentAbsent) {
            Remove-Item Env:PHASE10_NFR_SQL_CONNECTION_STRING, Env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING -ErrorAction SilentlyContinue
        }
        else {
            $env:PHASE10_NFR_SQL_CONNECTION_STRING = 'mock-original-sql'
            $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING = 'mock-original-bus'
        }
        $threw = $false
        try { Invoke-ConsumerOutageBacklogDrill -TopicName 'mock' -SqlConnectionString 'mock-test-sql' -ServiceBusConnectionString 'mock-test-bus' | Out-Null }
        catch { $threw = $true }
        if ($script:successCase) {
            if ($threw) { throw 'Successful execution was incorrectly reported as a failure.' }
        }
        elseif (-not $threw) { throw 'Execution failure was not propagated.' }
        $record = Get-Content (Join-Path $nfrRoot 'consumer-outage-drill.json') -Raw | ConvertFrom-Json
        if ($script:successCase) {
            if ($record.status -ne 'passed' -or $record.restorationStatus -ne $case.ExpectedRestore) { throw 'Successful drill should pass execution and restoration.' }
        }
        elseif ($record.status -ne 'failed' -or $record.restorationStatus -ne $case.ExpectedRestore) { throw 'Incorrect final result.' }
        if ($script:Phase10NfrRestorationFailed -ne ($case.ExpectedRestore -eq 'failed')) { throw 'Subsequent-mutation gate does not match restoration outcome.' }
        if ($case.PreviousEnvironmentAbsent) {
            if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('PHASE10_NFR_SQL_CONNECTION_STRING', 'Process')) -or
                -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('PHASE10_NFR_SERVICEBUS_CONNECTION_STRING', 'Process'))) {
                throw 'Previously absent process environment variables were not restored as absent.'
            }
        }
        elseif ($env:PHASE10_NFR_SQL_CONNECTION_STRING -cne 'mock-original-sql' -or $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING -cne 'mock-original-bus') { throw 'Environment was not restored.' }
        if ($script:actions[0] -ne 'consumer-start') { throw 'Consumer restore was not attempted.' }
        $expectedActionCount = if ($script:processCase -or $script:successCase) { 6 } else { 3 }
        if ($case.ExpectedRestore -eq 'passed' -and $script:actions.Count -ne $expectedActionCount) { throw "Both readiness checks must execute (expected=$expectedActionCount actual=$($script:actions.Count) success=$script:successCase process=$script:processCase actions=$($script:actions -join ','))." }
        if ($script:processCase -and -not $script:fakeProbe.KilledTree) { throw 'Timed-out probe must be killed with entireProcessTree=true.' }
        if ($script:processCase -and $record.probeStopped -ne (-not $script:killFails)) { throw 'Process termination failure was not recorded.' }
        if ($script:successCase -and ($threw -or $record.status -ne 'passed' -or $record.executionStatus -ne 'passed' -or $record.restorationStatus -ne 'passed')) {
            throw 'Successful operational drill with absent prior environment must pass execution and restoration.'
        }
    }

    $replayBlock = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $node.ScriptBlock.Extent.Text.Contains('$restorePath = Join-Path') }, $true)
    if ($null -eq $replayBlock) { throw 'Parent replay restoration gate is missing.' }
    $text = $replayBlock.ScriptBlock.Extent.Text
    $sourceRoot = (Split-Path -Parent ([IO.Path]::GetFullPath($runner))).Replace("'", "''")
    $invokeReplay = [scriptblock]::Create($text.Substring(1, $text.Length - 2).Replace('$PSScriptRoot', "'$sourceRoot'"))
    function pwsh {
        $directory = Join-Path $nfrRoot 'replay-proof'
        [void][IO.Directory]::CreateDirectory($directory)
        if ($script:restorePayload) { Set-Content (Join-Path $directory 'replay-restoration.json') $script:restorePayload }
        $global:LASTEXITCODE = $script:childExit
    }
    foreach ($scenario in @(
        @{ Payload = $null; ChildExit = 0; Blocked = $true },
        @{ Payload = '{'; ChildExit = 0; Blocked = $true },
        @{ Payload = '{"status":"failed"}'; ChildExit = 1; Blocked = $true },
        @{ Payload = '{"status":"passed","exitCode":0,"inspectExitCode":0,"effectiveSettingMatches":true}'; ChildExit = 0; Blocked = $false },
        @{ Payload = '{"status":"passed","exitCode":0,"inspectExitCode":0,"effectiveSettingMatches":true}'; ChildExit = 1; Blocked = $false }
    )) {
        $file = Join-Path $nfrRoot 'replay-proof/replay-restoration.json'
        if (Test-Path $file) { Remove-Item -LiteralPath $file }
        $script:restorePayload = $scenario.Payload
        $script:childExit = $scenario.ChildExit
        $script:Phase10NfrRestorationFailed = $false
        $rejected = $false
        $mockFailure = ''
        try { & $invokeReplay } catch { $rejected = $true; $mockFailure = $_.Exception.Message }
        if ($script:Phase10NfrRestorationFailed -ne $scenario.Blocked) { throw "Parent replay mutation gate failed (exit=$($scenario.ChildExit), expectedBlocked=$($scenario.Blocked)): $mockFailure" }
        if ($rejected -ne ($scenario.Blocked -or $scenario.ChildExit -ne 0)) { throw 'Parent incorrectly accepted/rejected replay execution.' }
    }
} finally {
    [Environment]::SetEnvironmentVariable('PHASE10_NFR_SQL_CONNECTION_STRING', $previousSql, 'Process')
    [Environment]::SetEnvironmentVariable('PHASE10_NFR_SERVICEBUS_CONNECTION_STRING', $previousBus, 'Process')
    $resolvedRoot = [IO.Path]::GetFullPath($nfrRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedRoot) -notmatch '^phase10-drill-mock-[0-9a-f]{32}$') { throw 'Unsafe test cleanup target.' }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}
Write-Host 'PASS actual NFR drill: failed execution, restart/readiness failures, environment restoration and mutation gate (all runtime commands mocked).'
