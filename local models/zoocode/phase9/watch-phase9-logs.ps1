param(
    [string]$LogDir = (Join-Path $PSScriptRoot '_temp')
)

$ollamaLog = Join-Path $LogDir 'ollama.log'
$phaseLog = Join-Path $LogDir 'phase9-e2e.log'

if (-not (Test-Path $LogDir)) {
    throw "Log directory not found: $LogDir"
}

function Get-NewLines {
    param(
        [string]$Path,
        [ref]$State
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    $lines = Get-Content -LiteralPath $Path
    $previousCount = 0
    if ($State.Value.ContainsKey($Path)) {
        $previousCount = [int]$State.Value[$Path]
    }

    if ($lines.Count -le $previousCount) {
        return @()
    }

    $newLines = $lines[$previousCount..($lines.Count - 1)]
    $State.Value[$Path] = $lines.Count
    return $newLines
}

Write-Host "Watching logs:"
Write-Host "  $ollamaLog"
Write-Host "  $phaseLog"
Write-Host ""
Write-Host "Press Ctrl+C to stop."
Write-Host ""

$state = @{}
if (Test-Path $ollamaLog) {
    $state[$ollamaLog] = (Get-Content -LiteralPath $ollamaLog).Count
}
if (Test-Path $phaseLog) {
    $state[$phaseLog] = (Get-Content -LiteralPath $phaseLog).Count
}

while ($true) {
    $ollamaLines = Get-NewLines -Path $ollamaLog -State ([ref]$state)
    foreach ($line in $ollamaLines) {
        Write-Host "[ollama] $line"
    }

    $phaseLines = Get-NewLines -Path $phaseLog -State ([ref]$state)
    foreach ($line in $phaseLines) {
        Write-Host "[phase9] $line"
    }

    Start-Sleep -Seconds 1
}
