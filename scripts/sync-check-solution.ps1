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

# Maintained surfaces — relative to repo root and expected Solution Explorer folder path.
# Checks are intentionally non-recursive per surface; nested surfaces are declared separately.
$trackedSurfaces = @(
    @{ Path = '.github'; SolutionFolderPath = @('.github') }
    @{ Path = '.github\agents'; SolutionFolderPath = @('.github', 'agents') }
    @{ Path = '.github\instructions'; SolutionFolderPath = @('.github', 'instructions') }
    @{ Path = '.github\prompts'; SolutionFolderPath = @('.github', 'prompts') }
    @{ Path = '.github\workflows'; SolutionFolderPath = @('.github', 'workflows') }
    @{ Path = 'scripts'; SolutionFolderPath = @('scripts') }
    @{ Path = 'Resources\Azure-Deployment'; SolutionFolderPath = @('Resources', 'Azure-Deployment') }
    @{ Path = 'Resources\BuildConfiguration'; SolutionFolderPath = @('Resources', 'BuildConfiguration') }
    @{ Path = 'Resources\Certificates'; SolutionFolderPath = @('Resources', 'Certificates') }
    @{ Path = 'Resources\Configuration'; SolutionFolderPath = @('Resources', 'Configuration') }
    @{ Path = 'Resources\Docker'; SolutionFolderPath = @('Resources', 'Docker') }
    @{ Path = 'Documentation'; SolutionFolderPath = @('Documentation') }
    @{ Path = 'Documentation\05-Self-Learning\Azure-Curriculum'; SolutionFolderPath = @('Documentation', '05-Self-Learning', 'Azure-Curriculum') }
    @{ Path = 'docs'; SolutionFolderPath = @('docs') }
    @{ Path = 'docs\architecture\decisions'; SolutionFolderPath = @('docs', 'architecture', 'decisions') }
    @{ Path = 'docs\internal'; SolutionFolderPath = @('docs', 'internal') }
    @{ Path = 'docs\archive'; SolutionFolderPath = @('docs', 'archive') }
    @{ Path = 'docs\archive\historical-notes\internal'; SolutionFolderPath = @('docs', 'archive', 'historical-notes', 'internal') }
    @{ Path = 'docs\runbooks'; SolutionFolderPath = @('docs', 'runbooks') }
    @{ Path = 'infra'; SolutionFolderPath = @('infra') }
    @{ Path = 'infra\parameters'; SolutionFolderPath = @('infra', 'parameters') }
    @{ Path = 'infra\modules'; SolutionFolderPath = @('infra', 'modules') }
    @{ Path = 'bicep'; SolutionFolderPath = @('bicep') }
    @{ Path = 'bicep\parameters'; SolutionFolderPath = @('bicep', 'parameters') }
)

# File extensions to ignore — generated outputs, not source files
$excludeExtensions = @('.log', '.tmp', '.bak', '.user', '.dcproj')
$excludeFileNames = @('.env.local')

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

$missing = [System.Collections.Generic.List[string]]::new()
$stale = [System.Collections.Generic.List[string]]::new()
$misplaced = [System.Collections.Generic.List[string]]::new()
$missingFolders = [System.Collections.Generic.List[string]]::new()
$unexpectedFolderEntries = [System.Collections.Generic.List[string]]::new()

foreach ($surface in $trackedSurfaces) {
    $relDir = Normalize-RelativePath -Path $surface.Path
    $expectedSolutionFolderPath = ($surface.SolutionFolderPath -join '\')
    $absDir = Join-Path $repoRoot $relDir

    if (-not (Test-Path $absDir)) { continue }

    if (-not $solutionFoldersByPath.ContainsKey($expectedSolutionFolderPath)) {
        Add-UniqueListItem -List $missingFolders -Value $expectedSolutionFolderPath
    }

    $files = Get-ChildItem -Path $absDir -File |
             Where-Object {
                 $excludeExtensions -notcontains $_.Extension.ToLower() -and
                 $excludeFileNames -notcontains $_.Name
             } |
             Select-Object -ExpandProperty Name

    foreach ($file in $files) {
        $slnEntry = "$relDir\$file"

        if ($solutionItemLocations.ContainsKey($slnEntry)) {
            $registeredFolders = @($solutionItemLocations[$slnEntry])

            if ($registeredFolders -contains $expectedSolutionFolderPath) {
                continue
            }

            Add-UniqueListItem -List $misplaced -Value ("{0} -> {1}" -f $slnEntry, ($registeredFolders -join ', '))
            continue
        }

        Add-UniqueListItem -List $missing -Value $slnEntry
    }

    if (-not $solutionFoldersByPath.ContainsKey($expectedSolutionFolderPath)) {
        continue
    }

    foreach ($entry in ($solutionFoldersByPath[$expectedSolutionFolderPath].SolutionItems | Sort-Object -Unique)) {
        $entryPath = Join-Path $repoRoot $entry
        if (-not (Test-Path $entryPath)) {
            Add-UniqueListItem -List $stale -Value $entry
            continue
        }

        $entryDir = Normalize-RelativePath -Path ([System.IO.Path]::GetDirectoryName($entry))
        if ($entryDir -ne $relDir) {
            Add-UniqueListItem -List $unexpectedFolderEntries -Value ("{0} -> {1}" -f $entry, $expectedSolutionFolderPath)
        }
    }
}

if ($missing.Count -gt 0 -or $stale.Count -gt 0 -or $misplaced.Count -gt 0 -or $missingFolders.Count -gt 0 -or $unexpectedFolderEntries.Count -gt 0) {
    Write-Host ''
    Write-Host 'Solution sync check FAILED — tracked solution-item surfaces are out of sync:' -ForegroundColor Red

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

    Write-Host 'Fix: add missing solution folders, move entries to the correct ProjectSection(SolutionItems) block, and remove stale paths from XYDataLabs.OrderProcessingSystem.sln.' -ForegroundColor Cyan
    exit 1
}

Write-Host 'Solution sync check PASSED — tracked solution-item surfaces and solution-folder hierarchy are in sync with .sln.' -ForegroundColor Green
exit 0
