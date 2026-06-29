param(
    [string]$Mode = 'developer',
    [string]$PromptFile = '',
    [string]$SessionId = ''
)
if (-not $PromptFile) { $PromptFile = '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md' }
Write-Host "AI runtime runner: mode=$Mode prompt=$PromptFile session=$SessionId"
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\logger.ps1"
. "$PSScriptRoot\config.ps1"

# Generate deterministic session id if not provided: ISO timestamp + random 6-hex
if (-not $SessionId) {
    $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $rnd = -join ((48..57 + 97..102) | Get-Random -Count 6 | ForEach-Object {[char]$_})
    $SessionId = "$ts-$rnd"
}

$res = Invoke-Engine -Mode $Mode -PromptFile $PromptFile -SessionId $SessionId
Write-Host "Engine exit: $($res.exit) session: $($res.session)"
Write-PromptRunLog -PromptFile $res.prompt -Model $res.model -ExitCode $res.exit -OutputFile $res.output -SessionId $res.session
