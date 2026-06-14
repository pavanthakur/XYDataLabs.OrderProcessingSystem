param(
    [string]$Mode = 'developer',
    [string]$PromptFile = ''
)
if (-not $PromptFile) { $PromptFile = '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md' }
Write-Host "AI runtime runner: mode=$Mode prompt=$PromptFile"
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\logger.ps1"
. "$PSScriptRoot\config.ps1"

$res = Invoke-Engine -Mode $Mode -PromptFile $PromptFile
Write-Host "Engine exit: $($res.exit)"
Write-PromptRunLog -PromptFile $res.prompt -Model $res.model -ExitCode $res.exit -OutputFile $res.output -SessionId ''
