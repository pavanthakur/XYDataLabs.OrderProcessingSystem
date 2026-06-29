param(
    [Parameter(Mandatory = $true)]
    [string]$PhasePackRoot,

    [Parameter(Mandatory = $true)]
    [string]$Slice,

    [Parameter(Mandatory = $true)]
    [ValidateSet('architect','developer','review','automation')]
    [string]$Step,

    [int]$ArchitectTokenLimit = 3500,
    [int]$OtherTokenLimit = 12000
)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempDir = Join-Path $PhasePackRoot '_temp'
$sliceDir = Join-Path $PhasePackRoot $Slice
$contextFile = Join-Path $tempDir "$Slice-$Step.context.md"
$promptFile = Join-Path $sliceDir "$Step.md"
$rulesFile = Join-Path $root '.github\instructions\ai-operating.instructions.md'

if (-not (Test-Path $PhasePackRoot)) { throw "Phase pack root not found: $PhasePackRoot" }
if (-not (Test-Path $promptFile)) { throw "Prompt file not found: $promptFile" }

$null = New-Item -ItemType Directory -Path $tempDir -Force

$sections = New-Object System.Collections.Generic.List[string]
$sectionSizes = New-Object System.Collections.Generic.List[object]

function Add-Block {
    param([string]$Title, [string]$Content)
    $sections.Add($Title)
    $sections.Add("")
    $sections.Add($Content)
    $sections.Add("")
    $sectionSizes.Add([pscustomobject]@{
        Title = $Title
        ApproxTokens = [Math]::Ceiling($Content.Length / 4)
    })
}

Add-Block -Title "# Phase $Slice $Step Context" -Content "This file is generated for one model run only. Keep the slice narrow and do not expand scope."

$rulesSummary = @(
    "- Keep every task slice-sized."
    "- Do not expand scope beyond the accepted handoff."
    "- Prefer the minimum set of files needed to make progress."
    "- Treat architecture output as advisory until reviewed and accepted."
    "- Architect output must start with a concrete plan summary, then list deliverables, risks, and the acceptance checklist for the slice."
    "- Treat developer output as implementation-only; do not invent architecture."
    "- Validate the narrowest useful change first, then widen only if needed."
    "- Automation output must end with an explicit achieved/not-achieved verdict against the planned checklist, not a vague success claim."
) -join "`r`n"
Add-Block -Title "## AI Operating Rules" -Content $rulesSummary

$handoffSummary = @(
    "- Architect produces the decision, risks, constraints, first implementation slice, and a concrete plan summary before any command sequence."
    "- Developer implements one accepted slice only."
    "- Agent execution may happen only after the slice is precise."
    "- Validation runs before the next slice starts."
    "- Automation closes with an explicit checklist verdict that names anything still unfinished."
) -join "`r`n"
Add-Block -Title "## Local Handoff Guide Summary" -Content $handoffSummary

if (Test-Path $rulesFile) {
    Add-Block -Title "## Repo AI Rules" -Content (Get-Content -Raw $rulesFile)
}

$slicePromptText = Get-Content -Raw $promptFile

switch ($Step) {
    'architect' {
        Add-Block -Title "## Slice Prompt" -Content $slicePromptText
    }
    'developer' {
        $artifact = Join-Path $tempDir "$Slice-architect.md"
        Add-Block -Title "## Slice Prompt" -Content $slicePromptText
        if (Test-Path $artifact) {
            Add-Block -Title "## Accepted Architect Artifact" -Content (Get-Content -Raw $artifact)
        }
    }
    'review' {
        $artifact = Join-Path $tempDir "$Slice-developer.md"
        Add-Block -Title "## Slice Prompt" -Content $slicePromptText
        if (Test-Path $artifact) {
            Add-Block -Title "## Accepted Developer Artifact" -Content (Get-Content -Raw $artifact)
        }
    }
    'automation' {
        $artifact = Join-Path $tempDir "$Slice-review.md"
        Add-Block -Title "## Slice Prompt" -Content $slicePromptText
        if (Test-Path $artifact) {
            Add-Block -Title "## Accepted Review Artifact" -Content (Get-Content -Raw $artifact)
        }
    }
}

$contextPreview = ($sections -join "`r`n")
$approxTokens = [Math]::Ceiling($contextPreview.Length / 4)
$tokenLimit = if ($Step -eq 'architect') { $ArchitectTokenLimit } else { $OtherTokenLimit }

if ($approxTokens -gt $tokenLimit) {
    $largestSection = $sectionSizes | Sort-Object ApproxTokens -Descending | Select-Object -First 1
    $details = ($sectionSizes | Sort-Object ApproxTokens -Descending | ForEach-Object { "$($_.Title): ~$($_.ApproxTokens) tokens" }) -join "; "
    throw "Generated context for $Slice/$Step is too large (~$approxTokens tokens). Limit is $tokenLimit. Largest section: $($largestSection.Title) (~$($largestSection.ApproxTokens) tokens). Section sizes: $details. Narrow the slice before running the model."
}

[void]$sections.Insert(1, "Estimated context size: approximately $approxTokens tokens (limit: $tokenLimit).")
[void]$sections.Insert(2, "")

[System.IO.File]::WriteAllLines($contextFile, $sections, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $contextFile
