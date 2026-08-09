param(
    [string[]]$Targets = @(
        'Resources/Azure-Deployment'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$forbiddenPatterns = @(
    @{
        Name = 'UseAzureAdToken switch forwarding'
        Regex = '-UseAzureAdToken:\$[A-Za-z_][A-Za-z0-9_]*'
    }
    @{
        Name = 'UseSqlAuth switch forwarding'
        Regex = '-UseSqlAuth:\$[A-Za-z_][A-Za-z0-9_]*'
    }
)

$violations = New-Object 'System.Collections.Generic.List[object]'

foreach ($target in $Targets) {
    $resolvedTarget = Join-Path $repoRoot $target
    if (-not (Test-Path -LiteralPath $resolvedTarget)) {
        continue
    }

    $files = Get-ChildItem -LiteralPath $resolvedTarget -Recurse -File -Include *.ps1,*.psm1
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            foreach ($pattern in $forbiddenPatterns) {
                if ($line -match $pattern.Regex) {
                    $violations.Add([pscustomobject]@{
                            File    = $file.FullName.Substring($repoRoot.Length + 1)
                            Line    = $lineNumber
                            Rule    = $pattern.Name
                            Content = $line.Trim()
                        })
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'PowerShell switch-forwarding guardrail failed.' -ForegroundColor Red
    foreach ($violation in $violations) {
        Write-Host (" - {0}:{1} [{2}] {3}" -f $violation.File, $violation.Line, $violation.Rule, $violation.Content) -ForegroundColor Yellow
    }

    throw 'Forbidden PowerShell switch-forwarding pattern detected. Use explicit switch selection or a splat built from .IsPresent instead.'
}

Write-Host 'PowerShell switch-forwarding guardrail passed.' -ForegroundColor Green
