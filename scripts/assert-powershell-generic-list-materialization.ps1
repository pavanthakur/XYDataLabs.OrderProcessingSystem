param(
    [string[]]$Targets = @(
        'Resources/Azure-Deployment',
        'scripts'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$violations = New-Object 'System.Collections.Generic.List[object]'

foreach ($target in $Targets) {
    $resolvedTarget = Join-Path $repoRoot $target
    if (-not (Test-Path -LiteralPath $resolvedTarget)) {
        continue
    }

    $files = Get-ChildItem -LiteralPath $resolvedTarget -Recurse -File -Include *.ps1,*.psm1
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $objectListMatches = [regex]::Matches(
            $content,
            '(?im)^\s*\$(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*New-Object\s+["'']System\.Collections\.Generic\.List\[object\]["'']'
        )

        foreach ($objectListMatch in $objectListMatches) {
            $variableName = $objectListMatch.Groups['name'].Value
            $escapedVariableName = [regex]::Escape($variableName)
            $unsafeReturn = [regex]::Match(
                $content,
                "(?im)^\s*return\s+@\(\`$$escapedVariableName\)"
            )

            if ($unsafeReturn.Success) {
                $lineNumber = ($content.Substring(0, $unsafeReturn.Index) -split "`r?`n").Count
                $violations.Add([pscustomobject]@{
                        File     = $file.FullName.Substring($repoRoot.Length + 1)
                        Line     = $lineNumber
                        Variable = $variableName
                    })
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'PowerShell generic-list materialization guardrail failed.' -ForegroundColor Red
    foreach ($violation in $violations) {
        Write-Host (" - {0}:{1} `${2}: use .ToArray() instead of @(`${2})" -f $violation.File, $violation.Line, $violation.Variable) -ForegroundColor Yellow
    }

    throw 'Unsafe List[object] materialization detected. PowerShell 7 can throw "Argument types do not match" for this pattern.'
}

Write-Host 'PowerShell generic-list materialization guardrail passed.' -ForegroundColor Green
