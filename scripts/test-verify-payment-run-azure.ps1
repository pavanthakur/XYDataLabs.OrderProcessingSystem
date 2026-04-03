<#!
.SYNOPSIS
    Regression runner for verify-payment-run-azure.ps1.

.DESCRIPTION
    Executes the Azure payment verifier as a child script, parses its JSON output,
    and asserts the key behaviors that previously regressed:
    - staging Azure path resolves and passes end to end
    - sparse/no App Insights evidence does not crash the verifier and marks
      log-side checks inconclusive when evidence is absent

.PARAMETER Scenario
    One or more regression scenarios to run.

.PARAMETER StagingRunPrefix
    Optional staging logical run prefix. If omitted, the verifier must be able to
    auto-resolve a single prefix for the current day.

.PARAMETER DevRunPrefix
    Optional dev logical run prefix used for the fallback/no-evidence regression.
    The dev scenario is skipped when this parameter is not supplied.

.PARAMETER SkipFirewallOpen
    Pass through to verify-payment-run-azure.ps1.

.EXAMPLE
    .\scripts\test-verify-payment-run-azure.ps1

.EXAMPLE
    .\scripts\test-verify-payment-run-azure.ps1 -Scenario stg-pass,dev-fallback -DevRunPrefix OR-1-2ndApr
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]] $Scenario = @('stg-pass'),

    [Parameter(Mandatory = $false)]
    [string] $StagingRunPrefix,

    [Parameter(Mandatory = $false)]
    [string] $DevRunPrefix,

    [Parameter(Mandatory = $false)]
    [switch] $SkipFirewallOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$supportedScenarios = @('stg-pass', 'dev-fallback')
$Scenario = @(
    $Scenario |
        ForEach-Object { [string] $_ } |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$invalidScenarios = @($Scenario | Where-Object { $supportedScenarios -notcontains $_ } | Sort-Object -Unique)
if ($invalidScenarios.Count -gt 0) {
    throw "Unsupported scenario value(s): $($invalidScenarios -join ', '). Supported values: $($supportedScenarios -join ', ')."
}

$script:TestResults = @()
$script:OverallSuccess = $true
$verifierScriptPath = Join-Path $PSScriptRoot 'verify-payment-run-azure.ps1'

function Write-TestHeader {
    param([string] $Title)

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string] $TestName,

        [Parameter(Mandatory = $true)]
        [bool] $Success,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [string] $ScenarioName = ''
    )

    $status = if ($Success) { 'PASS' } else { 'FAIL' }
    $color = if ($Success) { 'Green' } else { 'Red' }

    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "      $Message" -ForegroundColor Gray
    }

    $script:TestResults += [PSCustomObject] @{
        Scenario = $ScenarioName
        Test = $TestName
        Status = $status
        Message = $Message
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    if (-not $Success) {
        $script:OverallSuccess = $false
    }
}

function Add-SkippedResult {
    param(
        [Parameter(Mandatory = $true)]
        [string] $TestName,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [string] $ScenarioName = ''
    )

    Write-Host "[SKIP] $TestName" -ForegroundColor Yellow
    Write-Host "      $Message" -ForegroundColor Gray

    $script:TestResults += [PSCustomObject] @{
        Scenario = $ScenarioName
        Test = $TestName
        Status = 'SKIP'
        Message = $Message
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

function Get-Check {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [string] $CheckName
    )

    $property = $Report.Checks.PSObject.Properties[$CheckName]
    if ($null -eq $property) {
        throw "Check '$CheckName' was not present in the verifier output."
    }

    return $property.Value
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [string] $TestName,

        [Parameter(Mandatory = $true)]
        [object] $Expected,

        [Parameter(Mandatory = $true)]
        [object] $Actual,

        [Parameter(Mandatory = $false)]
        [string] $ScenarioName = ''
    )

    $success = ($Expected -eq $Actual)
    Add-TestResult -TestName $TestName -Success $success -Message "Expected: $Expected | Actual: $Actual" -ScenarioName $ScenarioName
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [string] $TestName,

        [Parameter(Mandatory = $true)]
        [bool] $Condition,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [string] $ScenarioName = ''
    )

    Add-TestResult -TestName $TestName -Success $Condition -Message $Message -ScenarioName $ScenarioName
}

function Invoke-Verifier {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'stg', 'prod')]
        [string] $Environment,

        [Parameter(Mandatory = $false)]
        [string] $RunPrefix
    )

    $arguments = @(
        '-NoProfile'
        '-File'
        $verifierScriptPath
        '-Environment'
        $Environment
        '-OutputFormat'
        'Json'
    )

    if (-not [string]::IsNullOrWhiteSpace($RunPrefix)) {
        $arguments += @('-RunPrefix', $RunPrefix)
    }

    if ($SkipFirewallOpen.IsPresent) {
        $arguments += '-SkipFirewallOpen'
    }

    $stdoutPath = Join-Path $env:TEMP ("verify-payment-run-azure-{0}-{1}.stdout.txt" -f $Environment, [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $env:TEMP ("verify-payment-run-azure-{0}-{1}.stderr.txt" -f $Environment, [guid]::NewGuid().ToString('N'))

    try {
        $process = Start-Process -FilePath 'pwsh' -ArgumentList $arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdoutText = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath -Raw } else { '' }
        $stderrText = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath -Raw } else { '' }

        if ($process.ExitCode -ne 0) {
            $details = @($stdoutText, $stderrText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            throw "Verifier exited with code $($process.ExitCode) for environment '$Environment'.`n$($details -join [Environment]::NewLine)"
        }
    }
    finally {
        if (Test-Path $stdoutPath) {
            Remove-Item $stdoutPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $stderrPath) {
            Remove-Item $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    $rawText = $stdoutText
    $jsonStart = $rawText.IndexOf('{')
    $jsonEnd = $rawText.LastIndexOf('}')

    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw "Verifier did not emit a JSON payload. Raw output:`n$rawText"
    }

    $jsonPayload = $rawText.Substring($jsonStart, ($jsonEnd - $jsonStart) + 1)
    return $jsonPayload | ConvertFrom-Json -Depth 12
}

function Test-StagingPassScenario {
    $scenarioName = 'stg-pass'
    Write-TestHeader 'Scenario: staging verifier passes end to end'

    try {
        $report = Invoke-Verifier -Environment 'stg' -RunPrefix $StagingRunPrefix
    }
    catch {
        $message = $_.Exception.Message
        $canSkipForLiveData = [string]::IsNullOrWhiteSpace($StagingRunPrefix) -and (
            $message -like '*No payment run prefixes were found*' -or
            $message -like '*Multiple run prefixes were found*'
        )

        if ($canSkipForLiveData) {
            Add-SkippedResult -TestName 'stg-pass scenario' -Message 'No unambiguous staging run prefix was available today. Re-run with -StagingRunPrefix to force the happy-path regression against a known run.' -ScenarioName $scenarioName
            return
        }

        throw
    }

    Assert-Equal -TestName 'stg-pass resolved environment' -Expected 'stg' -Actual $report.Environment -ScenarioName $scenarioName
    Assert-True -TestName 'stg-pass resolved run prefix' -Condition (-not [string]::IsNullOrWhiteSpace($report.RunPrefix)) -Message "RunPrefix: $($report.RunPrefix)" -ScenarioName $scenarioName

    $apiEvidenceCount = @($report.AppInsights.ApiEvidence).Count
    $uiEvidenceCount = @($report.AppInsights.UiEvidence).Count
    $hasLogEvidence = ($apiEvidenceCount -gt 0 -or $uiEvidenceCount -gt 0)
    Add-TestResult -TestName 'stg-pass evidence mode' -Success $true -Message "API rows: $apiEvidenceCount | UI rows: $uiEvidenceCount" -ScenarioName $scenarioName

    $dbCheckNames = @(
        'Pre-flight TenantA 3DS',
        'Pre-flight TenantB 3DS',
        'Pre-flight TenantC 3DS',
        'Q2 TenantA rows',
        'Q2 TenantB rows',
        'Q5 TenantA steps',
        'Q5 TenantB steps',
        'Q8 bleed',
        'Q2-B TenantC rows',
        'Q5-B TenantC steps',
        'Q9-B TenantC bleed'
    )

    foreach ($checkName in $dbCheckNames) {
        $check = Get-Check -Report $report -CheckName $checkName
        Assert-Equal -TestName "stg-pass check: $checkName" -Expected 'PASS' -Actual $check.Outcome -ScenarioName $scenarioName
    }

    $apiCheck = Get-Check -Report $report -CheckName 'API log -> DB charge IDs'
    $uiCheck = Get-Check -Report $report -CheckName 'UI log -> callbacks present where expected'

    if ($hasLogEvidence) {
        Assert-Equal -TestName 'stg-pass check: API log -> DB charge IDs' -Expected 'PASS' -Actual $apiCheck.Outcome -ScenarioName $scenarioName
        Assert-Equal -TestName 'stg-pass check: UI log -> callbacks present where expected' -Expected 'PASS' -Actual $uiCheck.Outcome -ScenarioName $scenarioName
        Assert-True -TestName 'stg-pass charge correlation populated' -Condition (@($report.ChargeCorrelation).Count -gt 0) -Message "Charge rows: $(@($report.ChargeCorrelation).Count)" -ScenarioName $scenarioName
        Assert-True -TestName 'stg-pass all charges persisted' -Condition (@($report.ChargeCorrelation | Where-Object { -not $_.InDb }).Count -eq 0) -Message 'All charge IDs resolved from App Insights were found in SQL.' -ScenarioName $scenarioName
        Assert-True -TestName 'stg-pass all expected UI callbacks logged' -Condition (@($report.ChargeCorrelation | Where-Object { $_.UiCallbackExpected -and -not $_.UiCallbackLogged }).Count -eq 0) -Message 'All 3DS charge flows had correlated UI callback evidence.' -ScenarioName $scenarioName
    }
    else {
        Assert-Equal -TestName 'stg-pass check: API log -> DB charge IDs' -Expected 'INCONCLUSIVE' -Actual $apiCheck.Outcome -ScenarioName $scenarioName
        Assert-Equal -TestName 'stg-pass check: UI log -> callbacks present where expected' -Expected 'INCONCLUSIVE' -Actual $uiCheck.Outcome -ScenarioName $scenarioName
        Assert-Equal -TestName 'stg-pass charge correlation absent without log evidence' -Expected 0 -Actual @($report.ChargeCorrelation).Count -ScenarioName $scenarioName
    }
}

function Test-DevFallbackScenario {
    $scenarioName = 'dev-fallback'
    Write-TestHeader 'Scenario: dev verifier survives sparse log evidence'

    if ([string]::IsNullOrWhiteSpace($DevRunPrefix)) {
        Add-SkippedResult -TestName 'dev-fallback scenario' -Message 'Provide -DevRunPrefix to exercise the sparse/no-evidence fallback path.' -ScenarioName $scenarioName
        return
    }

    $report = Invoke-Verifier -Environment 'dev' -RunPrefix $DevRunPrefix

    Assert-Equal -TestName 'dev-fallback resolved environment' -Expected 'dev' -Actual $report.Environment -ScenarioName $scenarioName
    Assert-Equal -TestName 'dev-fallback preserved requested run prefix' -Expected $DevRunPrefix -Actual $report.RunPrefix -ScenarioName $scenarioName
    Assert-True -TestName 'dev-fallback returned checks object' -Condition ($null -ne $report.Checks) -Message 'Verifier completed and emitted structured checks.' -ScenarioName $scenarioName

    $apiCheck = Get-Check -Report $report -CheckName 'API log -> DB charge IDs'
    $uiCheck = Get-Check -Report $report -CheckName 'UI log -> callbacks present where expected'
    $apiEvidenceCount = @($report.AppInsights.ApiEvidence).Count
    $uiEvidenceCount = @($report.AppInsights.UiEvidence).Count

    Assert-True -TestName 'dev-fallback API check returned a valid outcome' -Condition (@('PASS', 'FAIL', 'INCONCLUSIVE') -contains $apiCheck.Outcome) -Message "API outcome: $($apiCheck.Outcome)" -ScenarioName $scenarioName
    Assert-True -TestName 'dev-fallback UI check returned a valid outcome' -Condition (@('PASS', 'FAIL', 'INCONCLUSIVE') -contains $uiCheck.Outcome) -Message "UI outcome: $($uiCheck.Outcome)" -ScenarioName $scenarioName

    if ($apiEvidenceCount -eq 0) {
        Assert-Equal -TestName 'dev-fallback API no-evidence is inconclusive' -Expected 'INCONCLUSIVE' -Actual $apiCheck.Outcome -ScenarioName $scenarioName
    }

    if ($uiEvidenceCount -eq 0) {
        Assert-Equal -TestName 'dev-fallback UI no-evidence is inconclusive' -Expected 'INCONCLUSIVE' -Actual $uiCheck.Outcome -ScenarioName $scenarioName
    }
}

function Show-TestSummary {
    Write-TestHeader 'Regression Summary'

    $script:TestResults |
        Format-Table Scenario, Test, Status, Message -AutoSize |
        Out-String -Width 500 |
        Write-Host

    $passed = @($script:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = @($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    $skipped = @($script:TestResults | Where-Object { $_.Status -eq 'SKIP' }).Count
    $total = $script:TestResults.Count

    Write-Host "Results: $passed/$total passed, $failed failed, $skipped skipped" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
}

Write-Host '=====================================================' -ForegroundColor Magenta
Write-Host ' VERIFY-PAYMENT-RUN-AZURE REGRESSION TEST' -ForegroundColor Magenta
Write-Host '=====================================================' -ForegroundColor Magenta
Write-Host "Scenarios: $($Scenario -join ', ')" -ForegroundColor White
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White

if (-not (Test-Path $verifierScriptPath)) {
    throw "Verifier script not found: $verifierScriptPath"
}

foreach ($scenarioName in $Scenario) {
    switch ($scenarioName) {
        'stg-pass' {
            Test-StagingPassScenario
        }
        'dev-fallback' {
            Test-DevFallbackScenario
        }
    }
}

Show-TestSummary
exit $(if ($script:OverallSuccess) { 0 } else { 1 })