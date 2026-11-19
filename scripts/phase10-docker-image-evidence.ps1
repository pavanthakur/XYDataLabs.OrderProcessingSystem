#Requires -Version 7.0

function Get-Phase10WorktreeContentIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot, [Parameter(Mandatory = $true)]$GitCommand)

    $changed = @(& $GitCommand.Source -C $WorkspaceRoot diff --name-only HEAD -- 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate tracked worktree changes for image provenance.' }
    $untracked = @(& $GitCommand.Source -C $WorkspaceRoot ls-files --others --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate untracked worktree files for image provenance.' }
    $paths = @(@($changed) + @($untracked) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    $rootFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $entries = @()
    foreach ($relativePath in $paths) {
        $normalized = ([string]$relativePath).Replace([IO.Path]::DirectorySeparatorChar, '/')
        if ($normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.?(/|$)') { throw 'Git returned an unsafe changed path during provenance capture.' }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull ([string]$relativePath)))
        if (-not $fullPath.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Changed worktree path escaped the repository during provenance capture.'
        }
        $state = 'deleted'
        $contentHash = $null
        if (Test-Path -LiteralPath $fullPath) {
            $item = Get-Item -LiteralPath $fullPath -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $state = 'link'
                $contentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                    [Text.Encoding]::UTF8.GetBytes([string]$item.Target))).ToLowerInvariant()
            }
            elseif ($item.PSIsContainer) {
                $submoduleHead = @(& $GitCommand.Source -C $fullPath rev-parse --verify HEAD 2>$null)
                if ($LASTEXITCODE -ne 0 -or $submoduleHead.Count -ne 1) { throw 'A changed directory is not a verifiable Git submodule.' }
                $state = 'submodule'
                $contentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                    [Text.Encoding]::UTF8.GetBytes($submoduleHead[0]))).ToLowerInvariant()
            }
            else {
                $state = 'file'
                $contentHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        $entries += [ordered]@{ path = $normalized; state = $state; sha256 = $contentHash }
    }
    $canonical = ConvertTo-Json -InputObject @($entries) -Depth 5 -Compress
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
    return [ordered]@{ sha256 = $hash; changedPaths = @($entries | ForEach-Object { $_.path }) }
}

function Get-Phase10DockerImageManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('before', 'after')][string]$CapturePoint,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ComposeFile,
        [Parameter(Mandatory = $true)][string]$EnvExampleFile,
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$ArtifactRoot
    )

    $profiles = @('data', 'identity', 'storage', 'messaging', 'apps', 'functions')
    $composeArgs = @('--env-file', $EnvExampleFile, '--env-file', $EnvFile, '-f', $ComposeFile)
    foreach ($profile in $profiles) { $composeArgs += @('--profile', $profile) }

    $services = @(& docker compose @composeArgs config --services 2>$null)
    $expectedServices = @('azurite','functions','gateway','inventory','keycloak-local','notifications','orders','payments','redis','servicebus-emulator','servicebus-sql','sql-server','ui')
    $serviceList = (@($services | Sort-Object) -join ',')
    $expectedServiceList = (@($expectedServices | Sort-Object) -join ',')
    if ($LASTEXITCODE -ne 0 -or $services.Count -ne 13 -or @($services | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9_-]*$' }).Count -or
        $serviceList -cne $expectedServiceList) {
        throw 'Could not discover the complete expected Phase 10 Compose service set.'
    }
    if (@($services | Select-Object -Unique).Count -ne $services.Count) {
        throw 'Compose service discovery returned duplicate service identities.'
    }

    $images = @()
    foreach ($service in $services) {
        $containerIds = @(& docker compose @composeArgs ps --all -q $service 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($LASTEXITCODE -ne 0 -or $containerIds.Count -ne 1 -or $containerIds[0] -notmatch '^[0-9a-f]{12,64}$') {
            throw "Expected exactly one owned Phase 10 container for service '$service'."
        }
        $containerJson = @(& docker inspect --type container $containerIds[0] 2>$null)
        if ($LASTEXITCODE -ne 0) { throw "Could not inspect Phase 10 container for service '$service'." }
        try { $container = ($containerJson -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch { throw "Container inspection for '$service' was invalid." }
        $container = @($container)[0]
        $labels = $container.Config.Labels
        if ($labels.'com.docker.compose.project' -cne 'xy-phase10' -or $labels.'com.docker.compose.service' -cne $service) {
            throw "Container ownership does not match the Phase 10 project/service for '$service'."
        }
        $imageId = [string]$container.Image
        if ($imageId -notmatch '^sha256:[0-9a-f]{64}$' -or [string]::IsNullOrWhiteSpace([string]$container.Config.Image)) {
            throw "Image identity is missing or malformed for service '$service'."
        }
        $imageJson = @(& docker image inspect $imageId 2>$null)
        if ($LASTEXITCODE -ne 0) { throw "Could not inspect image identity for service '$service'." }
        try { $image = (@($imageJson -join "`n" | ConvertFrom-Json -ErrorAction Stop))[0] } catch { throw "Image inspection for '$service' was invalid." }
        $digests = @($image.RepoDigests | Where-Object { $_ -match '^.+@sha256:[0-9a-f]{64}$' } | Sort-Object -Unique)
        $images += [ordered]@{
            project = 'xy-phase10'
            service = [string]$service
            containerId = $containerIds[0]
            imageReference = [string]$container.Config.Image
            imageId = $imageId
            repositoryDigests = $digests
        }
    }

    $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $candidateSha = @(& $gitCommand.Source -C $WorkspaceRoot rev-parse --verify HEAD 2>$null)
    $status = @(& $gitCommand.Source --no-optional-locks -C $WorkspaceRoot status --porcelain=v1 --untracked-files=normal 2>$null)
    if ($LASTEXITCODE -ne 0 -or $candidateSha.Count -ne 1 -or $candidateSha[0] -notmatch '^([0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'Could not capture a trustworthy source revision for image identity evidence.'
    }
    $worktree = if ($status.Count) { 'dirty' } else { 'clean' }
    $statusBytes = [Text.UTF8Encoding]::new($false).GetBytes(($status -join "`n"))
    $dirtyIdentity = if ($worktree -eq 'dirty') {
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($statusBytes)).ToLowerInvariant()
    } else { $null }
    $contentIdentity = if ($worktree -eq 'dirty') { Get-Phase10WorktreeContentIdentity -WorkspaceRoot $WorkspaceRoot -GitCommand $gitCommand } else { $null }
    # Assign through a typed local: an empty array inside an if-expression can be
    # unrolled by PowerShell and serialized as JSON null instead of [].
    [string[]]$changedPaths = @()
    if ($contentIdentity) { $changedPaths = [string[]]@($contentIdentity.changedPaths) }
    $buildLogs = [ordered]@{}
    foreach ($name in @('docker-compose-apps-build.log', 'docker-compose-azurite-build.log')) {
        $path = Join-Path $ArtifactRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 20MB) { throw "Build evidence log '$name' is not a bounded regular file." }
            $buildLogs[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $manifest = [ordered]@{
        schema = 'phase10-docker-image-identities-v1'
        runId = $RunId
        capturePoint = $CapturePoint
        capturedUtc = [DateTime]::UtcNow.ToString('o')
        candidate = [ordered]@{
            commit = $candidateSha[0]
            worktree = $worktree
            dirtyStatusSha256 = $dirtyIdentity
            worktreeContentSha256 = if ($contentIdentity) { $contentIdentity.sha256 } else { $null }
            changedPaths = $changedPaths
        }
        buildLogsSha256 = $buildLogs
        images = $images
    }
    $json = $manifest | ConvertTo-Json -Depth 8
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 2MB) { throw 'Image identity manifest exceeds the evidence size limit.' }
    $temporary = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $OutputPath)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    return $manifest
}

function Test-Phase10DockerImageManifestShape {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest, [string]$ExpectedCapturePoint)
    $expectedServices = @('azurite','functions','gateway','inventory','keycloak-local','notifications','orders','payments','redis','servicebus-emulator','servicebus-sql','sql-server','ui')
    $candidateDirtyValid = ($Manifest.candidate.worktree -eq 'clean' -and $null -eq $Manifest.candidate.dirtyStatusSha256) -or
        ($Manifest.candidate.worktree -eq 'dirty' -and $Manifest.candidate.dirtyStatusSha256 -match '^[0-9a-f]{64}$')
    $candidateContentValid = ($null -eq $Manifest.candidate.worktreeContentSha256 -or $Manifest.candidate.worktreeContentSha256 -match '^[0-9a-f]{64}$') -and
        ($null -eq $Manifest.candidate.changedPaths -or ($Manifest.candidate.changedPaths -is [array] -and
            @($Manifest.candidate.changedPaths | Where-Object { $_ -isnot [string] -or $_ -match '(^|/)\.\.?(/|$)' -or $_.StartsWith('/') }).Count -eq 0))
    if ($Manifest.schema -cne 'phase10-docker-image-identities-v1' -or [string]::IsNullOrWhiteSpace([string]$Manifest.runId) -or
        $Manifest.capturePoint -notin @('before','after') -or ($ExpectedCapturePoint -and $Manifest.capturePoint -cne $ExpectedCapturePoint) -or
        -not $candidateDirtyValid -or -not $candidateContentValid -or $Manifest.candidate.commit -notmatch '^([0-9a-f]{40}|[0-9a-f]{64})$' -or @($Manifest.images).Count -ne 13) { return $false }
    $services = @($Manifest.images | ForEach-Object { [string]$_.service } | Sort-Object)
    if (($services -join ',') -cne (@($expectedServices | Sort-Object) -join ',')) { return $false }
    $containerIds = @()
    foreach ($image in $Manifest.images) {
        if ($image.project -cne 'xy-phase10' -or $image.containerId -notmatch '^[0-9a-f]{12,64}$' -or
            $image.imageId -notmatch '^sha256:[0-9a-f]{64}$' -or [string]::IsNullOrWhiteSpace([string]$image.imageReference) -or
            $null -eq $image.repositoryDigests -or @($image.repositoryDigests | Where-Object { $_ -notmatch '^.+@sha256:[0-9a-f]{64}$' }).Count) { return $false }
        $containerIds += [string]$image.containerId
    }
    return @($containerIds | Select-Object -Unique).Count -eq $containerIds.Count
}

function Test-Phase10DockerImageManifestsMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After)
    if (-not (Test-Phase10DockerImageManifestShape -Manifest $Before -ExpectedCapturePoint before) -or
        -not (Test-Phase10DockerImageManifestShape -Manifest $After -ExpectedCapturePoint after) -or
        $Before.runId -cne $After.runId -or $Before.candidate.commit -cne $After.candidate.commit -or
        $Before.candidate.worktree -cne $After.candidate.worktree -or
        $Before.candidate.dirtyStatusSha256 -cne $After.candidate.dirtyStatusSha256 -or
        $Before.candidate.worktreeContentSha256 -cne $After.candidate.worktreeContentSha256 -or
        (($Before.candidate.changedPaths | ConvertTo-Json -Compress) -cne ($After.candidate.changedPaths | ConvertTo-Json -Compress))) { return $false }
    $left = @($Before.images | Sort-Object { $_.service })
    $right = @($After.images | Sort-Object { $_.service })
    if ($left.Count -ne 13 -or $right.Count -ne 13 -or $left.Count -ne $right.Count) { return $false }
    for ($index = 0; $index -lt $left.Count; $index++) {
        if ($left[$index].project -cne 'xy-phase10' -or $right[$index].project -cne 'xy-phase10' -or
            $left[$index].service -cne $right[$index].service -or $left[$index].imageId -cne $right[$index].imageId -or
            $left[$index].imageReference -cne $right[$index].imageReference -or
            (@($left[$index].repositoryDigests | Sort-Object) -join "`n") -cne (@($right[$index].repositoryDigests | Sort-Object) -join "`n")) { return $false }
    }
    return $true
}

function Assert-Phase10DockerImageManifestMatches {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Expected, [Parameter(Mandatory = $true)]$Actual)
    if (-not (Test-Phase10DockerImageManifestShape -Manifest $Expected -ExpectedCapturePoint before) -or
        -not (Test-Phase10DockerImageManifestShape -Manifest $Actual) -or
        $Expected.candidate.worktree -ne 'clean' -or $Actual.candidate.worktree -ne 'clean' -or
        $Expected.candidate.commit -cne $Actual.candidate.commit -or
        $Expected.candidate.worktreeContentSha256 -cne $Actual.candidate.worktreeContentSha256) { throw 'Expected and actual image manifests are not bound to the same clean candidate.' }
    $expectedImages = @($Expected.images | Sort-Object { $_.service })
    $actualImages = @($Actual.images | Sort-Object { $_.service })
    if ($expectedImages.Count -ne 13 -or $actualImages.Count -ne 13 -or $expectedImages.Count -ne $actualImages.Count) {
        throw 'Expected and actual image manifests do not cover the same complete Phase 10 service set.'
    }
    for ($index = 0; $index -lt $expectedImages.Count; $index++) {
        if ($expectedImages[$index].service -cne $actualImages[$index].service -or
            $expectedImages[$index].project -cne 'xy-phase10' -or $actualImages[$index].project -cne 'xy-phase10' -or
            $expectedImages[$index].imageId -cne $actualImages[$index].imageId -or
            $expectedImages[$index].imageReference -cne $actualImages[$index].imageReference -or
            (@($expectedImages[$index].repositoryDigests | Sort-Object) -join "`n") -cne (@($actualImages[$index].repositoryDigests | Sort-Object) -join "`n")) {
            throw "Runtime image mismatch for Phase 10 service '$($expectedImages[$index].service)'."
        }
    }
}
