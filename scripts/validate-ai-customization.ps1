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
$warnings = [System.Collections.Generic.List[string]]::new()
$pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Add-Failure {
    param([string]$Message)

    $script:failures.Add($Message)
}

function Get-FileText {
    param([string]$RelativePath)

    $fullPath = Get-SafeRepositoryPath -RelativePath $RelativePath
    if (-not $fullPath) { return $null }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Add-Failure("AI101 Missing required file: $RelativePath")
        return $null
    }
    return Get-Content -LiteralPath $fullPath -Raw
}

function Get-SafeRepositoryPath {
    param([string]$RelativePath, [switch]$AllowMissing)
    # Accept repository-relative paths only, with either separator on both platforms.
    if ($RelativePath -match '^(?:[A-Za-z]:|[/\\])') {
        Add-Failure('AI102 Rooted reference rejected (target redacted).'); return $null
    }
    try {
        $normalized = $RelativePath.Replace('\', [IO.Path]::DirectorySeparatorChar).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $full = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $normalized))
    } catch { Add-Failure('AI102 Malformed reference rejected (target redacted).'); return $null }
    $prefix = $RepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, $pathComparison)) {
        Add-Failure('AI102 Reference escapes repository boundary (target redacted).'); return $null
    }
    $cursor = $RepositoryRoot
    foreach ($part in [IO.Path]::GetRelativePath($RepositoryRoot, $full).Split([IO.Path]::DirectorySeparatorChar)) {
        $cursor = Join-Path $cursor $part
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Add-Failure('AI103 Symlink/reparse reference rejected (target redacted).'); return $null
        }
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        Add-Failure('AI101 Required repository reference is missing (target redacted).'); return $null
    }
    return $full
}

function Get-AssetFiles {
    param([string]$Directory, [string]$Filter, [switch]$Recurse)
    $safe = Get-SafeRepositoryPath -RelativePath $Directory
    if (-not $safe) { return }
    foreach ($item in Get-ChildItem -LiteralPath $safe -Force | Sort-Object Name) {
        $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $item.FullName)
        if (-not (Get-SafeRepositoryPath -RelativePath $relative)) { continue }
        if ($item.PSIsContainer) {
            if ($Recurse) { Get-AssetFiles -Directory $relative -Filter $Filter -Recurse }
        } elseif ($item.Name -like $Filter) { $item }
    }
}

function Assert-ByteBudget {
    param([string]$RelativePath, [int]$Maximum)
    $safe = Get-SafeRepositoryPath -RelativePath $RelativePath
    if ($safe -and (Get-Item -LiteralPath $safe).Length -gt $Maximum) {
        Add-Failure("AI104 Instruction budget exceeded: $RelativePath (maximum $Maximum bytes).")
    }
}

function Get-HeadingSlug {
    param([string]$Heading)
    $value = ($Heading -replace '<[^>]*>', '' -replace '`+', '').Trim().ToLowerInvariant().Normalize([Text.NormalizationForm]::FormKD)
    return (($value -replace '\p{Mn}', '' -replace '[^\p{L}\p{N}\s-]', '' -replace '\s+', '-' -replace '-+', '-').Trim('-'))
}

function Test-LocalLinks {
    param([string]$Source, [string]$Content)
    $withoutCode = $Content -replace '(?s)```.*?```', '' -replace '(?s)~~~.*?~~~', ''
    foreach ($match in [regex]::Matches($withoutCode, '(?<!!)\[[^\]]*\]\((?<target>[^)]+)\)')) {
        $target = $match.Groups['target'].Value.Trim().Trim('<', '>')
        if ($target -match '^(?i:https?:|mailto:|tel:)') { continue }
        $pieces = $target.Split('#', 2)
        try { $local = [Uri]::UnescapeDataString($pieces[0]) } catch { Add-Failure("AI105 Invalid link in $Source (target redacted)."); continue }
        if ($local -match '^(?:[A-Za-z][\w+.-]*:|[/\\])') { Add-Failure("AI102 Invalid local link in $Source (target redacted)."); continue }
        $parent = Split-Path $Source -Parent
        $relative = if (-not $local) { $Source } elseif ($parent) { Join-Path $parent $local } else { $local }
        $safe = Get-SafeRepositoryPath -RelativePath $relative -AllowMissing
        if (-not $safe) { continue }
        if (-not (Test-Path -LiteralPath $safe)) {
            $resolvedRelative = [IO.Path]::GetRelativePath($RepositoryRoot, $safe).Replace('\', '/')
            if ($resolvedRelative.StartsWith('TestResults/', [StringComparison]::Ordinal)) {
                $warnings.Add("Unavailable local artifact referenced in $Source; not reverified.")
            } else { Add-Failure("AI105 Broken repository link in $Source (target redacted).") }
            continue
        }
        if ($pieces.Count -gt 1 -and $pieces[1]) {
            if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) { Add-Failure("AI105 Invalid anchor target in $Source."); continue }
            $anchors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $seen = @{}
            foreach ($line in Get-Content -LiteralPath $safe) {
                if ($line -match '^#{1,6}\s+(.*)$') {
                    $slug = Get-HeadingSlug $Matches[1]
                    if ($seen.ContainsKey($slug)) { $seen[$slug]++; [void]$anchors.Add("$slug-$($seen[$slug])") }
                    else { $seen[$slug] = 0; [void]$anchors.Add($slug) }
                }
            }
            if (-not $anchors.Contains([Uri]::UnescapeDataString($pieces[1]))) { Add-Failure("AI105 Broken heading link in $Source (target redacted).") }
        }
    }
}

function Test-CheckpointEvidence {
    param([string]$Content)
    $values = @{}
    foreach ($field in @('Review revision','Worktree state','Evidence status','Evidence revision','Evidence environment','Evidence scope','Evidence reference')) {
        $hits = [regex]::Matches($Content, ('(?m)^- ' + [regex]::Escape($field) + ':[ \t]*`?([^`\r\n]+)`?[ \t]*\r?$'))
        if ($hits.Count -ne 1) { Add-Failure("AI108 Missing/duplicate checkpoint field: $field"); continue }
        $values[$field] = $hits[0].Groups[1].Value.Trim()
    }
    if ($values.Count -ne 7) { return }
    foreach ($field in $values.Keys) {
        if ([string]::IsNullOrWhiteSpace($values[$field])) { Add-Failure("AI108 Empty checkpoint field: $field (value redacted).") }
    }
    foreach ($field in @('Review revision','Evidence revision')) {
        if ($values[$field] -notmatch '^(?:[0-9a-fA-F]{7,40}|UNKNOWN)$') { Add-Failure("AI108 Invalid checkpoint field: $field (value redacted).") }
    }
    if ($values['Worktree state'] -notin @('CLEAN','DIRTY','UNKNOWN')) { Add-Failure('AI108 Invalid checkpoint worktree state.') }
    if ($values['Evidence status'] -notin @('HISTORICAL','UNAVAILABLE','NOT_TESTED','CURRENT_PASS','FAIL','BLOCKED')) { Add-Failure('AI108 Invalid checkpoint evidence status.') }
    $reference = $values['Evidence reference'].Replace('\', '/')
    if (-not $reference.StartsWith('TestResults/', [StringComparison]::Ordinal)) { Add-Failure('AI108 Evidence reference must be repository-relative under TestResults (value redacted).'); return }
    $safe = Get-SafeRepositoryPath -RelativePath $reference -AllowMissing
    if ($values['Evidence status'] -eq 'CURRENT_PASS') {
        if ($values['Evidence revision'] -eq 'UNKNOWN' -or $values['Review revision'] -ne $values['Evidence revision'] -or $values['Worktree state'] -ne 'CLEAN') {
            Add-Failure('AI109 CURRENT_PASS requires bound matching revisions and a clean recorded worktree; not runtime certification.')
        }
        if (-not $safe -or -not (Test-Path -LiteralPath $safe -PathType Leaf)) { Add-Failure('AI109 CURRENT_PASS requires its recorded artifact; missing evidence is not PASS.') }
    } elseif ($safe -and -not (Test-Path -LiteralPath $safe)) {
        $warnings.Add('Checkpoint artifact unavailable in this checkout; historical/unknown evidence is not current PASS.')
    }
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

function Assert-FrontmatterField {
    param([string]$Frontmatter, [string]$Field, [string]$FileName)
    $matches = [regex]::Matches($Frontmatter, ('(?m)^' + [regex]::Escape($Field) + ':[ \t]*([^\r\n]*)'))
    if ($matches.Count -ne 1 -or -not $matches[0].Groups[1].Value.Trim().Trim('"', "'")) {
        Add-Failure("AI112 Missing/duplicate/empty frontmatter field $Field in $FileName (value redacted).")
    }
}

$requiredFiles = @(
    'AGENTS.md',
    'memories/repo/active-work.md',
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
$sharedInstructions = Get-FileText -RelativePath 'AGENTS.md'
$promptReadme = Get-FileText -RelativePath '.github/prompts/README.md'
$skillReadme = Get-FileText -RelativePath '.github/skills/README.md'
$workflowReadme = Get-FileText -RelativePath '.github/workflows/README.md'
$scriptReadme = Get-FileText -RelativePath 'scripts/README.md'
$operatingModel = Get-FileText -RelativePath 'docs/AI-OPERATING-MODEL.md'
$completionCheckPrompt = Get-FileText -RelativePath '.github/prompts/XYDataLabs-completion-check.prompt.md'

$instructionFiles = @(Get-AssetFiles '.github/instructions' '*.instructions.md')
$promptFiles = @(Get-AssetFiles '.github/prompts' '*.prompt.md')
$agentFiles = @(Get-AssetFiles '.github/agents' '*.agent.md')
$skillFiles = @(Get-AssetFiles '.github/skills' 'SKILL.md' -Recurse)

foreach ($file in $instructionFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.Name): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^applyTo\s*:') {
        Add-Failure("$($file.Name): frontmatter must include applyTo")
    }
    Assert-FrontmatterField $frontmatter 'applyTo' $file.Name
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
    Assert-FrontmatterField $frontmatter 'description' $file.Name

    $promptCommand = '/' + $file.BaseName.Replace('.prompt', '')
    Assert-Contains -Content $promptReadme -Needle $promptCommand -FailureMessage "$($file.Name): missing from .github/prompts/README.md"
    $headings = [regex]::Matches($promptReadme, ('(?m)^###\s+`' + [regex]::Escape($promptCommand) + '`\s*\r?$'))
    if ($headings.Count -ne 1) { Add-Failure("AI106 Expected exactly one canonical prompt heading for $($file.Name).") }
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
    Assert-FrontmatterField $frontmatter 'description' $file.Name

    Assert-Contains -Content $promptReadme -Needle $file.Name -FailureMessage "$($file.Name): missing from .github/prompts/README.md"
    $row = [regex]::Matches($promptReadme, ('(?m)^\|[^\r\n]*`\.github/agents/' + [regex]::Escape($file.Name) + '`[^\r\n]*\|\s*\r?$'))
    if ($row.Count -ne 1) { Add-Failure("AI106 Expected exactly one canonical agent row for $($file.Name).") }
}

$skillNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $skillFiles) {
    $frontmatter = Get-Frontmatter -FilePath $file.FullName
    if (-not $frontmatter) {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): missing YAML frontmatter")
        continue
    }

    if ($frontmatter -notmatch '(?m)^name\s*:') {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): frontmatter must include name")
    }
    Assert-FrontmatterField $frontmatter 'name' $file.Name
    Assert-FrontmatterField $frontmatter 'description' $file.Name

    if ($frontmatter -notmatch '(?m)^description\s*:') {
        Add-Failure("$($file.FullName.Substring($RepositoryRoot.Length + 1)): frontmatter must include description")
    }

    $skillFolder = Split-Path -Path $file.DirectoryName -Leaf
    $nameMatch = [regex]::Match($frontmatter, '(?m)^name:\s*["'']?([a-z0-9-]+)["'']?\s*\r?$')
    if (-not $nameMatch.Success -or $nameMatch.Groups[1].Value -ne $skillFolder) { Add-Failure('AI106 Skill name must match its canonical folder (value redacted).') }
    if ($nameMatch.Success -and -not $skillNames.Add($nameMatch.Groups[1].Value)) { Add-Failure('AI106 Duplicate skill name (value redacted).') }
    Assert-Contains -Content $skillReadme -Needle $skillFolder -FailureMessage "$($file.FullName.Substring($RepositoryRoot.Length + 1)): missing from .github/skills/README.md"
    $rows = [regex]::Matches($skillReadme, ('(?m)^\|[^\r\n]*`\.github/skills/' + [regex]::Escape($skillFolder) + '/(?:SKILL\.md)?`[^\r\n]*\|\s*\r?$'))
    if ($rows.Count -ne 1) { Add-Failure('AI106 Expected one canonical row per skill in its owning index (value redacted).') }
}

foreach ($index in @($promptReadme, $skillReadme)) {
    $labels = @{}
    foreach ($row in [regex]::Matches($index, '(?m)^\|\s*([^|]+?)\s*\|\s*`(\.github/(?:agents|skills)/[^`]+)`')) {
        $label = $row.Groups[1].Value.Trim(); $target = $row.Groups[2].Value
        if ($labels.ContainsKey($label) -and $labels[$label] -ne $target) { Add-Failure('AI107 Contradictory discovery label maps to different assets (values redacted).') }
        $labels[$label] = $target
    }
}

foreach ($entry in @('AGENTS.md','.github/copilot-instructions.md')) { Assert-ByteBudget $entry 6144 }
Assert-ByteBudget 'memories/repo/active-work.md' 8192
foreach ($source in @('AGENTS.md','.github/copilot-instructions.md','docs/AI-OPERATING-MODEL.md','docs/DEVELOPER-OPERATING-MODEL.md','.github/prompts/README.md','.github/skills/README.md','memories/repo/active-work.md')) {
    $content = Get-FileText $source
    if ($content) { Test-LocalLinks $source $content }
}
$checkpoint = Get-FileText 'memories/repo/active-work.md'
if ($checkpoint) { Test-CheckpointEvidence $checkpoint }
Assert-Contains $sharedInstructions '## Approval Boundaries' 'AI110 Shared approval guidance is missing.'
Assert-Contains $sharedInstructions '## Evidence And Limits' 'AI110 Shared evidence section is missing.'
foreach ($source in @('AGENTS.md','.github/copilot-instructions.md','.github/prompts/XYDataLabs-day-start.prompt.md','.github/prompts/XYDataLabs-day-complete.prompt.md','.github/prompts/XYDataLabs-new-feature.prompt.md')) {
    $content = Get-FileText $source
    if ($content -match '(?im)^\s*git\s+add\s+-A\s*$|^\s*git\s+commit\s|authoritative source\s*[—-]\s*trust it|^\s*- Push tag and branch to origin\s*$') {
        Add-Failure("AI110 Known unsafe unconditional directive in $source (content redacted).")
    }
}
foreach ($source in @('AGENTS.md','.github/copilot-instructions.md','memories/repo/active-work.md') + @($instructionFiles + $promptFiles + $agentFiles + $skillFiles | ForEach-Object { [IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName) })) {
    $content = Get-FileText $source
    if ($content -match '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|sk_live_[A-Za-z0-9]{12,}|ghp_[A-Za-z0-9]{30,}') {
        Add-Failure("AI111 Potential sensitive literal in $source (value redacted).")
    }
}

# Short client entries link owning indexes; discovery is still checked for every asset above.
Assert-Contains -Content $copilotInstructions -Needle '../AGENTS.md' -FailureMessage '.github/copilot-instructions.md must link shared AGENTS.md guidance'
Assert-Contains -Content $copilotInstructions -Needle 'prompts/README.md' -FailureMessage '.github/copilot-instructions.md must link the owning prompt/agent index'
Assert-Contains -Content $copilotInstructions -Needle 'skills/README.md' -FailureMessage '.github/copilot-instructions.md must link the owning skill index'
Assert-Contains -Content $sharedInstructions -Needle 'docs/AI-OPERATING-MODEL.md' -FailureMessage 'AGENTS.md must route to the shared AI operating model'
Assert-Contains -Content $sharedInstructions -Needle '.github/skills/README.md' -FailureMessage 'AGENTS.md must route to the canonical existing skill index'

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

$azureWorkflowInstructions = Get-FileText -RelativePath '.github/instructions/azure-workflows.instructions.md'
$azureDeploymentSkill = Get-FileText -RelativePath '.github/skills/azure-deployment-operations/SKILL.md'
$cqrsBackendSkill = Get-FileText -RelativePath '.github/skills/cqrs-backend-implementation/SKILL.md'
$codeReviewSkill = Get-FileText -RelativePath '.github/skills/code-review-guardrails/SKILL.md'
$completionCheckSkill = Get-FileText -RelativePath '.github/skills/completion-check-governance/SKILL.md'
$contextAuditSkill = Get-FileText -RelativePath '.github/skills/context-audit-governance/SKILL.md'
$newFeaturePrompt = Get-FileText -RelativePath '.github/prompts/XYDataLabs-new-feature.prompt.md'
$cqrsBackendAgent = Get-FileText -RelativePath '.github/agents/cqrs-backend.agent.md'
$codeReviewerAgent = Get-FileText -RelativePath '.github/agents/code-reviewer.agent.md'
$azureDevOpsAgent = Get-FileText -RelativePath '.github/agents/azure-devops.agent.md'

Assert-Contains -Content $copilotInstructions -Needle 'Strict Azure Runtime Target Convention' -FailureMessage '.github/copilot-instructions.md must document the strict Azure runtime target convention'
Assert-Contains -Content $copilotInstructions -Needle 'automation/config/runtime-targets.json' -FailureMessage '.github/copilot-instructions.md must identify runtime-targets.json as the Azure automation source of truth'
Assert-Contains -Content $copilotInstructions -Needle 'validate-phase10-environment-contract.ps1' -FailureMessage '.github/copilot-instructions.md must require the Phase 10 environment contract validator for Azure automation changes'
Assert-Contains -Content $azureWorkflowInstructions -Needle 'Strict Azure Runtime Target Convention' -FailureMessage '.github/instructions/azure-workflows.instructions.md must document the strict Azure runtime target convention'
Assert-Contains -Content $azureWorkflowInstructions -Needle 'Do not commit generated Azure Container Apps FQDNs' -FailureMessage '.github/instructions/azure-workflows.instructions.md must ban generated Azure hostnames in runtime-targets.json'
Assert-Contains -Content $azureDeploymentSkill -Needle 'Runtime target convention for Phase 10+ automation' -FailureMessage 'azure-deployment-operations skill must document the runtime target convention'
Assert-Contains -Content $azureDeploymentSkill -Needle 'validate-phase10-environment-contract.ps1' -FailureMessage 'azure-deployment-operations skill must require the Phase 10 environment contract validator when Azure runtime target behavior changes'
Assert-Contains -Content $cqrsBackendSkill -Needle 'Azure/runtime automation impact' -FailureMessage 'cqrs-backend-implementation skill must require Azure/runtime automation impact checks for new services'
Assert-Contains -Content $codeReviewSkill -Needle 'runtime-target drift' -FailureMessage 'code-review-guardrails skill must flag runtime-target drift'
Assert-Contains -Content $completionCheckSkill -Needle 'Azure automation changed without proving' -FailureMessage 'completion-check-governance skill must require Azure runtime-target closeout validation'
Assert-Contains -Content $contextAuditSkill -Needle 'Azure runtime-target convention' -FailureMessage 'context-audit-governance skill must include runtime-target convention drift checks'
Assert-Contains -Content $newFeaturePrompt -Needle 'Azure Runtime/Automation Impact Check' -FailureMessage 'new feature prompt must include Azure runtime/automation impact check'
Assert-Contains -Content $cqrsBackendAgent -Needle 'Azure/runtime impact check' -FailureMessage 'CQRS backend agent must flag Azure/runtime automation impact for new services'
Assert-Contains -Content $codeReviewerAgent -Needle 'Azure runtime targets' -FailureMessage 'code reviewer agent must review Azure runtime target updates for new services'
Assert-Contains -Content $azureDevOpsAgent -Needle 'Runtime target source of truth' -FailureMessage 'Azure DevOps agent must document runtime-target source-of-truth convention'

foreach ($warning in $warnings | Sort-Object -Unique) { Write-Host "[UNAVAILABLE] $warning" }
if ($failures.Count -eq 0) {
    Write-Host "AI customization validation passed. Checked $($instructionFiles.Count) instruction file(s), $($promptFiles.Count) prompt file(s), $($agentFiles.Count) agent file(s), and $($skillFiles.Count) skill file(s)." -ForegroundColor Green
    exit 0
}

Write-Host "AI customization validation FAILED - $($failures.Count) issue(s):" -ForegroundColor Red
foreach ($failure in $failures) {
    Write-Host "  $failure" -ForegroundColor Red
}

exit 1
