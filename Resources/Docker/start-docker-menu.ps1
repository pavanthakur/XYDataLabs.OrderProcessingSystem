<#
.SYNOPSIS
    Interactive launcher for the XY Order Processing System.
    Works from Visual Studio F5, VS Code terminal, or double-click.
    Shows a numbered menu — pick a number, press Enter — the script
    starts both API and UI for you automatically.

.PARAMETER Choice
    Pre-select a menu option (1-8, 0, Q) without the interactive prompt.
    Used by the /XYDataLabs-docker-start Copilot Chat prompt and automation.

.EXAMPLE
    .\start-docker-menu.ps1              # interactive menu
    .\start-docker-menu.ps1 -Choice 1   # Dev HTTP Docker, no prompt
    .\start-docker-menu.ps1 -Choice 7   # Local HTTP dotnet run, no prompt
    .\start-docker-menu.ps1 -Choice 0   # open the stop sub-menu
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$Choice = ""
)

# --- Concurrent-launch guard ---------------------------------------------------
# Visual Studio spawns one powershell.exe per project in a multi-project launch
# profile. Without this guard two identical menus appear simultaneously.
# The second process detects the lock and exits gracefully after 3 seconds.
$menuLockFile       = Join-Path $env:TEMP "xy-docker-menu.lock"
$menuLockTimeoutSec = 600   # auto-release after 10 min (crashed process safety)
$acquiredMenuLock   = $false

if (Test-Path $menuLockFile) {
    $lockAge = (Get-Date) - (Get-Item $menuLockFile).LastWriteTime
    if ($lockAge.TotalSeconds -lt $menuLockTimeoutSec) {
        Write-Host ""
        Write-Host "  Docker Launcher is already open in another window." -ForegroundColor Yellow
        Write-Host "  This window will close in 3 seconds..." -ForegroundColor DarkGray
        Write-Host ""
        Start-Sleep -Seconds 3
        exit 0
    }
    Remove-Item $menuLockFile -Force -ErrorAction SilentlyContinue
}

try {
    New-Item $menuLockFile -ItemType File -Force | Out-Null
    $acquiredMenuLock = $true
} catch {}

# --- Paths ---------------------------------------------------------------------
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$solutionRoot = (Resolve-Path (Join-Path $scriptDir "../..")).Path
$startDocker  = Join-Path $scriptDir "start-docker.ps1"

# --- Menu display --------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  +====================================================================+" -ForegroundColor Cyan
    Write-Host "  |         XY Order Processing System  --  Launch Menu               |" -ForegroundColor Cyan
    Write-Host "  +====================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  What do you want to start?" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- DOCKER  (full containers, matches Azure deployment) -------------" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  [1]  Dev . HTTP    API: http://localhost:5020/swagger" -ForegroundColor White
    Write-Host "                     UI:  http://localhost:5022" -ForegroundColor DarkGray
    Write-Host "       ^ Recommended for daily development" -ForegroundColor Green
    Write-Host ""
    Write-Host "  [2]  Dev . HTTPS   API: https://localhost:5021/swagger" -ForegroundColor White
    Write-Host "                     UI:  https://localhost:5023" -ForegroundColor DarkGray
    Write-Host "       Use when testing HTTPS-specific behaviour" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3]  Stg . HTTP    API: http://localhost:5030/swagger" -ForegroundColor White
    Write-Host "                     UI:  http://localhost:5032" -ForegroundColor DarkGray
    Write-Host "       Staging config -- validate before pushing to Azure staging" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  [4]  Stg . HTTPS   API: https://localhost:5031/swagger" -ForegroundColor White
    Write-Host "                     UI:  https://localhost:5033" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [5]  Prod . HTTP   API: http://localhost:5040/swagger   /!\ prod config" -ForegroundColor Yellow
    Write-Host "                     UI:  http://localhost:5042" -ForegroundColor DarkGray
    Write-Host "       Only for local prod smoke-testing -- uses production settings" -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "  [6]  Prod . HTTPS  API: https://localhost:5041/swagger  /!\ prod config" -ForegroundColor Yellow
    Write-Host "                     UI:  https://localhost:5043" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  -- PLAIN .NET  (no Docker, fastest startup, full VS debugger) -----" -ForegroundColor DarkBlue
    Write-Host ""
    Write-Host "  [7]  Local . HTTP   API: http://localhost:5010/swagger" -ForegroundColor White
    Write-Host "                      UI:  http://localhost:5012" -ForegroundColor DarkGray
    Write-Host "       Opens two terminal windows (dotnet run for API + UI)" -ForegroundColor DarkGray
    Write-Host "       For breakpoints/hot-reload: use VS F5 'Http Profile' instead" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [8]  Local . HTTPS  API: https://localhost:5011/swagger" -ForegroundColor White
    Write-Host "                      UI:  https://localhost:5013" -ForegroundColor DarkGray
    Write-Host "       For breakpoints/hot-reload: use VS F5 'Https Profile' instead" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  -- STOP / QUIT --------------------------------------------------- " -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0]  Stop a running Docker stack (will ask which one)" -ForegroundColor White
    Write-Host "  [Q]  Quit -- close this window without starting anything" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ---------------------------------------------------------------------" -ForegroundColor DarkGray
}

# --- Docker runner -------------------------------------------------------------
function Invoke-Docker {
    param([string]$Env, [string]$Prof, [switch]$Down)
    Set-Location $scriptDir
    if ($Down) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startDocker `
            -Environment $Env -Profile $Prof -Down
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startDocker `
            -Environment $Env -Profile $Prof -NoPrePull
    }
}

# --- Plain .NET runner ---------------------------------------------------------
function Start-PlainDotNet {
    param([string]$LaunchProfile)

    $apiProject = Join-Path $solutionRoot "XYDataLabs.OrderProcessingSystem.API"
    $uiProject  = Join-Path $solutionRoot "XYDataLabs.OrderProcessingSystem.UI"
    $apiUrl     = if ($LaunchProfile -eq "http") { "http://localhost:5010/swagger"  } else { "https://localhost:5011/swagger" }
    $uiUrl      = if ($LaunchProfile -eq "http") { "http://localhost:5012"          } else { "https://localhost:5013" }

    Write-Host ""
    Write-Host "  Starting API and UI in separate terminal windows..." -ForegroundColor Cyan

    # Write temp launcher scripts so quoting stays clean across process boundaries
    $apiScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    $uiScript  = [System.IO.Path]::GetTempFileName() + ".ps1"

    Set-Content -Path $apiScript -Value @"
`$host.UI.RawUI.WindowTitle = 'XY API ($LaunchProfile)'
Write-Host '  XY Order Processing -- API ($LaunchProfile)' -ForegroundColor Cyan
Write-Host '  $apiUrl' -ForegroundColor White
Write-Host ''
Set-Location '$solutionRoot'
dotnet run --project '$apiProject' --launch-profile $LaunchProfile
Write-Host ''
Write-Host '  API process ended. Press any key to close...' -ForegroundColor Yellow
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Set-Content -Path $uiScript -Value @"
`$host.UI.RawUI.WindowTitle = 'XY UI ($LaunchProfile)'
Write-Host '  XY Order Processing -- UI ($LaunchProfile)' -ForegroundColor Cyan
Write-Host '  $uiUrl' -ForegroundColor White
Write-Host ''
Set-Location '$solutionRoot'
dotnet run --project '$uiProject' --launch-profile $LaunchProfile
Write-Host ''
Write-Host '  UI process ended. Press any key to close...' -ForegroundColor Yellow
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $apiScript
    Start-Sleep -Seconds 2   # slight stagger -- prevents both processes racing DB init
    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $uiScript

    Write-Host ""
    Write-Host "  API  -->  $apiUrl" -ForegroundColor White
    Write-Host "  UI   -->  $uiUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "  TIP: For VS debugger (breakpoints, hot reload, diagnostics):" -ForegroundColor Yellow
    Write-Host "       Close those windows and use VS F5 with '$LaunchProfile' profile instead." -ForegroundColor Yellow
}

# --- Stop sub-menu -------------------------------------------------------------
function Show-StopMenu {
    Write-Host ""
    Write-Host "  Which Docker stack do you want to stop?" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1] Dev  . HTTP     [2] Dev  . HTTPS" -ForegroundColor White
    Write-Host "    [3] Stg  . HTTP     [4] Stg  . HTTPS" -ForegroundColor White
    Write-Host "    [5] Prod . HTTP     [6] Prod . HTTPS" -ForegroundColor White
    Write-Host "    [A] Stop all of the above" -ForegroundColor White
    Write-Host ""
    $stopChoice = Read-Host "  Enter choice"

    $stopMap = @{
        "1" = @{ Env = "dev";  Prof = "http"  }
        "2" = @{ Env = "dev";  Prof = "https" }
        "3" = @{ Env = "stg";  Prof = "http"  }
        "4" = @{ Env = "stg";  Prof = "https" }
        "5" = @{ Env = "prod"; Prof = "http"  }
        "6" = @{ Env = "prod"; Prof = "https" }
    }

    if ($stopChoice.Trim().ToUpper() -eq "A") {
        foreach ($entry in $stopMap.Values) {
            Invoke-Docker -Env $entry.Env -Prof $entry.Prof -Down
        }
    } elseif ($stopMap.ContainsKey($stopChoice.Trim())) {
        $entry = $stopMap[$stopChoice.Trim()]
        Invoke-Docker -Env $entry.Env -Prof $entry.Prof -Down
    } else {
        Write-Host "  No action taken." -ForegroundColor DarkGray
    }
}

# --- Main ----------------------------------------------------------------------
try {
    Show-Menu

    if ([string]::IsNullOrWhiteSpace($Choice)) {
        $Choice = Read-Host "  Enter choice (default = 1)"
        if ([string]::IsNullOrWhiteSpace($Choice)) { $Choice = "1" }
    } else {
        Write-Host "  Pre-selected: $Choice" -ForegroundColor DarkGray
    }

    Write-Host ""

    switch ($Choice.Trim().ToUpper()) {
        "1" { Invoke-Docker    -Env dev  -Prof http  }
        "2" { Invoke-Docker    -Env dev  -Prof https }
        "3" { Invoke-Docker    -Env stg  -Prof http  }
        "4" { Invoke-Docker    -Env stg  -Prof https }
        "5" { Invoke-Docker    -Env prod -Prof http  }
        "6" { Invoke-Docker    -Env prod -Prof https }
        "7" { Start-PlainDotNet -LaunchProfile http  }
        "8" { Start-PlainDotNet -LaunchProfile https }
        "0" { Show-StopMenu }
        "Q" { Write-Host "  Cancelled. No action taken." -ForegroundColor DarkGray }
        default {
            Write-Host "  '$Choice' is not a valid option. Run the script again and choose 1-8, 0, or Q." -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Press any key to close this window..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} finally {
    if ($acquiredMenuLock) { Remove-Item $menuLockFile -Force -ErrorAction SilentlyContinue }
}
