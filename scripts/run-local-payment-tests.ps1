#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('sandbox','deterministic')][string]$Mode='sandbox',
    [switch]$Headed,
    [switch]$ManualSmoke,
    [switch]$Negative,
    [ValidateSet('baseline','extended')][string]$AcceptanceProfile='baseline',
    [string]$TenantCode,
    [ValidateSet('Razorpay','OpenPay')][string]$ProviderType
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root=Split-Path -Parent $PSScriptRoot
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
Assert-Phase10LocalSettings -Settings $settings -FullStack
if (-not ([string]$settings.LOCAL_RAZORPAY_MERCHANT_ID).StartsWith('rzp_test_', [StringComparison]::Ordinal)) { throw 'Only a Razorpay test-mode key ID is permitted for local payment acceptance; configured value omitted.' }
$previous=[Environment]::GetEnvironmentVariable('LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS')
$compose=@('compose','--env-file',(Join-Path $root 'Resources/Docker/.env.local.example'),'--env-file',(Join-Path $root 'Resources/Docker/.env.local'),'-f',(Join-Path $root 'compose/docker-compose.phase10.yml'),'--profile','*')
$exitCode=1
try {
    $env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS=if($Mode -eq 'deterministic'){'true'}else{'false'}
    & docker @compose up -d --no-deps --no-build payments 2>&1 | Protect-Phase10Log | Out-Host
    if($LASTEXITCODE -ne 0){throw 'Payment runtime mode switch failed.'}
    $ready=$false
    for($attempt=0;$attempt -lt 30;$attempt++){
        try {if((Invoke-WebRequest http://localhost:5084/health -TimeoutSec 3).StatusCode -eq 200){$ready=$true;break}}catch{}
        Start-Sleep -Seconds 2
    }
    if(-not $ready){throw 'Payments service did not become ready.'}
    $scriptName="test:payments:$Mode"
    if($Negative -and $Mode-eq'sandbox'){$scriptName+=':negative'}
    $arguments=@('--prefix',(Join-Path $root 'automation'),'run',$scriptName)
    if($TenantCode -or $ProviderType -or $ManualSmoke -or $Headed -or ($Negative -and $Mode-eq'deterministic') -or $AcceptanceProfile -ne 'baseline'){
        $arguments+='--'
        if($TenantCode){$arguments+=@('--tenant',$TenantCode)}
        if($ProviderType){$arguments+=@('--provider',$ProviderType)}
        if($ManualSmoke){$arguments+='--manual-smoke'}
        if($Headed){$arguments+='--headed'}
        if($Negative -and $Mode-eq'deterministic'){$arguments+='--negative'}
        if($AcceptanceProfile -ne 'baseline'){$arguments+=@('--acceptance-profile',$AcceptanceProfile)}
    }
    & npm @arguments 2>&1 | Protect-Phase10Log | Out-Host
    $exitCode=$LASTEXITCODE
} finally {
    # Always return the normal local UI to real sandbox, never leave simulation
    # enabled after a deterministic regression (including an unsuccessful run).
    $env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS='false'
    & docker @compose up -d --no-deps --no-build payments 2>&1 | Protect-Phase10Log | Out-Host
    $restoreExit=$LASTEXITCODE
    if($null -eq $previous){Remove-Item Env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS -ErrorAction SilentlyContinue}
    else{$env:LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS=$previous}
    if($restoreExit -ne 0){throw 'Could not restore sandbox runtime. Manual review is required.'}
}
exit $exitCode
