param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('9.1','9.2')]
    [string]$Slice,

    [Parameter(Mandatory = $true)]
    [ValidateSet('architect','developer','review','automation')]
    [string]$Step
)

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$sliceDir = Join-Path $PSScriptRoot $Slice
$tempDir = Join-Path $PSScriptRoot '_temp'
$contextFile = Join-Path $tempDir "$Slice-$Step.context.md"
$promptFile = Join-Path $sliceDir "$Step.md"
$rulesFile = Join-Path $root '.github\instructions\ai-operating.instructions.md'
$architecturePromptFile = Join-Path $root '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md'
$implementationPromptFile = Join-Path $root '.github\prompts\phase-handoffs\phase-09-microservices-implementation.prompt.md'
$architectArtifactFile = Join-Path $tempDir "$Slice-architect.md"
$developerArtifactFile = Join-Path $tempDir "$Slice-developer.md"

if (-not (Test-Path $promptFile)) {
    throw "Prompt file not found: $promptFile"
}

$null = New-Item -ItemType Directory -Path $tempDir -Force

$sections = New-Object System.Collections.Generic.List[string]
$sectionSizes = New-Object System.Collections.Generic.List[object]

function Add-Block {
    param(
        [string]$Title,
        [string]$Content
    )

    $sections.Add($Title)
    $sections.Add("")
    $sections.Add($Content)
    $sections.Add("")
    $sectionSizes.Add([pscustomobject]@{
        Title = $Title
        Characters = $Content.Length
        ApproxTokens = [Math]::Ceiling($Content.Length / 4)
    })
}

$sections.Add("# Phase $Slice $Step Context")
$sections.Add("")
$sections.Add("This file is generated for one model run only. Keep the slice narrow and do not expand scope.")
$sections.Add("")

$rulesSummary = @(
    "- Keep every task slice-sized."
    "- Do not expand scope beyond the accepted handoff."
    "- Prefer the minimum set of files needed to make progress."
    "- Treat architecture output as advisory until reviewed and accepted."
    "- Architect output must start with a concrete plan summary, then list deliverables, risks, and the acceptance checklist for the slice."
    "- Treat developer output as implementation-only; do not invent architecture."
    "- Validate the narrowest useful change first, then widen only if needed."
    "- Do not use Aider to create or edit files in implementation slices; use deterministic direct-write scripts."
    "- Review must validate actual changed files and diffs."
    "- Automation must verify the narrow end-to-end behavior of the changed files."
    "- Automation output must end with an explicit achieved/not-achieved verdict against the planned checklist, not a vague success claim."
) -join "`r`n"

Add-Block -Title '## AI Operating Rules' -Content $rulesSummary

$handoffSummary = @(
    "- Architect produces the decision, risks, constraints, first implementation slice, and a concrete plan summary before any command sequence."
    "- Developer implements one accepted slice only."
    "- Agent execution may happen only after the slice is precise."
    "- Validation runs before the next slice starts."
    "- Automation closes with an explicit checklist verdict that names anything still unfinished."
) -join "`r`n"

Add-Block -Title '## Local Handoff Guide Summary' -Content $handoffSummary

switch ($Step) {
    'architect' {
        Add-Block -Title '## Phase Prompt' -Content (Get-Content -Raw $architecturePromptFile)
        Add-Block -Title '## Slice Prompt' -Content (Get-Content -Raw $promptFile)
    }
    'developer' {
        Add-Block -Title '## Phase Prompt' -Content (Get-Content -Raw $implementationPromptFile)
        Add-Block -Title '## Slice Prompt' -Content (Get-Content -Raw $promptFile)
        if (Test-Path $architectArtifactFile) {
            Add-Block -Title '## Accepted Architect Artifact' -Content (Get-Content -Raw $architectArtifactFile)
        }
    }
    'review' {
        Add-Block -Title '## Slice Prompt' -Content (Get-Content -Raw $promptFile)
        if (Test-Path $developerArtifactFile) {
            Add-Block -Title '## Accepted Developer Artifact' -Content (Get-Content -Raw $developerArtifactFile)
        }
    }
    'automation' {
        $reviewArtifactFile = Join-Path $tempDir "$Slice-review.md"
        Add-Block -Title '## Slice Prompt' -Content (Get-Content -Raw $promptFile)
        if (Test-Path $reviewArtifactFile) {
            Add-Block -Title '## Accepted Review Artifact' -Content (Get-Content -Raw $reviewArtifactFile)
        }
    }
}

[string]$contextPreview = ($sections -join "`r`n")
$approxTokens = [Math]::Ceiling($contextPreview.Length / 4)
$tokenLimit = switch ($Step) {
    'architect' { 3500 }
    default { 12000 }
}

if ($approxTokens -gt $tokenLimit) {
    $largestSection = $sectionSizes | Sort-Object ApproxTokens -Descending | Select-Object -First 1
    $details = ($sectionSizes | Sort-Object ApproxTokens -Descending | ForEach-Object { "$($_.Title): ~$($_.ApproxTokens) tokens" }) -join "; "
    throw "Generated context for $Slice/$Step is too large (~$approxTokens tokens). Limit is $tokenLimit. Largest section: $($largestSection.Title) (~$($largestSection.ApproxTokens) tokens). Section sizes: $details. Narrow the slice or remove unsupported context before running the model."
}

[void]$sections.Insert(1, "Estimated context size: approximately $approxTokens tokens (limit: $tokenLimit).")
[void]$sections.Insert(2, "")

[System.IO.File]::WriteAllLines($contextFile, $sections, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $contextFile
