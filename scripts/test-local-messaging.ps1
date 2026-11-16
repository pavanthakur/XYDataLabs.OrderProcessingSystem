#Requires -Version 7.0
[CmdletBinding()]
param([string]$ArtifactDirectory='TestResults/DockerStorage',[ValidateRange(30,300)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root=Split-Path -Parent $PSScriptRoot
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
Assert-Phase10LocalSettings -Settings $settings -FullStack
$artifact=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($ArtifactDirectory)){$ArtifactDirectory}else{Join-Path $root $ArtifactDirectory}))
$allowed=[IO.Path]::GetFullPath((Join-Path $root 'TestResults'))+[IO.Path]::DirectorySeparatorChar
if(-not $artifact.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Messaging artifacts must stay under project TestResults.'}
$artifactOutputs=@('messaging-proof.json','functions-proof.json','replay-restoration.json')
foreach($artifactName in $artifactOutputs){
    if(Test-Path -LiteralPath (Join-Path $artifact $artifactName)){throw "Messaging artifact '$artifactName' already exists. Select a new run-specific ArtifactDirectory; prior evidence is never overwritten."}
}
[void][IO.Directory]::CreateDirectory($artifact)
$previousSql=[Environment]::GetEnvironmentVariable('PHASE10_NFR_SQL_CONNECTION_STRING')
$previousBus=[Environment]::GetEnvironmentVariable('PHASE10_NFR_SERVICEBUS_CONNECTION_STRING')
$previousReplay=[Environment]::GetEnvironmentVariable('LOCAL_SERVICEBUS_REPLAY_ENABLED')
$previousOperatorPassword=[Environment]::GetEnvironmentVariable('KEYCLOAK_TENANT_ADMIN_PASSWORD')
$functionOwner=& docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' xy-phase10-functions-1
if($LASTEXITCODE-ne 0-or$functionOwner-ne'xy-phase10'){throw 'An owned Functions container is required before replay proof.'}
$beforeEnv=@(& docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' xy-phase10-functions-1)
if($LASTEXITCODE-ne 0){throw 'Cannot read the original effective replay setting.'}
$originalReplayLine=$beforeEnv|Where-Object {$_ -like 'ServiceBus__ReplayEnabled=*'}|Select-Object -First 1
if($originalReplayLine-notin@('ServiceBus__ReplayEnabled=true','ServiceBus__ReplayEnabled=false')){throw 'Original replay setting is unknown; refuse replay mutation.'}
$originalReplay=$originalReplayLine.Split('=')[1]
$compose=@('compose','--env-file',(Join-Path $root 'Resources/Docker/.env.local.example'),'--env-file',(Join-Path $root 'Resources/Docker/.env.local'),'-f',(Join-Path $root 'compose/docker-compose.phase10.yml'),'--profile','*')
Push-Location $root
try {
    $env:PHASE10_NFR_SQL_CONNECTION_STRING=New-Phase10HostSqlConnectionString -Database OrderProcessingSystem_Dev -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $env:PHASE10_NFR_SQL_CONNECTION_STRING
    $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING=$settings.LOCAL_SERVICEBUS_HOST_CONNECTION_STRING
    $env:KEYCLOAK_TENANT_ADMIN_PASSWORD=$settings.KEYCLOAK_TENANT_ADMIN_PASSWORD
    dotnet run --project (Join-Path $root 'tools/Phase10.NfrProbe') --no-build -- --sql-read-mode direct --tenant-code TenantA --message-count 3 --timeout-seconds $TimeoutSeconds --result-path (Join-Path $artifact 'messaging-proof.json') 2>&1 | Protect-Phase10Log | Out-Host
    if($LASTEXITCODE-ne 0){throw 'Messaging consumer effects were not verified.'}
    $env:LOCAL_SERVICEBUS_REPLAY_ENABLED='true'
    & docker @compose up -d --no-deps --no-build functions 2>&1 | Protect-Phase10Log | Out-Host
    if($LASTEXITCODE-ne 0){throw 'Functions proof startup failed.'}
    dotnet run --project (Join-Path $root 'tools/Phase10.NfrProbe') --no-build -- functions-proof --tenant-code TenantA --timeout-seconds $TimeoutSeconds --result-path (Join-Path $artifact 'functions-proof.json') 2>&1 | Protect-Phase10Log | Out-Host
    if($LASTEXITCODE-ne 0){throw 'Functions intake/DLQ/replay effects were not verified.'}
}finally{
    $restoreExit=1
    $inspectExit=1
    $replayLine=$null
    $replayRestored=$false
    $restoreCommandFailed=$false
    try{
        $env:LOCAL_SERVICEBUS_REPLAY_ENABLED=$originalReplay
        & docker @compose up -d --no-deps --no-build functions 2>&1 | Protect-Phase10Log | Out-Host
        $restoreExit=$LASTEXITCODE
        $runtimeEnv=@(& docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' xy-phase10-functions-1)
        $inspectExit=$LASTEXITCODE
        $replayLine=$runtimeEnv|Where-Object {$_ -like 'ServiceBus__ReplayEnabled=*'}|Select-Object -First 1
        $replayRestored=$restoreExit-eq 0-and$inspectExit-eq 0-and$replayLine-eq"ServiceBus__ReplayEnabled=$originalReplay"
    }catch{
        $restoreCommandFailed=$true
    }finally{
        try{
            if($null-eq$previousSql){Remove-Item Env:PHASE10_NFR_SQL_CONNECTION_STRING -ErrorAction SilentlyContinue}else{$env:PHASE10_NFR_SQL_CONNECTION_STRING=$previousSql}
            if($null-eq$previousBus){Remove-Item Env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING -ErrorAction SilentlyContinue}else{$env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING=$previousBus}
            if($null-eq$previousReplay){Remove-Item Env:LOCAL_SERVICEBUS_REPLAY_ENABLED -ErrorAction SilentlyContinue}else{$env:LOCAL_SERVICEBUS_REPLAY_ENABLED=$previousReplay}
            if($null-eq$previousOperatorPassword){Remove-Item Env:KEYCLOAK_TENANT_ADMIN_PASSWORD -ErrorAction SilentlyContinue}else{$env:KEYCLOAK_TENANT_ADMIN_PASSWORD=$previousOperatorPassword}
        }finally{
            Pop-Location
        }
    }
    $reportWriteFailed=$false
    try{
        @{status=$(if($replayRestored-and-not$restoreCommandFailed){'passed'}else{'failed'});exitCode=$restoreExit;inspectExitCode=$inspectExit;effectiveSettingMatches=$replayRestored}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $artifact 'replay-restoration.json')
    }catch{
        $reportWriteFailed=$true
    }
    if($reportWriteFailed){throw 'Could not persist the Functions replay restoration record; environment variables and location were restored, but manual verification is required.'}
    if(-not$replayRestored-or$restoreCommandFailed){throw 'Could not verify the original Functions replay setting. Manual review is required.'}
}
