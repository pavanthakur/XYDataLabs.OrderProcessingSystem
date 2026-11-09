#Requires -Version 7.0
param([Parameter(Mandatory)][string]$ArtifactDirectory,[ValidateSet('baseline','extended')][string]$AcceptanceProfile='baseline')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$root=Split-Path -Parent $PSScriptRoot
$artifact=[IO.Path]::GetFullPath($ArtifactDirectory)
if(-not$artifact.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Sandbox evidence must stay under TestResults.'}
[void][IO.Directory]::CreateDirectory($artifact)
$previousRoot=$env:PHASE10_PAYMENT_REPORT_ROOT;$env:PHASE10_PAYMENT_REPORT_ROOT=$artifact
$rows=@()
try{
    foreach($negative in @($false,$true)){
        if(Test-Path (Join-Path $root 'TestResults/local-payment-test-state.lock')){throw 'Fixture recovery is required before more charges.'}
        $started=[DateTime]::UtcNow
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run-local-payment-tests.ps1') -Mode sandbox -Negative:$negative -AcceptanceProfile $AcceptanceProfile 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $artifact "sandbox-negative-$negative.log")
        $code=$LASTEXITCODE
        $report=Get-ChildItem $artifact -Directory -Filter 'payment-acceptance-sandbox-*'|Where-Object LastWriteTimeUtc -ge $started.AddSeconds(-1)|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
        $json=if($report -and(Test-Path (Join-Path $report.FullName 'summary.json'))){Get-Content (Join-Path $report.FullName 'summary.json') -Raw|ConvertFrom-Json}else{$null}
        $rows+=@{negative=$negative;rawExitCode=$code;primaryPassed=($json.primaryPassed-eq$true);status=$(if($null-eq$json){'failed'}else{$json.status});report=$(if($report){$report.FullName}else{$null})}
        if(Test-Path (Join-Path $root 'TestResults/local-payment-test-state.lock')){throw 'Fixture recovery is required; no independent mutating gates may continue.'}
    }
}finally{
    $env:PHASE10_PAYMENT_REPORT_ROOT=$previousRoot
    $primaryPassed=$rows.Count-eq 2-and@($rows|Where-Object {-not$_.primaryPassed-or$_.rawExitCode-ne 0}).Count-eq 0
    $hasFailure=$rows.Count-ne 2-or@($rows|Where-Object status -eq 'failed').Count-gt 0
    @{status=$(if($hasFailure){'failed'}elseif($primaryPassed){'passed'}else{'partial'});primaryPassed=$primaryPassed;results=$rows;capabilityStatus='blocked';note='Baseline payment results are independent from extended capability gaps; no capability gap is reported as PASS.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $artifact 'sandbox-gates.json')
}
if($rows.Count-eq 2-and@($rows|Where-Object {$_.rawExitCode-ne 0-or-not$_.primaryPassed}).Count-eq 0){exit 0}
exit 1
