param(
    [string]$Mode = 'developer',
    [string]$PromptFile = ''
)
if (-not $PromptFile) { $PromptFile = '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md' }
Write-Host "AI runtime runner: mode=$Mode prompt=$PromptFile"
& scripts\run-aider-onecmd.ps1 -Mode $Mode -PromptFile $PromptFile
