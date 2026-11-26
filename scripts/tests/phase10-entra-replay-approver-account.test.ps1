$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $root 'scripts/phase10-entra-replay-approver-account.ps1'
$roleScriptPath = Join-Path $root 'scripts/phase10-entra-replay-approver.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$roleSource = Get-Content -LiteralPath $roleScriptPath -Raw
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Account provisioner has PowerShell parse errors: $($parseErrors.Message -join '; ')" }

foreach ($required in @(
    "ValidateSet('Plan','Apply','Verify')",
    'phase10-replay-approver@pavanthakurgmail.onmicrosoft.com',
    'CREATE DEV REPLAY APPROVER',
    "Read-Host 'Enter a unique temporary password",
    '-AsSecureString',
    'User.ReadWrite.All',
    'forceChangePasswordNextSignIn=$true',
    '$claimBody[$extensionName] = ''TenantA''',
    'emailsSent=0',
    'credentialsStored=$false',
    'ShouldProcess',
    'awaiting-operator-confirmation',
    'Preflight passed. No directory changes have happened yet.',
    'Enter the unique temporary password at the secure prompt.',
    'Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false'
)) {
    if (-not $source.Contains($required)) { throw "Account provisioner is missing required safety contract: $required" }
}
if ($source -match 'sendMail|/sendMail|inviteRedeemUrl|passwordLogged\s*=\s*\$true') { throw 'Account provisioner contains an unexpected mail or credential disclosure path.' }
$extensionDeclaration = $source.IndexOf('$extensionName = "extension_$($apiClientId.ToString(''N''))_applicationTenantCode"')
$extensionUse = $source.IndexOf('$_.name -ceq $extensionName')
if ($extensionDeclaration -lt 0 -or $extensionUse -lt 0 -or $extensionDeclaration -gt $extensionUse) { throw 'API tenant-claim extension must be initialized before the extension preflight.' }
if (-not $roleSource.Contains('''AppRoleAssignment.ReadWrite.All'' -notin $graphGrants')) { throw 'Role assignment does not fail closed on missing Graph permission.' }
Write-Host 'Phase 10 replay approver account provisioner safety contracts passed.'
