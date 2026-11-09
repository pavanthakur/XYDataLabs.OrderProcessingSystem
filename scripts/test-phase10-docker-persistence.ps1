#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$RestartDesktop,[string]$ArtifactDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root=Split-Path -Parent $PSScriptRoot
if(-not $RestartDesktop){throw 'Use -RestartDesktop to explicitly exercise the Docker Desktop restart. No data reset is performed.'}
if(Test-Path (Join-Path $root 'TestResults/local-payment-test-state.lock')){throw 'A payment fixture is active or needs recovery. Do not restart during a test.'}
if(@(Get-ChildItem (Join-Path $root 'TestResults') -Filter 'integration-active-*.lock').Count){throw 'Integration execution/recovery is active. Do not restart.'}
foreach($container in @(& docker ps -q)){
    $owner=& docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $container
    if($LASTEXITCODE-ne 0-or([string]$owner).Trim()-ne'xy-phase10'){throw 'Unrelated running containers would be interrupted. Restart acceptance needs separate operator coordination.'}
}
$disk=Get-Phase10DockerDiskLocation
if($disk.TrimEnd('\')-ine'G:\DockerStorage\DockerDesktopWSL'){throw 'Unexpected active disk location. Restart acceptance stopped.'}
if(-not $PSCmdlet.ShouldProcess('Docker Desktop and xy-phase10 containers','Restart and verify SQL persistence without deleting data')){return}
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
$artifact=if($ArtifactDirectory){[IO.Path]::GetFullPath($ArtifactDirectory)}else{Join-Path $root ("TestResults/DockerStorage/persistence-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))}
if(-not$artifact.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Persistence evidence must stay under TestResults.'}
[void](New-Item -ItemType Directory -Path $artifact)
function Get-Snapshot {
    $registryCs=New-Phase10HostSqlConnectionString -Database 'OrderProcessingSystem_Dev' -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $registryCs
    $registryCx=[System.Data.SqlClient.SqlConnection]::new($registryCs)
    try{$registryCx.Open();$registryCmd=$registryCx.CreateCommand();$registryCmd.CommandText="SELECT Code FROM dbo.Tenants WHERE Status='Active' ORDER BY Code";$registryReader=$registryCmd.ExecuteReader();$tenants=@();while($registryReader.Read()){$tenants+=$registryReader.GetString(0)};$registryReader.Dispose()}finally{$registryCx.Dispose()}
    $contract=Get-Content (Join-Path $root 'Resources/Configuration/tenant-bootstrap.local.json') -Raw|ConvertFrom-Json
    foreach($required in $contract.requiredBaselineTenants){if($required-notin$tenants){throw "Required baseline tenant '$required' is missing before persistence proof."}}
    $rows=foreach($tenant in $tenants){
        $database=Resolve-Phase10LocalTenantDatabase -TenantCode $tenant -Settings $settings
        $cs=New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
        Assert-Phase10HostSqlIdentity -ConnectionString $cs
        $cx=[System.Data.SqlClient.SqlConnection]::new($cs)
        try{
            $cx.Open();$command=$cx.CreateCommand()
            $command.CommandText='SELECT TOP(1) o.OrderId,o.OrderReferenceId,o.TotalPrice,o.CurrencyCode,o.Status FROM orders.Orders o JOIN dbo.Tenants t ON t.Id=o.TenantId WHERE t.Code=@tenant AND o.Status=''Paid'' ORDER BY o.OrderId DESC'
            [void]$command.Parameters.AddWithValue('@tenant',$tenant)
            $reader=$command.ExecuteReader()
            if(-not $reader.Read()){throw "No Paid order available to prove persistence for $tenant."}
            [ordered]@{tenant=$tenant;database=$database;orderId=$reader.GetInt32(0);reference=$reader.GetGuid(1).ToString();amount=$reader.GetDecimal(2);currency=$reader.GetString(3);status=$reader.GetString(4)}
        }finally{$cx.Dispose()}
    }
    return @($rows)
}
$before=Get-Snapshot
$before|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $artifact 'before.json')
$nativeBefore=@(Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess -Unique|Sort-Object)
$mounts=& docker inspect xy-phase10-sql-server-1 --format '{{json .Mounts}}'|ConvertFrom-Json
$sqlVolume=($mounts|Where-Object Destination -eq '/var/opt/mssql').Name
if([string]::IsNullOrWhiteSpace($sqlVolume)-or$sqlVolume-notlike'xy-phase10_*'){throw 'Application SQL is not on an explicit project volume.'}
$report=[ordered]@{status='running';artifact=$artifact;disk=$disk;sqlVolume=$sqlVolume;nativeSqlBefore=$nativeBefore}
try{
    & docker desktop restart --timeout 180 2>&1|Protect-Phase10Log|Out-Host
    if($LASTEXITCODE-ne 0){throw 'Docker Desktop restart did not complete.'}
    & docker compose --env-file (Join-Path $root 'Resources/Docker/.env.local.example') --env-file (Join-Path $root 'Resources/Docker/.env.local') -f (Join-Path $root 'compose/docker-compose.phase10.yml') --profile '*' up -d --no-build 2>&1|Protect-Phase10Log|Out-Host
    if($LASTEXITCODE-ne 0){throw 'Project startup after Desktop restart failed.'}
    foreach($port in @(5080,5081,5082,5083,5084)){
        $ready=$false;$deadline=(Get-Date).AddSeconds(120)
        do{try{if((Invoke-WebRequest "http://localhost:$port/health/ready" -TimeoutSec 5).StatusCode-eq 200){$ready=$true;break}}catch{};Start-Sleep -Seconds 2}while((Get-Date)-lt$deadline)
        if(-not $ready){throw "Readiness did not recover for port $port."}
    }
    foreach($url in @('http://localhost:5022/','http://localhost:5085/','http://localhost:8081/','http://localhost:5300/health')){
        $reachable=$false;$deadline=(Get-Date).AddSeconds(120)
        do{try{if((Invoke-WebRequest $url -TimeoutSec 5).StatusCode-eq 200){$reachable=$true;break}}catch{};Start-Sleep -Seconds 2}while((Get-Date)-lt$deadline)
        if(-not$reachable){throw "Public service endpoint did not recover: $url"}
    }
    $report.publicEndpointsReachable=$true
    if((Get-Phase10DockerDiskLocation).TrimEnd('\')-ine$disk.TrimEnd('\')){throw 'Active backing disk location changed after restart.'}
    $after=Get-Snapshot
    $after|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $artifact 'after.json')
    if(($before|ConvertTo-Json -Depth 5 -Compress)-ne($after|ConvertTo-Json -Depth 5 -Compress)){throw 'Known SQL rows changed or disappeared across restart.'}
    $mountsAfter=& docker inspect xy-phase10-sql-server-1 --format '{{json .Mounts}}'|ConvertFrom-Json
    if(($mountsAfter|Where-Object Destination -eq '/var/opt/mssql').Name-ne$sqlVolume){throw 'SQL persistent volume changed.'}
    $nativeAfter=@(Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess -Unique|Sort-Object)
    if(($nativeBefore-join',')-ne($nativeAfter-join',')){throw 'Native Windows SQL listener changed; investigate separately.'}
    $report.status='passed';$report.nativeSqlAfter=$nativeAfter
}catch{$report.status='failed';$report.error=$_.Exception.Message;throw}
finally{$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $artifact 'summary.json');Write-Output "Persistence evidence: $artifact"}
