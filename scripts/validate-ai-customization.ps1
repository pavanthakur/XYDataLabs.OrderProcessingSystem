#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates repo-shared AI customization assets and their discovery surfaces.

.DESCRIPTION
    Checks the shared Copilot operating surfaces for minimum enterprise governance consistency:
      - required governance files exist
      - instruction files contain frontmatter with applyTo
    - prompt, agent, and skill files contain frontmatter with description
    - prompts, agents, and skills are discoverable from README/index surfaces
      - completion-check references the rubric and deferred-work register
      - operating and workflow/script docs reference the new validator surfaces

.PARAMETER RepositoryRoot
    Optional repository root. Defaults to the parent of the scripts directory.

.EXAMPLE
    pwsh scripts/validate-ai-customization.ps1
#>

param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $script:failures.Add($Message)
}

function Get-FileText {
    param([string]$RelativePath)

    $fullPath = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path $fullPath)) {
        Add-Failure("Missing required file: $RelativePath")
        return $null
    }

    return Get-Content -Path $fullPath -Raw
}

function Get-Frontmatter {
    param([string]$FilePath)

    $lines = Get-Content -Path $FilePath
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
        return $null
    }

    $endIndex = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq '---') {
            $endIndex = $index
            break
        }
    }

    if ($endIndex -lt 1) {
        return $null
    }

    return ($lines[1..($endIndex - 1)] -join "`n")
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Needle,
        [string]$FailureMessage
    )

    if ([string]::IsNullOrWhiteSpace($Content) -or $Content -notmatch [regex]::Escape($Needle)) {
        Add-Failure($FailureMessage)
    }
}

$requiredFiles = @(
    'docs/AI-OPERATING-MODEL.md',
    'docs/internal/DEFERRED-WORK-LOG.md',
    '.github/completion-check-rubric.md',
    '.github/prompts/README.md',
    '.github/skills/README.md',
    '.github/copilot-instructions.md',
    '.github/workflows/README.md',
    'scripts/README.md',
    'scripts/validate-ai-customization.ps1'
)

foreach ($relativePath in $requiredFiles) {
    $null = Get-FileText -RelativePath $relativePath
}

$copilotInstructions = Get-FileText -RelativePath '.github/copilot-instructions.md'
$promptReadme = Get-FileText -RelativePath '.github/prompts/README.md'
$skillReadme = Get-FileText -RelativePath '.github/skills/README.md'
$workflowReadme = Get-FileText -RelativePath '.github/workflows/README.md'
$scriptReadme = Get-FileText -RelativePath 'scripts/README.md'
$operatingModel = Get-FileText -RelativePath 'docs/AI-OPERATING-MODEL.md'
$completionCheckPrompt = Get-FileText -RelativePath '.github/prompts/XYDataLabs-completion-check.prompt.md'

$instructionFiles = Get-ChildItem -Path (Join-Path $RepositoryRoot '.github/instructions') -Filter '*.instructions.md' | Sort-Object Name
$promptFiles = Get-ChildItem -Path (Join-Path $RepositoryRoot '.github/prompts') -Filter '*.prompt.md' | Sort-Object Name
$agentFiles = Get-ChildItem -Path (Join-Path $RepositoryRoot '.github/agents') -Filter '*.agent.md' | Sort-Object Name
$skillFiles = Get-ChildItem -Path (Join-Path $RepositoryRoot '.github/skills') -Recurse -Filter 'SKILL.md' | Sort-Object FullName

foreach ($file in $instructionFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.Name): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^applyTo\s*:') {
        Add-Failure("$($file.Name): frontmatter must include applyTo")
    }
}

foreach ($file in $promptFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.Name): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^description\s*:') {
        Add-Failure("$($file.Name): frontmatter must include description")
    }

    $promptCommand = '/' + $file.BaseName.Replace('.prompt', '')
    Assert-Contains -Content $promptReadme -Needle $promptCommand -FailureMessage "$($file.Name): missing from .github/prompts/README.md"
    Assert-Contains -Content $copilotInstructions -Needle $promptCommand -FailureMessage "$($file.Name): missing from .github/copilot-instructions.md"
}

foreach ($file in $agentFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.Name): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^description\s*:') {
        Add-Failure("$($file.Name): frontmatter must include description")
    }

    Assert-Contains -Content $promptReadme -Needle $file.Name -FailureMessage "$($file.Name): missing from .github/prompts/README.md"
    Assert-Contains -Content $copilotInstructions -Needle $file.Name -FailureMessage "$($file.Name): missing from .github/copilot-instructions.md"
}

foreach ($file in $skillFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^name\s*:') {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): frontmatter must include name")
    }

    if ($frontmatter -notmatch '(?m)^description\s*:') {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): frontmatter must include description")
    }

    $skillFolder = Split-Path -Path $file.DirectoryName -Leaf
    Assert-Contains -Content $skillReadme -Needle $skillFolder -FailureMessage "$($file.FullName.Substring($RepositoryRoot.Length + 1)): missing from .github/skills/README.md"
    Assert-Contains -Content $copilotInstructions -Needle $skillFolder -FailureMessage "$($file.FullName.Substring($RepositoryRoot.Length + 1)): missing from .github/copilot-instructions.md"
}

Assert-Contains -Content $completionCheckPrompt -Needle '.github/completion-check-rubric.md' -FailureMessage 'Completion-check prompt must reference .github/completion-check-rubric.md'
Assert-Contains -Content $completionCheckPrompt -Needle 'docs/internal/DEFERRED-WORK-LOG.md' -FailureMessage 'Completion-check prompt must reference docs/internal/DEFERRED-WORK-LOG.md'

Assert-Contains -Content $operatingModel -Needle '.github/copilot-instructions.md' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference .github/copilot-instructions.md'
Assert-Contains -Content $operatingModel -Needle '.github/prompts/README.md' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference .github/prompts/README.md'
Assert-Contains -Content $operatingModel -Needle '.github/skills/README.md' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference .github/skills/README.md'
Assert-Contains -Content $operatingModel -Needle '.github/completion-check-rubric.md' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference .github/completion-check-rubric.md'
Assert-Contains -Content $operatingModel -Needle 'docs/internal/DEFERRED-WORK-LOG.md' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference docs/internal/DEFERRED-WORK-LOG.md'
Assert-Contains -Content $operatingModel -Needle 'scripts/validate-ai-customization.ps1' -FailureMessage 'docs/AI-OPERATING-MODEL.md must reference scripts/validate-ai-customization.ps1'

Assert-Contains -Content $workflowReadme -Needle 'validate-ai-customization.yml' -FailureMessage '.github/workflows/README.md must document validate-ai-customization.yml'
Assert-Contains -Content $scriptReadme -Needle 'validate-ai-customization.ps1' -FailureMessage 'scripts/README.md must document validate-ai-customization.ps1'

if ($failures.Count -eq 0) {
    Write-Host "AI customization validation passed. Checked $($instructionFiles.Count) instruction file(s), $($promptFiles.Count) prompt file(s), $($agentFiles.Count) agent file(s), and $($skillFiles.Count) skill file(s)." -ForegroundColor Green
    exit 0
}

Write-Host "AI customization validation FAILED - $($failures.Count) issue(s):" -ForegroundColor Red
foreach ($failure in $failures) {
    Write-Host "  $failure" -ForegroundColor Red
}

exit 1