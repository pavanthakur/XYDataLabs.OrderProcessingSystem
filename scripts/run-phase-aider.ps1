param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('architecture', 'implementation')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{2}$')]
    [string]$Phase,

    [string]$Model,
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$phaseName = "phase-$Phase-microservices-$Mode.prompt.md"
$promptFile = Join-Path $RepoRoot ".github\prompts\phase-handoffs\$phaseName"

if (-not (Test-Path $promptFile)) {
    throw "Prompt file not found: $promptFile"
}

if (-not $Model) {
    if ($Mode -eq 'architecture') {
        $Model = 'ollama/qwen3-8b-64k:latest'
    } else {
        $Model = 'ollama/qwen2.5-coder:7b'
    }
}

$aiderExe = 'C:\Users\Pavan\AppData\Local\Programs\Python\Python311\Scripts\aider.exe'
if (-not (Test-Path $aiderExe)) {
    throw "Aider executable not found at $aiderExe"
}

Write-Host "Running $Mode handoff for phase $Phase with model $Model"
Write-Host "Prompt: $promptFile"

& $aiderExe $RepoRoot --model $Model --message-file $promptFile
