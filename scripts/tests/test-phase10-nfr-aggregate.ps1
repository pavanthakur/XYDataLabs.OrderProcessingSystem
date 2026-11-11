#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\phase10-nfr-aggregate.ps1')

function New-Categories([hashtable]$Statuses) {
    $result = [ordered]@{}
    foreach ($key in $Statuses.Keys) { $result[$key] = [ordered]@{ status = $Statuses[$key] } }
    $result
}

$cases = @(
    @{ name = 'all passed'; input = @{ functional = 'passed'; operational = 'passed'; recovery = 'passed' }; expected = 'passed' },
    @{ name = 'skipped required category is not PASS'; input = @{ functional = 'passed'; operational = 'skipped'; recovery = 'skipped' }; expected = 'incomplete' },
    @{ name = 'blocked rollback is not PASS'; input = @{ functional = 'passed'; operational = 'passed'; recovery = 'blocked' }; expected = 'incomplete' },
    @{ name = 'failure outranks blocked'; input = @{ functional = 'failed'; operational = 'passed'; recovery = 'blocked' }; expected = 'failed' },
    @{ name = 'unfinished category is not PASS'; input = @{ functional = 'passed'; operational = 'running' }; expected = 'incomplete' }
)

$failures = 0
foreach ($case in $cases) {
    $actual = (Get-Phase10NfrAggregate -Categories (New-Categories $case.input)).Status
    if ($actual -ne $case.expected) {
        Write-Host "FAIL $($case.name): expected $($case.expected), got $actual"
        $failures++
    }
    else { Write-Host "PASS $($case.name)" }
}

$named = (Get-Phase10NfrAggregate -Categories (New-Categories @{ operational = 'passed'; recovery = 'blocked' })).NonPassing
if ($named -notcontains 'recovery=blocked') { Write-Host 'FAIL non-passing categories are not named'; $failures++ }

if ($failures -gt 0) { exit 1 }
Write-Host 'All Phase 10 NFR aggregate cases passed.'
exit 0
