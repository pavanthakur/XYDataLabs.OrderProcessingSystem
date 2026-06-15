param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('architect','developer','review','automation')]
    [string]$Step
)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$aider = 'C:\Users\Pavan\AppData\Local\Programs\Python\Python311\Scripts\aider.exe'
$basePrompt = Join-Path $PSScriptRoot '00-phase9-zoo-code-runner.md'

if (-not (Test-Path $aider)) {
    throw "Aider executable not found at $aider"
}

switch ($Step) {
    'architect' {
        $prompt = Join-Path $PSScriptRoot 'phase9_architect1.0.md'
        & $aider $root --model ollama/qwen2.5-coder:7b --message-file $prompt
    }
    'developer' {
        $prompt = Join-Path $PSScriptRoot 'phase9_development1.0.md'
        & $aider $root --model ollama/qwen2.5-coder:7b --message-file $prompt
    }
    'review' {
        $prompt = Join-Path $PSScriptRoot 'phase9_review1.0.md'
        & $aider $root --model ollama/qwen2.5-coder:7b --message-file $prompt
    }
    'automation' {
        $prompt = Join-Path $PSScriptRoot 'phase9_automation1.0.md'
        & $aider $root --model ollama/qwen2.5-coder:7b --message-file $prompt
    }
}
