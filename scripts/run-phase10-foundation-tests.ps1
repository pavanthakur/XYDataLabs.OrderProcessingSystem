#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$root=Split-Path -Parent $PSScriptRoot
$artifact=[IO.Path]::GetFullPath($ArtifactDirectory)
if(-not $artifact.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Test artifacts must remain under project TestResults.'}
[void][IO.Directory]::CreateDirectory($artifact)
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
$results=@()
function Run-Test([string]$name,[string]$command,[string[]]$arguments){
    $started=[DateTime]::UtcNow
    & $command @arguments 2>&1|Protect-Phase10Log|Tee-Object -FilePath (Join-Path $artifact "$name.log")|Out-Null
    $code=$LASTEXITCODE
    $script:results+=@{name=$name;exitCode=$code;status=$(if($code-eq 0){'passed'}else{'failed'});startedUtc=$started.ToString('o');finishedUtc=[DateTime]::UtcNow.ToString('o')}
    Write-Host "$name exit=$code"
}
Push-Location $root
try{
    Run-Test 'docker-safety' 'pwsh' @('-NoProfile','-File','scripts/test-phase10-docker-safety.ps1')
    Run-Test 'fixture-regression' 'pwsh' @('-NoProfile','-File','scripts/test-phase10-payment-fixture.ps1')
    foreach($name in @('Domain','Application','API','Gateway','Architecture')){
        Run-Test "$name-tests" 'dotnet' @('test',"tests/XYDataLabs.OrderProcessingSystem.$name.Tests/XYDataLabs.OrderProcessingSystem.$name.Tests.csproj",'--blame-hang-timeout','90s','--logger','console;verbosity=minimal','--logger',"trx;LogFileName=$name.trx",'--results-directory',$artifact)
    }
    Run-Test 'frontend-tests' 'npm' @('--prefix','frontend','run','test:web')
    Run-Test 'frontend-typecheck' 'npm' @('--prefix','frontend','run','typecheck')
    Push-Location (Join-Path $root 'automation')
    try{Run-Test 'automation-typecheck' 'npx' @('tsc','--noEmit','-p','tsconfig.json')}finally{Pop-Location}
    foreach($suite in @('test:payment-evidence','test:acceptance-coverage','test:verification-polling','test:callbacks','test:callbacks:browser','test:provider-challenges:browser')){
        Run-Test ($suite.Replace(':','-')) 'npm' @('--prefix','automation','run',$suite)
    }
    Run-Test 'messaging-probe-build' 'dotnet' @('build','tools/Phase10.NfrProbe','--verbosity','quiet')
}finally{
    Pop-Location
    @{results=$results;status=$(if(@($results|Where-Object status -eq 'failed').Count){'failed'}else{'passed'})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $artifact 'summary.json')
}
if(@($results|Where-Object status -eq 'failed').Count){exit 1}
