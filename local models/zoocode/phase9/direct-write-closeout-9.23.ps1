param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
)

$runPhase9 = Join-Path $RepoRoot 'local models\zoocode\phase9\run-phase9.ps1'
$closeoutDoc = Join-Path $RepoRoot 'local models\zoocode\phase9\phase9-closeout.md'
$remediationDoc = Join-Path $RepoRoot 'local models\zoocode\phase9\phase9-remediation-handover-plan.md'
$folderPolicy = Join-Path $RepoRoot 'local models\zoocode\phase9\folder-policy.md'

$closeoutContent = @'
# Phase 9 Closeout

## Purpose

Use this note as the single handoff reference for the Phase 9 final acceptance run.

## Acceptance Order

1. Build the solution cleanly.
2. Run architecture tests.
3. Run gateway tests.
4. Run integration tests.
5. Run Playwright end-to-end verification.
6. Review warnings separately from failures.
7. Close Phase 9 only when every required gate is green.

## Current Closure Rule

- Keep the Phase 9 closure lane direct-write only.
- Keep `9.21`, `9.22`, and `9.23` focused on topology, identity portability, and runner hygiene.
- Do not reintroduce aider-style edit paths for closure slices.

## Command Sequence

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem

dotnet build XYDataLabs.OrderProcessingSystem.sln --no-restore

dotnet test tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj --no-restore

dotnet test tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj --no-restore

dotnet test tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --no-restore

powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-cold-bootstrap.ps1" -DockerStartupTimeoutSeconds 300 -StabilizationDelaySeconds 180
```

## Closeout Rule

Do not mark Phase 9 complete until:

- the solution build succeeds,
- architecture tests pass,
- gateway tests pass,
- integration tests pass,
- Playwright end-to-end verification completes,
- and any warnings or deferred items are explicitly recorded.
'@

$remediationContent = Get-Content -LiteralPath $remediationDoc -Raw
if ($remediationContent -notmatch 'Concrete Closure Plan') {
    $remediationContent += "`r`n`r`nClosure evidence is recorded through the direct-write runner and the final closeout gates above."
}

$folderPolicyContent = Get-Content -LiteralPath $folderPolicy -Raw
if ($folderPolicyContent -notmatch 'Direct-write closure slices') {
    $folderPolicyContent += @"

## 8. Direct-Write Closure Slices

- `9.21`, `9.22`, and `9.23` must use direct-write scripts only.
- Do not route these slices through aider-style edit instructions.
- Keep their artifacts in `local models\zoocode\phase9\_temp`.
"@
}

[System.IO.File]::WriteAllText($closeoutDoc, $closeoutContent, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($remediationDoc, $remediationContent, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($folderPolicy, $folderPolicyContent, [System.Text.UTF8Encoding]::new($false))

Write-Host "Direct writer completed for Phase 9.23 closeout files."
