#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$requiredConfig = @('Directory.Build.props','Directory.Packages.props','NuGet.Config','global.json')
foreach ($dockerfilePath in @('XYDataLabs.OrderProcessingSystem.Gateway/Dockerfile','XYDataLabs.OrderProcessingSystem.Functions/Dockerfile')) {
    $dockerfile = Get-Content -LiteralPath (Join-Path $root $dockerfilePath)
    $restoreLine = -1
    for ($lineIndex = 0; $lineIndex -lt $dockerfile.Count; $lineIndex++) { if ($dockerfile[$lineIndex] -match '^RUN dotnet restore') { $restoreLine = $lineIndex; break } }
    if ($restoreLine -lt 0) { throw "Dockerfile restore command was not found: $dockerfilePath" }
    foreach ($file in $requiredConfig) {
        $copyLine = -1
        for ($lineIndex = 0; $lineIndex -lt $dockerfile.Count; $lineIndex++) {
            if ($dockerfile[$lineIndex] -cmatch ('^COPY \["' + [regex]::Escape($file) + '"')) { $copyLine = $lineIndex; break }
        }
        if ($copyLine -lt 0 -or $copyLine -ge $restoreLine) { throw "$dockerfilePath restore does not receive central configuration '$file' first." }
    }
}
Write-Host 'PASS phase10-central-restore-inputs'

$nfrRunner = Join-Path $root 'scripts/run-phase10-docker-nfr-proof.ps1'
$missingManifest = Join-Path ([IO.Path]::GetTempPath()) ('missing-phase10-image-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
$withoutSkipOutput = @(& pwsh -NoProfile -File $nfrRunner -ExpectedImageManifest $missingManifest 2>&1)
$withoutSkipExit = $LASTEXITCODE
if ($withoutSkipExit -eq 0 -or (($withoutSkipOutput -join "`n") -notmatch 'requires -SkipStartIfNeeded')) {
    throw 'NFR expected-image mode did not require the existing-stack guard before runtime access.'
}
$missingOutput = @(& pwsh -NoProfile -File $nfrRunner -ExpectedImageManifest $missingManifest -SkipStartIfNeeded 2>&1)
$missingExit = $LASTEXITCODE
if ($missingExit -eq 0 -or (($missingOutput -join "`n") -notmatch 'manifest is missing')) {
    throw 'NFR did not reject a missing expected image manifest before runtime access.'
}
$dirtyManifest = Join-Path ([IO.Path]::GetTempPath()) ('dirty-phase10-image-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
$services = @('azurite','functions','gateway','inventory','keycloak-local','notifications','orders','payments','redis','servicebus-emulator','servicebus-sql','sql-server','ui')
$images = for ($index = 0; $index -lt $services.Count; $index++) {
    @{ project='xy-phase10'; service=$services[$index]; containerId=$index.ToString('x').PadLeft(12,'0');
        imageReference="$($services[$index]):dev"; imageId=('sha256:' + ($index + 1).ToString('x').PadLeft(64,'0')); repositoryDigests=@() }
}
@{ schema='phase10-docker-image-identities-v1'; runId='phase10-docker-http-20261111-000000001'; capturePoint='before';
    candidate=@{ commit=('a' * 40); worktree='dirty'; dirtyStatusSha256=('b' * 64) }; buildLogsSha256=@{}; images=@($images) } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dirtyManifest
try {
    $dirtyOutput = @(& pwsh -NoProfile -File $nfrRunner -ExpectedImageManifest $dirtyManifest -SkipStartIfNeeded 2>&1)
    $dirtyExit = $LASTEXITCODE
    if ($dirtyExit -eq 0 -or (($dirtyOutput -join "`n") -notmatch 'must be bound to a clean candidate')) {
        throw 'NFR did not reject a dirty expected image manifest during preflight.'
    }
} finally { Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dirtyManifest -Force -ErrorAction SilentlyContinue }
Write-Host 'PASS dirty-expected-manifest-rejected-before-docker'
Write-Host 'PASS nfr-expected-manifest-preflight-before-docker'

$e2eRunner = Get-Content -LiteralPath (Join-Path $root 'scripts/run-phase10-local-container-stack-end-to-end.ps1') -Raw
$startupCapture = $e2eRunner.IndexOf("-CapturePoint before", [StringComparison]::Ordinal)
$persistenceGate = $e2eRunner.IndexOf("test-phase10-docker-persistence.ps1", [StringComparison]::Ordinal)
$finalCapture = $e2eRunner.IndexOf("-CapturePoint after", [StringComparison]::Ordinal)
if ($startupCapture -lt 0 -or $persistenceGate -le $startupCapture -or $finalCapture -le $persistenceGate) {
    throw 'The final image inventory must be captured after the optional persistence/restart gate.'
}
Write-Host 'PASS persistence-before-final-image-capture'

. (Join-Path $root 'scripts/phase10-docker-image-evidence.ps1')
$gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
$script:serviceNames = @('sql-server','redis','azurite','servicebus-sql','servicebus-emulator','keycloak-local','orders','payments','inventory','notifications','gateway','ui','functions')
$script:currentService = $null
$script:changeInventoryImage = $false
function docker {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'compose' -and $args -contains 'config') { return $script:serviceNames }
    if ($args[0] -eq 'compose' -and $args -contains 'ps') {
        $script:currentService = [string]$args[-1]
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($script:currentService))).ToLowerInvariant().Substring(0,12)
    }
    if ($args[0] -eq 'inspect' -and $args -contains '--type') {
        $service = $script:currentService
        $id = if ($script:changeInventoryImage -and $service -eq 'inventory') { 'sha256:' + ('f' * 64) }
            else { 'sha256:' + ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($service))).ToLowerInvariant().PadLeft(64,'0').Substring(0,64)) }
        return (@(@{ Image=$id; Config=@{ Image="$service`:dev"; Labels=@{
            'com.docker.compose.project'='xy-phase10'; 'com.docker.compose.service'=$service } } } | ConvertTo-Json -Depth 5))
    }
    if ($args[0] -eq 'image' -and $args[1] -eq 'inspect') {
        return (@(@{ RepoDigests=@() } | ConvertTo-Json -Depth 3))
    }
    throw "Unexpected mocked Docker invocation: $($args -join ' ')"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('phase10-image-evidence-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $workspace = Join-Path $temp 'clean-workspace'
    [void][IO.Directory]::CreateDirectory($workspace)
    & $gitCommand.Source -C $workspace init --quiet
    & $gitCommand.Source -C $workspace config user.email 'phase10-test@example.invalid'
    & $gitCommand.Source -C $workspace config user.name 'Phase10 test'
    Set-Content -LiteralPath (Join-Path $workspace 'baseline.txt') -Value 'baseline' -NoNewline
    & $gitCommand.Source -C $workspace add -- baseline.txt
    & $gitCommand.Source -C $workspace commit --quiet -m 'baseline'
    $beforePath = Join-Path $temp 'before.json'
    $afterPath = Join-Path $temp 'after.json'
    $arguments = @{ RunId='phase10-docker-http-20261111-000000001'; OutputPath=$beforePath; ComposeFile='compose.yml';
        EnvExampleFile='example.env'; EnvFile='local.env'; WorkspaceRoot=$workspace; ArtifactRoot=$temp }
    $before = Get-Phase10DockerImageManifest @arguments -CapturePoint before
    $afterArguments = $arguments.Clone()
    $afterArguments.OutputPath = $afterPath
    $after = Get-Phase10DockerImageManifest @afterArguments -CapturePoint after
    $readBack = Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json
    if ($readBack.images.Count -ne 13 -or $readBack.capturePoint -ne 'before') { throw 'Captured manifest is incomplete.' }
    if ($readBack.candidate.changedPaths -isnot [array] -or $readBack.candidate.changedPaths.Count -ne 0) {
        throw 'A clean candidate must serialize changedPaths as an empty JSON array.'
    }
    $readBack.candidate.worktree = 'clean'
    $readBack.candidate.dirtyStatusSha256 = $null
    $before.candidate.worktree = 'clean'
    $before.candidate.dirtyStatusSha256 = $null
    $before.candidate.worktreeContentSha256 = $null
    $before.candidate.changedPaths = @()
    $readBack.candidate.worktreeContentSha256 = $null
    $readBack.candidate.changedPaths = @()
    Assert-Phase10DockerImageManifestMatches -Expected $readBack -Actual $before
    Write-Host 'PASS live-ordered-manifest-matches-json-manifest'
    $beforeComparable = $readBack
    $afterComparable = Get-Content -LiteralPath $afterPath -Raw | ConvertFrom-Json
    $beforeComparable.candidate.worktree = 'clean'
    $beforeComparable.candidate.dirtyStatusSha256 = $null
    $beforeComparable.candidate.worktreeContentSha256 = $null
    $beforeComparable.candidate.changedPaths = @()
    $afterComparable.candidate.worktree = 'clean'
    $afterComparable.candidate.dirtyStatusSha256 = $null
    $afterComparable.candidate.worktreeContentSha256 = $null
    $afterComparable.candidate.changedPaths = @()
    $beforeShape = Test-Phase10DockerImageManifestShape -Manifest $beforeComparable -ExpectedCapturePoint before
    $afterShape = Test-Phase10DockerImageManifestShape -Manifest $afterComparable -ExpectedCapturePoint after
    if (-not (Test-Phase10DockerImageManifestsMatch -Before $beforeComparable -After $afterComparable)) {
        throw "Matching image inventories were not accepted (beforeShape=$beforeShape, afterShape=$afterShape, beforeRun=$($beforeComparable.runId), afterRun=$($afterComparable.runId), beforeWorktree=$($beforeComparable.candidate.worktree), afterWorktree=$($afterComparable.candidate.worktree))."
    }
    $afterComparable.images | Where-Object service -eq 'inventory' | ForEach-Object { $_.imageId = 'sha256:' + ('f' * 64) }
    if (Test-Phase10DockerImageManifestsMatch -Before $beforeComparable -After $afterComparable) { throw 'Image mismatch was not rejected.' }
    Write-Host 'PASS mocked-project-ownership-and-image-capture'
    Write-Host 'PASS image-change-detection'

    $identityRepo = Join-Path $temp 'identity-repo'
    [void][IO.Directory]::CreateDirectory($identityRepo)
    & $gitCommand.Source -C $identityRepo init --quiet
    & $gitCommand.Source -C $identityRepo config user.email 'phase10-test@example.invalid'
    & $gitCommand.Source -C $identityRepo config user.name 'Phase10 test'
    Set-Content -LiteralPath (Join-Path $identityRepo 'tracked.txt') -Value 'base' -NoNewline
    & $gitCommand.Source -C $identityRepo add -- tracked.txt
    & $gitCommand.Source -C $identityRepo commit --quiet -m 'base'
    Set-Content -LiteralPath (Join-Path $identityRepo 'tracked.txt') -Value 'changed' -NoNewline
    Set-Content -LiteralPath (Join-Path $identityRepo 'untracked.txt') -Value 'first' -NoNewline
    $identityOne = Get-Phase10WorktreeContentIdentity -WorkspaceRoot $identityRepo -GitCommand $gitCommand
    Set-Content -LiteralPath (Join-Path $identityRepo 'untracked.txt') -Value 'second' -NoNewline
    $identityTwo = Get-Phase10WorktreeContentIdentity -WorkspaceRoot $identityRepo -GitCommand $gitCommand
    if ($identityOne.sha256 -eq $identityTwo.sha256 -or 'untracked.txt' -notin $identityOne.changedPaths) {
        throw 'Worktree content identity must cover changed tracked and untracked file contents.'
    }
    Write-Host 'PASS dirty-worktree-content-identity-includes-untracked-files'
} finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
