#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap local development environment. Run once after a fresh clone.

.DESCRIPTION
    Performs all first-time setup needed to develop and run this project locally:
      1. Creates Resources/Docker/.env.local — prompts for passwords on first run,
         reads them from the existing file on subsequent runs.
      2. Sets dotnet user-secrets for VS F5 and dotnet run (API + UI projects)
      3. Trusts the HTTPS development certificate

    .env.local is the single source of truth for local passwords. All steps derive
    passwords from it — no hardcoded defaults, no parameters to pass.

    This script is idempotent: re-running it reads from the existing .env.local and
    re-applies user-secrets and cert without prompting again.
    Use -Force to re-prompt for passwords and overwrite everything.

.PARAMETER Force
    Re-prompt for passwords, recreate .env.local, and overwrite dotnet user-secrets
    and the dev certificate even if they already exist.

.EXAMPLE
    # First-time setup — prompts for SQL and cert passwords
    .\scripts\setup-local.ps1

.EXAMPLE
    # Re-run and overwrite everything (e.g. after a password change)
    .\scripts\setup-local.ps1 -Force

.NOTES
    After running this script:
      - F5 in Visual Studio 2022 is ready immediately (no prompts).
      - Docker: .\Resources\Docker\start-docker.ps1 -Environment dev -Profile http
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Paths ───────────────────────────────────────────────────────────────────
$root       = Split-Path $PSScriptRoot -Parent
$envExample = Join-Path $root 'Resources\Docker\.env.local.example'
$envLocal   = Join-Path $root 'Resources\Docker\.env.local'
$certFile   = Join-Path $root 'Resources\Certificates\aspnetapp.pfx'
$apiCsproj  = Join-Path $root 'XYDataLabs.OrderProcessingSystem.API\XYDataLabs.OrderProcessingSystem.API.csproj'
$uiCsproj   = Join-Path $root 'XYDataLabs.OrderProcessingSystem.UI\XYDataLabs.OrderProcessingSystem.UI.csproj'

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Write-Step([string] $msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Done([string] $msg) { Write-Host "    [ok]  $msg" -ForegroundColor Green }
function Write-Skip([string] $msg) { Write-Host "    [--]  $msg (already done — skip)" -ForegroundColor DarkGray }

function Read-Password([string] $prompt) {
    $ss = Read-Host -Prompt $prompt -AsSecureString
    [System.Net.NetworkCredential]::new('', $ss).Password
}

function Read-EnvLocal([string] $path) {
    $vars = @{}
    Get-Content $path | Where-Object { $_ -match '^[A-Z]' } | ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) { $vars[$parts[0].Trim()] = $parts[1].Trim() }
    }
    $vars
}

# ─── 1. Docker .env.local ─────────────────────────────────────────────────────
Write-Step 'Docker secrets — Resources/Docker/.env.local'

if ((Test-Path $envLocal) -and -not $Force) {
    Write-Skip '.env.local already exists — reading passwords from it'
    $envVars         = Read-EnvLocal $envLocal
    $certPassword    = $envVars['LOCAL_CERT_PASSWORD']
    $sqlPassword     = $envVars['LOCAL_SQL_PASSWORD']
    $openpayMerchant = $envVars['LOCAL_OPENPAY_MERCHANT_ID']
    $openpayKey      = $envVars['LOCAL_OPENPAY_PRIVATE_KEY']
    $openpaySession  = $envVars['LOCAL_OPENPAY_DEVICE_SESSION_ID']
}
else {
    if (-not (Test-Path $envExample)) {
        Write-Error "Expected template not found: $envExample"
    }

    Write-Host '  Choose passwords for your local sandbox — you are setting these for the first time.' -ForegroundColor Yellow
    Write-Host '  They will be saved to .env.local and used for every subsequent run.' -ForegroundColor Yellow
    Write-Host '  SQL Server requires: 8+ chars, uppercase, lowercase, digit, special char (e.g. MyLocal1!)' -ForegroundColor DarkGray
    Write-Host ''
    $sqlPassword  = Read-Password '  Choose SQL Server password (LOCAL_SQL_PASSWORD) '
    $certPassword = Read-Password '  Choose HTTPS cert password (LOCAL_CERT_PASSWORD) '

    Write-Host ''
    Write-Host '  OpenPay sandbox credentials — fetching from Key Vault kv-orderproc-dev...' -ForegroundColor Yellow
    $openpayMerchant = $null
    $openpayKey      = $null
    $openpaySession  = 'default-device-session'

    $azAvailable = Get-Command az -ErrorAction SilentlyContinue
    if ($azAvailable) {
        try {
            $kvMerchant = az keyvault secret show --vault-name kv-orderproc-dev --name 'OpenPay--MerchantId' --query value -o tsv 2>$null
            $kvKey      = az keyvault secret show --vault-name kv-orderproc-dev --name 'OpenPay--PrivateKey'  --query value -o tsv 2>$null
            if ($kvMerchant -and $kvKey -and
                $kvMerchant -notmatch '^set-openpay' -and $kvKey -notmatch '^set-openpay') {
                $openpayMerchant = $kvMerchant.Trim()
                $openpayKey      = $kvKey.Trim()
                Write-Done 'OpenPay credentials fetched from kv-orderproc-dev'
            } else {
                Write-Host '  [--]  Key Vault returned placeholder values — falling back to prompt.' -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [--]  Could not read from Key Vault: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  [--]  az CLI not found — skipping Key Vault fetch.' -ForegroundColor DarkGray
    }

    if (-not $openpayMerchant) {
        Write-Host ''
        Write-Host '  ┌─────────────────────────────────────────────────────────────────┐' -ForegroundColor Cyan
        Write-Host '  │  OpenPay sandbox credentials — manual step required             │' -ForegroundColor Cyan
        Write-Host '  ├─────────────────────────────────────────────────────────────────┤' -ForegroundColor Cyan
        Write-Host '  │  1. Open https://sandbox-dashboard.openpay.mx                   │' -ForegroundColor Cyan
        Write-Host '  │  2. Log in to your sandbox account                              │' -ForegroundColor Cyan
        Write-Host '  │  3. On the home/dashboard page you will see:                    │' -ForegroundColor Cyan
        Write-Host '  │       Merchant ID  — a short alphanumeric string (e.g. m...)    │' -ForegroundColor Cyan
        Write-Host '  │       Private key  — starts with sk_...                         │' -ForegroundColor Cyan
        Write-Host '  │  4. Paste both below.                                           │' -ForegroundColor Cyan
        Write-Host '  │                                                                 │' -ForegroundColor Cyan
        Write-Host '  │  These are stored in .env.local (gitignored) and user-secrets.  │' -ForegroundColor Cyan
        Write-Host '  │  You will NOT be asked again on subsequent runs.                │' -ForegroundColor Cyan
        Write-Host '  │                                                                 │' -ForegroundColor Cyan
        Write-Host '  │  To store them in Azure Key Vault so future team members and    │' -ForegroundColor Cyan
        Write-Host '  │  machines get them automatically, run once after pasting:       │' -ForegroundColor Cyan
        Write-Host '  │    .\Resources\Azure-Deployment\populate-keyvault-secrets.ps1   │' -ForegroundColor Cyan
        Write-Host '  │        -Environment dev                                         │' -ForegroundColor Cyan
        Write-Host '  │        -OpenPayMerchantId <id> -OpenPayPrivateKey <key>         │' -ForegroundColor Cyan
        Write-Host '  │                                                                 │' -ForegroundColor Cyan
        Write-Host '  │  Leave blank to skip — payment calls will fail (error 1002)     │' -ForegroundColor Cyan
        Write-Host '  │  until credentials are set.                                     │' -ForegroundColor Cyan
        Write-Host '  └─────────────────────────────────────────────────────────────────┘' -ForegroundColor Cyan
        Write-Host ''
        $openpayMerchant = (Read-Host '  OpenPay Merchant ID (LOCAL_OPENPAY_MERCHANT_ID) ').Trim()
        $openpayKey      = (Read-Host '  OpenPay Private Key (LOCAL_OPENPAY_PRIVATE_KEY)  ').Trim()
        if ([string]::IsNullOrWhiteSpace($openpayMerchant)) { $openpayMerchant = 'local-sandbox-only' }
        if ([string]::IsNullOrWhiteSpace($openpayKey))      { $openpayKey      = 'local-sandbox-only' }
    }

    $content = @"
# Local Docker secrets — auto-generated by setup-local.ps1
# Gitignored. Re-run setup-local.ps1 -Force to change passwords.
LOCAL_SQL_PASSWORD=$sqlPassword
LOCAL_CERT_PASSWORD=$certPassword
LOCAL_OPENPAY_MERCHANT_ID=$openpayMerchant
LOCAL_OPENPAY_PRIVATE_KEY=$openpayKey
LOCAL_OPENPAY_DEVICE_SESSION_ID=$openpaySession
"@
    Set-Content -Path $envLocal -Value $content -Encoding UTF8
    Write-Done 'Created .env.local'
}

# ─── 2. dotnet user-secrets (API) ─────────────────────────────────────────────
Write-Step 'dotnet user-secrets — API project'

$apiSecrets = [ordered]@{
    'ApiSettings:API:https:CertPassword' = $certPassword
    'OpenPay:MerchantId'                 = $openpayMerchant
    'OpenPay:PrivateKey'                 = $openpayKey
    'OpenPay:DeviceSessionId'            = $openpaySession
}

foreach ($kv in $apiSecrets.GetEnumerator()) {
    if ($PSCmdlet.ShouldProcess("API user-secrets: $($kv.Key)")) {
        dotnet user-secrets set $kv.Key $kv.Value --project $apiCsproj | Out-Null
        Write-Done "API  $($kv.Key)"
    }
}

# ─── 3. dotnet user-secrets (UI) ──────────────────────────────────────────────
Write-Step 'dotnet user-secrets — UI project'

if ($PSCmdlet.ShouldProcess("UI user-secrets: ApiSettings:UI:https:CertPassword")) {
    dotnet user-secrets set 'ApiSettings:UI:https:CertPassword' $certPassword --project $uiCsproj | Out-Null
    Write-Done "UI   ApiSettings:UI:https:CertPassword"
}

# ─── 4. HTTPS dev certificate ─────────────────────────────────────────────────
Write-Step 'HTTPS development certificate'

$certOutput = dotnet dev-certs https --check --quiet 2>&1
$certAlreadyTrusted = ($LASTEXITCODE -eq 0)

# Always (re-)export the PFX with the current LOCAL_CERT_PASSWORD so the file stays
# in sync with .env.local — even if the system cert is already trusted.
# Skipping this step when already trusted was the root cause of cert password mismatch
# on stg/https profiles: the file had an old password but .env.local had a new one.
if ($PSCmdlet.ShouldProcess('HTTPS dev cert — export to PFX')) {
    dotnet dev-certs https --export-path $certFile --password $certPassword | Out-Null
    Write-Done "Cert exported to Resources/Certificates/aspnetapp.pfx (password synced with .env.local)"
}

if ($certAlreadyTrusted -and -not $Force) {
    Write-Skip 'dev cert already trusted'
}
else {
    if ($PSCmdlet.ShouldProcess('HTTPS dev cert — trust')) {
        dotnet dev-certs https --trust
        Write-Done "Dev cert trusted"
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  Local setup complete!' -ForegroundColor Green
Write-Host ''
Write-Host '  Visual Studio F5 (http/https profile — no docker-* profiles):'
Write-Host '    API  http://localhost:5010/swagger'
Write-Host '    UI   http://localhost:5012'
Write-Host ''
Write-Host '  Docker dev:'
Write-Host '    .\Resources\Docker\start-docker.ps1 -Environment dev -Profile http'
Write-Host ''
  if ($openpayMerchant -eq 'local-sandbox-only') {
      Write-Host '  OpenPay sandbox credentials were skipped. To add them later, run:' -ForegroundColor Yellow
      Write-Host '    .\scripts\setup-local.ps1 -Force' -ForegroundColor DarkGray
  }
Write-Host ''
