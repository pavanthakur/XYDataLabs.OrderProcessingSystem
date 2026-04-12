#Requires -Version 7.0
<#!
.SYNOPSIS
    Fails when generated build or report output is tracked by Git.

.DESCRIPTION
    Audits tracked repository paths via `git ls-files` and rejects common generated
    artifact locations that should stay ignored, such as frontend dist output,
    publish folders, and automation report folders.

    Intentional source assets that participate in packaging remain allowlisted,
    such as `frontend/apps/web/public/web.config`.

.EXAMPLE
    .\scripts\validate-tracked-generated-artifacts.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$allowedPaths = @(
    'automation/reports/.gitignore',
    'frontend/apps/web/public/web.config'
)

$rules = @(
    @{
        Name = 'frontend dist output'
        Pattern = '^frontend/.+/dist/'
    },
    @{
        Name = 'publish output'
        Pattern = '(^|/)publish/'
    },
    @{
        Name = 'automation reports output'
        Pattern = '^automation/reports/'
    }
)

Push-Location $repoRoot
try {
    $trackedFiles = & git ls-files
    if ($LASTEXITCODE -ne 0) {
        throw 'git ls-files failed.'
    }
}
finally {
    Pop-Location
}

$violations = @()

foreach ($trackedFile in $trackedFiles) {
    $normalizedPath = ([string] $trackedFile).Replace('\', '/')

    if ($allowedPaths -contains $normalizedPath) {
        continue
    }

    foreach ($rule in $rules) {
        if ($normalizedPath -match $rule.Pattern) {
            $violations += [PSCustomObject] @{
                Path = $normalizedPath
                Category = $rule.Name
            }
            break
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Tracked generated artifacts were found:' -ForegroundColor Red
    foreach ($violation in $violations | Sort-Object Path -Unique) {
        Write-Host " - [$($violation.Category)] $($violation.Path)" -ForegroundColor Red
    }

    Write-Host ''
    Write-Host 'Remove these files from Git tracking and keep only the source assets committed.' -ForegroundColor Yellow
    Write-Host 'Expected tracked example: frontend/apps/web/public/web.config' -ForegroundColor Yellow
    Write-Host 'Expected ignored examples: frontend/apps/web/dist/** and automation/reports/**' -ForegroundColor Yellow
    exit 1
}

Write-Host 'No tracked generated artifacts found.' -ForegroundColor Green
exit 0