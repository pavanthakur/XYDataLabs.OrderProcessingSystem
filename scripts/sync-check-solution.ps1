#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that maintained solution-item surfaces stay in sync with the VS solution file.

.DESCRIPTION
    Validates both file registration and solution-folder hierarchy for maintained surfaces.
    A surface is only considered in sync when:
      - files on disk are registered in the solution,
      - stale entries are not present in the solution,
      - files are placed under the correct solution folder path,
      - expected solution folder chains exist.

    This prevents false positives where the .sln still contains the right file path but shows
    it under the wrong logical folder in Solution Explorer.

.EXAMPLE
    .\scripts\sync-check-solution.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$slnPath  = Join-Path $repoRoot 'XYDataLabs.OrderProcessingSystem.sln'

if (-not (Test-Path $slnPath)) {
    Write-Error "Solution file not found: $slnPath"
    exit 1
}

$slnContent = Get-Content $slnPath -Raw

$solutionFolderTypeGuid = '{2150E333-8FDC-42A3-9474-1A3956D46DE8}'

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $normalized = $Path -replace '/', '\'
    if ($normalized.StartsWith('.\')) {
        $normalized = $normalized.Substring(2)
    }

    return $normalized
}

function Add-UniqueListItem {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$List,

        [Parameter(Mandatory)]
        [string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value)
    }
}

function Get-SolutionFolderPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectGuid,

        [Parameter(Mandatory)]
        [hashtable]$Projects,

        [Parameter(Mandatory)]
        [hashtable]$NestedParents
    )

    $segments = [System.Collections.Generic.List[string]]::new()
    $currentGuid = $ProjectGuid

    while ($currentGuid) {
        if (-not $Projects.ContainsKey($currentGuid)) {
            break
        }

        $project = $Projects[$currentGuid]
        if ($project.TypeGuid -ne $solutionFolderTypeGuid) {
            break
        }

        $segments.Insert(0, $project.Name)

        if ($NestedParents.ContainsKey($currentGuid)) {
            $currentGuid = $NestedParents[$currentGuid]
            continue
        }

        break
    }

    return ($segments -join '\')
}

function Get-ExpectedProjectFolderPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    if ($ProjectPath -eq 'Resources\Docker\docker-compose.dcproj') {
        return 'Resources\Docker'
    }

    if ($ProjectPath -like 'tests\*') {
        return 'tests'
    }

    return $null
}

function Get-ParentSolutionFolderPath {
    param(
        [Parameter(Mandatory)]
        [psobject]$Project,

        [Parameter(Mandatory)]
        [hashtable]$Projects,

        [Parameter(Mandatory)]
        [hashtable]$NestedParents
    )

    if (-not $NestedParents.ContainsKey($Project.Guid)) {
        return $null
    }

    $parentGuid = $NestedParents[$Project.Guid]
    if (-not $Projects.ContainsKey($parentGuid)) {
        return $null
    }

    if ($Projects[$parentGuid].TypeGuid -ne $solutionFolderTypeGuid) {
        return $null
    }

    return (Get-SolutionFolderPath -ProjectGuid $parentGuid -Projects $Projects -NestedParents $NestedParents)
}

function Test-ExcludedRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirectoryNames,

        [Parameter(Mandatory)]
        [string[]]$ExcludedPathPrefixes
    )

    foreach ($excludedPathPrefix in $ExcludedPathPrefixes) {
        if ($RelativePath -eq $excludedPathPrefix -or $RelativePath.StartsWith("$excludedPathPrefix\")) {
            return $true
        }
    }

    foreach ($segment in ($RelativePath -split '\\')) {
        if ($ExcludedDirectoryNames -contains $segment) {
            return $true
        }
    }

    return $false
}

function Get-MirroredFilesystemState {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    $mirroredRootFolders = @('.github', 'Resources', 'Documentation', 'docs', 'infra', 'bicep', 'scripts')
    $excludedDirectoryNames = @('bin', 'obj', '.git', '.vs', '.vscode', 'node_modules')
    $excludedPathPrefixes = @('Resources\Azure-Deployment\logs')
    $excludedExtensions = @('.log', '.tmp', '.bak', '.user', '.zip', '.csproj', '.dcproj')
    $excludedFileNames = @('.env.local', 'XYDataLabs.OrderProcessingSystem.sln')
    $mirroredFiles = [System.Collections.Generic.List[string]]::new()
    $mirroredFolders = [System.Collections.Generic.List[string]]::new()

    $rootFiles = Get-ChildItem -Path $RepositoryRoot -Force -File
    foreach ($rootFile in $rootFiles) {
        if ($excludedFileNames -contains $rootFile.Name -or $excludedExtensions -contains $rootFile.Extension.ToLowerInvariant()) {
            continue
        }

        Add-UniqueListItem -List $mirroredFiles -Value $rootFile.Name
    }

    foreach ($mirroredRootFolder in $mirroredRootFolders) {
        $absoluteMirroredRoot = Join-Path $RepositoryRoot $mirroredRootFolder
        if (-not (Test-Path $absoluteMirroredRoot)) {
            continue
        }

        Add-UniqueListItem -List $mirroredFolders -Value $mirroredRootFolder

        $directories = Get-ChildItem -Path $absoluteMirroredRoot -Force -Recurse -Directory
        foreach ($directory in $directories) {
            $relativeDirectoryPath = Normalize-RelativePath -Path $directory.FullName.Substring($RepositoryRoot.Length + 1)
            if (Test-ExcludedRelativePath -RelativePath $relativeDirectoryPath -ExcludedDirectoryNames $excludedDirectoryNames -ExcludedPathPrefixes $excludedPathPrefixes) {
                continue
            }

            Add-UniqueListItem -List $mirroredFolders -Value $relativeDirectoryPath
        }

        $files = Get-ChildItem -Path $absoluteMirroredRoot -Force -Recurse -File
        foreach ($file in $files) {
            $relativeFilePath = Normalize-RelativePath -Path $file.FullName.Substring($RepositoryRoot.Length + 1)
            if (Test-ExcludedRelativePath -RelativePath $relativeFilePath -ExcludedDirectoryNames $excludedDirectoryNames -ExcludedPathPrefixes $excludedPathPrefixes) {
                continue
            }

            if ($excludedFileNames -contains $file.Name -or $excludedExtensions -contains $file.Extension.ToLowerInvariant()) {
                continue
            }

            Add-UniqueListItem -List $mirroredFiles -Value $relativeFilePath
        }
    }

    return [pscustomobject]@{
        Files   = $mirroredFiles
        Folders = $mirroredFolders
    }
}

$projects = @{}
$nestedParents = @{}
$slnLines = Get-Content $slnPath

for ($lineIndex = 0; $lineIndex -lt $slnLines.Count; $lineIndex++) {
    $line = $slnLines[$lineIndex]

    if ($line -match '^Project\("(?<typeGuid>\{[^"]+\})"\) = "(?<name>[^"]+)", "(?<path>[^"]+)", "(?<guid>\{[^\}]+\})"$') {
        $projectGuid = $Matches.guid.ToUpperInvariant()
        $projectTypeGuid = $Matches.typeGuid.ToUpperInvariant()
        $projectName = $Matches.name
        $projectPath = Normalize-RelativePath -Path $Matches.path
        $solutionItems = [System.Collections.Generic.List[string]]::new()
        $insideSolutionItems = $false

        for ($projectLineIndex = $lineIndex + 1; $projectLineIndex -lt $slnLines.Count; $projectLineIndex++) {
            $projectLine = $slnLines[$projectLineIndex]

            if ($projectLine -match '^\s*ProjectSection\(SolutionItems\)\s*=\s*preProject$') {
                $insideSolutionItems = $true
                continue
            }

            if ($projectLine -match '^\s*EndProjectSection$') {
                $insideSolutionItems = $false
                continue
            }

            if ($projectLine -match '^EndProject$') {
                $lineIndex = $projectLineIndex
                break
            }

            if ($insideSolutionItems -and $projectLine -match '^\s*(?<path>[^=\r\n]+?)\s*=') {
                $solutionItems.Add((Normalize-RelativePath -Path $Matches.path))
            }
        }

        $projects[$projectGuid] = [pscustomobject]@{
            Guid          = $projectGuid
            TypeGuid      = $projectTypeGuid
            Name          = $projectName
            Path          = $projectPath
            SolutionItems = $solutionItems
        }

        continue
    }

    if ($line -match '^\s*GlobalSection\(NestedProjects\)\s*=\s*preSolution$') {
        for ($nestedLineIndex = $lineIndex + 1; $nestedLineIndex -lt $slnLines.Count; $nestedLineIndex++) {
            $nestedLine = $slnLines[$nestedLineIndex]
            if ($nestedLine -match '^\s*EndGlobalSection$') {
                $lineIndex = $nestedLineIndex
                break
            }

            if ($nestedLine -match '^\s*(?<child>\{[^\}]+\})\s*=\s*(?<parent>\{[^\}]+\})\s*$') {
                $nestedParents[$Matches.child.ToUpperInvariant()] = $Matches.parent.ToUpperInvariant()
            }
        }
    }
}

$solutionFoldersByPath = @{}
$solutionItemLocations = @{}

foreach ($project in $projects.Values) {
    if ($project.TypeGuid -ne $solutionFolderTypeGuid) {
        continue
    }

    $solutionFolderPath = Get-SolutionFolderPath -ProjectGuid $project.Guid -Projects $projects -NestedParents $nestedParents
    $solutionFoldersByPath[$solutionFolderPath] = $project

    foreach ($solutionItem in $project.SolutionItems) {
        if (-not $solutionItemLocations.ContainsKey($solutionItem)) {
            $solutionItemLocations[$solutionItem] = [System.Collections.Generic.List[string]]::new()
        }

        $solutionItemLocations[$solutionItem].Add($solutionFolderPath)
    }
}

$mirroredFilesystemState = Get-MirroredFilesystemState -RepositoryRoot $repoRoot
$trackedRepositoryFiles = $mirroredFilesystemState.Files
$expectedFolderPaths = [System.Collections.Generic.List[string]]::new()

foreach ($mirroredFolder in $mirroredFilesystemState.Folders) {
    Add-UniqueListItem -List $expectedFolderPaths -Value ([string]$mirroredFolder)
}

Add-UniqueListItem -List $expectedFolderPaths -Value 'Solution Items'
Add-UniqueListItem -List $expectedFolderPaths -Value 'tests'
$expectedFileLocations = @{}

foreach ($trackedRepositoryFile in $trackedRepositoryFiles) {
    $expectedFolderPath = [System.IO.Path]::GetDirectoryName([string]$trackedRepositoryFile)
    if (-not [string]::IsNullOrEmpty($expectedFolderPath)) {
        $expectedFolderPath = Normalize-RelativePath -Path $expectedFolderPath
    }

    if ([string]::IsNullOrEmpty($expectedFolderPath)) {
        $expectedFolderPath = 'Solution Items'
    }

    $expectedFileLocations[[string]$trackedRepositoryFile] = $expectedFolderPath
}

$missing = [System.Collections.Generic.List[string]]::new()
$stale = [System.Collections.Generic.List[string]]::new()
$misplaced = [System.Collections.Generic.List[string]]::new()
$missingFolders = [System.Collections.Generic.List[string]]::new()
$unexpectedFolderEntries = [System.Collections.Generic.List[string]]::new()
$unexpectedFolders = [System.Collections.Generic.List[string]]::new()
$misplacedProjects = [System.Collections.Generic.List[string]]::new()

foreach ($expectedFolderPath in $expectedFolderPaths) {
    if (-not $solutionFoldersByPath.ContainsKey($expectedFolderPath)) {
        Add-UniqueListItem -List $missingFolders -Value $expectedFolderPath
    }
}

foreach ($trackedRepositoryFile in $trackedRepositoryFiles) {
    $expectedFolderPath = $expectedFileLocations[[string]$trackedRepositoryFile]

    if (-not $solutionItemLocations.ContainsKey([string]$trackedRepositoryFile)) {
        Add-UniqueListItem -List $missing -Value ([string]$trackedRepositoryFile)
        continue
    }

    $registeredFolders = @($solutionItemLocations[[string]$trackedRepositoryFile])
    if ($registeredFolders -notcontains $expectedFolderPath) {
        Add-UniqueListItem -List $misplaced -Value ("{0} -> {1}" -f [string]$trackedRepositoryFile, ($registeredFolders -join ', '))
    }
}

foreach ($solutionFolderPath in ($solutionFoldersByPath.Keys | Sort-Object)) {
    $topLevelSegment = $solutionFolderPath.Split('\')[0]
    $isTrackedSolutionFolder = $solutionFolderPath -eq 'Solution Items' -or @('.github', 'Resources', 'Documentation', 'docs', 'infra', 'bicep', 'scripts', 'tests') -contains $topLevelSegment

    if (-not $isTrackedSolutionFolder) {
        continue
    }

    if ($expectedFolderPaths -notcontains $solutionFolderPath) {
        Add-UniqueListItem -List $unexpectedFolders -Value $solutionFolderPath
        continue
    }

    foreach ($entry in ($solutionFoldersByPath[$solutionFolderPath].SolutionItems | Sort-Object -Unique)) {
        if (-not $expectedFileLocations.ContainsKey($entry)) {
            Add-UniqueListItem -List $stale -Value $entry
            continue
        }

        if ($expectedFileLocations[$entry] -ne $solutionFolderPath) {
            Add-UniqueListItem -List $unexpectedFolderEntries -Value ("{0} -> {1}" -f $entry, $solutionFolderPath)
        }
    }
}

foreach ($project in $projects.Values) {
    if ($project.TypeGuid -eq $solutionFolderTypeGuid) {
        continue
    }

    $expectedProjectFolderPath = Get-ExpectedProjectFolderPath -ProjectPath $project.Path
    if ([string]::IsNullOrEmpty($expectedProjectFolderPath)) {
        continue
    }

    $actualProjectFolderPath = Get-ParentSolutionFolderPath -Project $project -Projects $projects -NestedParents $nestedParents
    if ($actualProjectFolderPath -ne $expectedProjectFolderPath) {
        Add-UniqueListItem -List $misplacedProjects -Value ("{0} -> {1}" -f $project.Path, ($actualProjectFolderPath ?? '<root>'))
    }
}

if ($missing.Count -gt 0 -or $stale.Count -gt 0 -or $misplaced.Count -gt 0 -or $missingFolders.Count -gt 0 -or $unexpectedFolderEntries.Count -gt 0 -or $unexpectedFolders.Count -gt 0 -or $misplacedProjects.Count -gt 0) {
    Write-Host ''
    Write-Host 'Solution sync check FAILED — tracked repository structure and .sln hierarchy are out of sync:' -ForegroundColor Red

    if ($missingFolders.Count -gt 0) {
        Write-Host 'Expected solution folder chains missing from .sln:' -ForegroundColor Yellow
        foreach ($item in ($missingFolders | Sort-Object)) {
            Write-Host "  FOLDER   $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($missing.Count -gt 0) {
        Write-Host 'Files on disk not registered in .sln:' -ForegroundColor Yellow
        foreach ($item in ($missing | Sort-Object)) {
            Write-Host "  MISSING  $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($unexpectedFolders.Count -gt 0) {
        Write-Host 'Solution folders present in .sln but not backed by tracked repository structure:' -ForegroundColor Yellow
        foreach ($item in ($unexpectedFolders | Sort-Object)) {
            Write-Host "  EXTRA    $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($stale.Count -gt 0) {
        Write-Host 'Entries still present in .sln but missing on disk:' -ForegroundColor Yellow
        foreach ($item in ($stale | Sort-Object)) {
            Write-Host "  STALE    $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($misplaced.Count -gt 0) {
        Write-Host 'Files registered in .sln under the wrong solution folder:' -ForegroundColor Yellow
        foreach ($item in ($misplaced | Sort-Object)) {
            Write-Host "  MISPLACED $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($unexpectedFolderEntries.Count -gt 0) {
        Write-Host 'Solution folders containing entries from a different physical directory:' -ForegroundColor Yellow
        foreach ($item in ($unexpectedFolderEntries | Sort-Object)) {
            Write-Host "  WRONGDIR $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($misplacedProjects.Count -gt 0) {
        Write-Host 'Projects nested under the wrong solution folder:' -ForegroundColor Yellow
        foreach ($item in ($misplacedProjects | Sort-Object)) {
            Write-Host "  PROJECT  $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    Write-Host 'Fix: mirror tracked repository folders/files in the .sln, move entries to the correct ProjectSection(SolutionItems) block, and correct project nesting in XYDataLabs.OrderProcessingSystem.sln.' -ForegroundColor Cyan
    exit 1
}

Write-Host 'Solution sync check PASSED — tracked repository structure and .sln hierarchy are in sync.' -ForegroundColor Green
exit 0
