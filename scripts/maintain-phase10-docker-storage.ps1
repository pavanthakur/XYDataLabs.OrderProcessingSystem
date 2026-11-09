# Read-only by default. Cleanup actions are explicit, project-scoped, and confirmed.
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Report', 'PruneBuildCache', 'PruneImages')]
    [string]$Action = 'Report',
    [string]$RollbackManifestPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
Assert-Phase10LocalDockerEndpoint
$root = Split-Path -Parent $PSScriptRoot
$settings = Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
$disk = Get-Phase10DockerDiskLocation
$drive = Assert-Phase10StorageCapacity -Path $disk -ForBuild:($Action -ne 'Report')

if ($Action -eq 'Report') {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'inspect-phase10-docker-storage.ps1') -Mode Report
    exit $LASTEXITCODE
}

if ($Action -eq 'PruneBuildCache') {
    $builder = @(& docker buildx ls 2>&1 | Protect-Phase10Log)
    if ($LASTEXITCODE -ne 0 -or -not ($builder -match '(?m)^desktop-linux\*?\s')) {
        throw 'The explicitly selected desktop-linux builder is unavailable; no cache was changed.'
    }
    if ($PSCmdlet.ShouldProcess('BuildKit cache on builder desktop-linux', 'Prune to a 20GB maximum used-space target')) {
        & docker buildx prune --builder desktop-linux --max-used-space 20GB 2>&1 | Protect-Phase10Log | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'BuildKit cache cleanup failed.' }
    }
    return
}

if ([string]::IsNullOrWhiteSpace($RollbackManifestPath)) {
    throw 'Image cleanup requires -RollbackManifestPath created before a cold build; no images were changed.'
}
$manifestFullPath = [IO.Path]::GetFullPath($RollbackManifestPath)
$resultsRoot = [IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\') + '\'
if (-not $manifestFullPath.StartsWith($resultsRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Rollback manifest must be under repository TestResults on Q:.'
}
$rollback = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
$keepIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($image in @($rollback.images)) {
    if ([string]$image.id -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Rollback manifest contains an invalid image ID; refusing cleanup.' }
    [void]$keepIds.Add([string]$image.id)
}
$requiredRollbackServices = @('orders', 'payments', 'inventory', 'notifications', 'gateway', 'ui', 'functions', 'azurite')
$recordedRollbackServices = @($rollback.images | ForEach-Object { [string]$_.service } | Sort-Object -Unique)
if (@($requiredRollbackServices | Where-Object { $_ -notin $recordedRollbackServices }).Count -gt 0) {
    throw 'Rollback manifest does not retain an image ID for each application/Functions/Azurite service; no images were removed.'
}
$containerIds = @(& docker ps -a -q --no-trunc)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect containers; refusing image cleanup.' }
$referencedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($containerId in $containerIds) {
    $imageId = [string](& docker inspect --format '{{.Image}}' $containerId)
    if ($LASTEXITCODE -ne 0 -or -not $imageId) { throw 'Cannot resolve a running container image; refusing image cleanup.' }
    [void]$referencedIds.Add($imageId.Trim())
}
$candidateIds = @(& docker image ls --no-trunc --quiet --filter 'label=org.xydatalabs.project=xy-phase10' | Sort-Object -Unique)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate project-labelled images; refusing image cleanup.' }
$projectTagPattern = '^ghcr\.io/[^/]+/orderprocessing-(orders|payments|inventory|notifications|gateway|ui|functions):.+$|^xydatalabs/phase10-azurite:.+$'
$removeRefs = @()
$removeDetails = @()
foreach ($imageId in $candidateIds) {
    if (-not $imageId -or $keepIds.Contains($imageId) -or $referencedIds.Contains($imageId)) { continue }
    $tagJson = & docker image inspect --format '{{json .RepoTags}}' $imageId
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect a candidate project image; refusing image cleanup.' }
    $repoTags = @($tagJson | ConvertFrom-Json)
    if ($repoTags.Count -gt 0 -and ($repoTags | Where-Object { $_ -and $_ -ne '<none>:<none>' -and $_ -notmatch $projectTagPattern }).Count -gt 0) {
        Write-Host "Preserving image with an unknown or shared repository tag: $imageId"
        continue
    }
    $projectTags = @($repoTags | Where-Object { $_ -and $_ -ne '<none>:<none>' -and $_ -match $projectTagPattern })
    $refsForImage = if ($projectTags.Count -gt 0) { $projectTags } else { @($imageId) }
    $removeRefs += $refsForImage
    $removeDetails += [ordered]@{ id = $imageId; references = $refsForImage }
}
$removeRefs = @($removeRefs | Sort-Object -Unique)
foreach ($detail in $removeDetails) { Write-Host "Project image candidate id=$($detail.id) refs=$($detail.references -join ',')" }
if ($removeRefs.Count -eq 0) { Write-Host 'No eligible image references; no changes needed.'; return }
$preview = @($removeDetails | ForEach-Object { "id=$($_.id) refs=$($_.references -join ',')" }) -join '; '
if ($PSCmdlet.ShouldProcess($preview, 'Remove unreferenced xy-phase10-labelled image references while preserving current and rollback IDs')) {
    foreach ($imageRef in $removeRefs) {
        & docker image rm $imageRef 2>&1 | Protect-Phase10Log | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Could not remove eligible project image reference $imageRef; stopping cleanup." }
    }
}
