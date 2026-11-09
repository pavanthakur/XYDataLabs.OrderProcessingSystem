#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ProcedureEvidencePath,
    [switch]$ResetProcedureVerified,
    [switch]$ReinstallProcedureApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$source = 'F:\DockerStorage\DockerDesktopWSL'
$destination = 'F:\DockerRetained\DockerDesktopWSL-before-G'
$artifactRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults')).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($ManifestPath)).StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Use a manifest under repository TestResults; no evidence will be written elsewhere.' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.mode -ne 'BeforeSwitch' -or $manifest.status -ne 'passed' -or
    $manifest.configuredDiskLocation -ine $source -or $manifest.retainedPath -ine $destination) { throw 'A passed original F: BeforeSwitch manifest is required.' }
if ([bool]$ResetProcedureVerified -eq [bool]$ReinstallProcedureApproved) { throw 'Select exactly one: verified version-specific reset, or separately approved offline retention followed by reinstall. No purge safety is inferred from reinstall approval.' }
$evidence = Get-Item -LiteralPath $ProcedureEvidencePath
if ($evidence.PSIsContainer -or $evidence.Length -eq 0) { throw 'Provide a nonempty record of the verified procedure and installed Docker version.' }
if ((Get-Phase10DockerDiskLocation).TrimEnd('\') -ine $source) { throw 'Docker disk location changed since the manifest. Stop and review.' }
if (Test-Path -LiteralPath $destination) { throw 'Retention destination exists; refusing to overwrite.' }
if (-not (Test-Path -LiteralPath $source)) { throw 'Original F: directory is missing.' }

function Assert-NoReparseAncestor {
    param([string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed in retention source/destination paths.' }
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
Assert-NoReparseAncestor -Path $source
Assert-NoReparseAncestor -Path $destination
if ((Resolve-Path -LiteralPath $source).ProviderPath.TrimEnd('\') -ine $source) { throw 'Source did not resolve to the exact approved folder.' }
if (Get-Process -Name 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue) { throw 'Quit Docker Desktop completely before retaining its storage.' }
$runningWsl = (& wsl --list --running --quiet 2>&1 | Out-String).Replace([string][char]0, '').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify WSL shutdown; retention blocked.' }
# Unknown/localized output is not proof of shutdown. Fail closed, rather than recognizing
# only common distro names and accidentally moving an active custom distribution's disk.
if ($runningWsl -and $runningWsl -ne 'There are no running distributions.') { throw 'WSL shutdown cannot be established. Save all WSL work, then explicitly acknowledge and run wsl --shutdown.' }
$disks = @(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.vhdx')
if ($disks.Count -ne @($manifest.diskFiles).Count -or $disks.Count -eq 0) { throw 'Disk inventory changed; review before retention.' }
foreach ($disk in $disks) {
    Assert-NoReparseAncestor -Path $disk.FullName
    if ($disk.FullName -notin @($manifest.diskFiles.path)) { throw 'Unrecorded VHDX found; retention blocked.' }
}
$receiptPath = [IO.Path]::GetFullPath($ManifestPath) + '.retained.json'
Assert-NoReparseAncestor -Path $receiptPath
if (Test-Path -LiteralPath $receiptPath) { throw 'Retention receipt exists; refusing to overwrite.' }
if (-not $PSCmdlet.ShouldProcess("$source -> $destination", 'Retain offline Docker disk on the same F: volume (no purge)')) { return }

$handles = @()
try {
    foreach ($disk in $disks) { $handles += [IO.File]::Open($disk.FullName, 'Open', 'Read', 'None') }
}
finally { foreach ($handle in $handles) { $handle.Dispose() } }
$null = New-Item -ItemType Directory -Path 'F:\DockerRetained' -Force
Move-Item -LiteralPath $source -Destination $destination
$retainedDisks = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Filter '*.vhdx')
if (Test-Path -LiteralPath $source) { throw 'Original directory still exists. Do not reset Docker; review retention.' }
foreach ($disk in $disks) {
    $newPath = Join-Path $destination ([IO.Path]::GetRelativePath($source, $disk.FullName))
    if (-not (Test-Path -LiteralPath $newPath) -or (Get-Item -LiteralPath $newPath).Length -ne $disk.Length) { throw 'Retained disk size verification failed. Do not reset Docker.' }
}
[ordered]@{
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    originalPath = $source
    retainedPath = $destination
    procedureEvidenceSha256 = (Get-FileHash -LiteralPath $ProcedureEvidencePath -Algorithm SHA256).Hash
    initializationMethod = if ($ReinstallProcedureApproved) { 'approved-reinstall' } else { 'verified-reset' }
    resetProcedureVerified = [bool]$ResetProcedureVerified
    diskFiles = @($retainedDisks | ForEach-Object { @{ path = $_.FullName; bytes = $_.Length } })
    retentionVerified = $true
    recoveryTested = $false
    note = 'Procedure evidence recorded; offline rename and sizes checked, not a tested backup. Reinstall approval does not verify purge behavior.'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Write-Host "Retained disks verified. Receipt: $receiptPath. No Docker reset, G: migration, or deletion performed."
