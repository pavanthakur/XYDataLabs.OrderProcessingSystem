function Invoke-Phase10AzCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $output = @(& az @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() })).Trim()
    }
}

function ConvertTo-Phase10SafeDiagnostic {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,

        [string[]]$SecretValues = @(),

        [int]$MaximumLength = 1200
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'Azure CLI returned no diagnostic text.'
    }

    $safeText = $Text
    foreach ($secretValue in @($SecretValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique)) {
        $safeText = $safeText.Replace($secretValue, '[REDACTED]')
    }

    $safeText = [regex]::Replace(
        $safeText,
        '(?i)(--value\s+)(?:"[^"]*"|''[^'']*''|\S+)',
        '$1[REDACTED]')
    $safeText = [regex]::Replace(
        $safeText,
        '(?i)((?:password|private[_-]?key|client[_-]?secret|token)\s*[=:]\s*)([^\s,;]+)',
        '$1[REDACTED]')
    $safeText = ($safeText -replace '[\r\n]+', ' ').Trim()

    if ($safeText.Length -gt $MaximumLength) {
        $safeText = $safeText.Substring(0, $MaximumLength) + '...'
    }

    return $safeText
}

function Get-Phase10KeyVaultSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KeyVaultName,
        [Parameter(Mandatory)][string]$SecretName,
        [string[]]$SecretValues = @(),
        [int]$Attempts = 3,
        [int]$DelaySeconds = 3
    )

    $lastDiagnostic = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $command = Invoke-Phase10AzCli -Arguments @(
            'keyvault', 'secret', 'show',
            '--vault-name', $KeyVaultName,
            '--name', $SecretName,
            '--query', 'value',
            '-o', 'tsv',
            '--only-show-errors'
        )

        if ($command.ExitCode -eq 0) {
            return [pscustomobject]@{
                State = 'Found'
                Value = $command.Output
                Diagnostic = ''
                Attempts = $attempt
            }
        }

        $lastDiagnostic = ConvertTo-Phase10SafeDiagnostic -Text $command.Output -SecretValues $SecretValues
        if ($lastDiagnostic -match '(?i)SecretNotFound|was not found|does not exist') {
            return [pscustomobject]@{
                State = 'Missing'
                Value = $null
                Diagnostic = $lastDiagnostic
                Attempts = $attempt
            }
        }

        if ($attempt -lt $Attempts) {
            Write-Host "Key Vault secret read retry ($attempt/$Attempts) for '$SecretName'. $lastDiagnostic"
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        State = 'Error'
        Value = $null
        Diagnostic = $lastDiagnostic
        Attempts = $Attempts
    }
}

function Set-Phase10KeyVaultSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KeyVaultName,
        [Parameter(Mandatory)][string]$SecretName,
        [Parameter(Mandatory)][string]$SecretValue,
        [string[]]$SecretValues = @(),
        [int]$Attempts = 3,
        [int]$DelaySeconds = 3
    )

    $lastDiagnostic = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $command = Invoke-Phase10AzCli -Arguments @(
            'keyvault', 'secret', 'set',
            '--vault-name', $KeyVaultName,
            '--name', $SecretName,
            '--value', $SecretValue,
            '--query', 'id',
            '-o', 'tsv',
            '--only-show-errors'
        )

        if ($command.ExitCode -eq 0) {
            return [pscustomobject]@{
                Succeeded = $true
                Diagnostic = "Azure Key Vault accepted the secret write on attempt $attempt."
                Attempts = $attempt
            }
        }

        $lastDiagnostic = ConvertTo-Phase10SafeDiagnostic `
            -Text $command.Output `
            -SecretValues (@($SecretValue) + $SecretValues)

        if ($attempt -lt $Attempts) {
            Write-Host "Key Vault secret write retry ($attempt/$Attempts) for '$SecretName'. $lastDiagnostic"
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    [pscustomobject]@{
        Succeeded = $false
        Diagnostic = $lastDiagnostic
        Attempts = $Attempts
    }
}

function Wait-Phase10KeyVaultSecretWriteAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KeyVaultName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$PrincipalObjectId,
        [int]$Attempts = 6,
        [int]$DelaySeconds = 10
    )

    $lastDiagnostic = 'Key Vault authorization metadata was not evaluated.'
    $observedPermissions = @()
    $authorizationMode = 'unknown'

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $command = Invoke-Phase10AzCli -Arguments @(
            'keyvault', 'show',
            '--name', $KeyVaultName,
            '--resource-group', $ResourceGroupName,
            '--query', 'properties',
            '-o', 'json',
            '--only-show-errors'
        )

        if ($command.ExitCode -ne 0) {
            $lastDiagnostic = ConvertTo-Phase10SafeDiagnostic -Text $command.Output
        }
        else {
            try {
                $properties = $command.Output | ConvertFrom-Json
                $authorizationMode = if ($properties.enableRbacAuthorization) { 'RBAC' } else { 'AccessPolicy' }

                if ($properties.enableRbacAuthorization) {
                    return [pscustomobject]@{
                        Succeeded = $true
                        AuthorizationMode = $authorizationMode
                        ObservedPermissions = @('data-plane role evaluated by secret write')
                        Diagnostic = 'Vault uses RBAC; the subsequent secret write is the authoritative data-plane permission check.'
                        Attempts = $attempt
                    }
                }

                $policy = @($properties.accessPolicies | Where-Object {
                        [string]::Equals([string]$_.objectId, $PrincipalObjectId, [StringComparison]::OrdinalIgnoreCase)
                    } | Select-Object -First 1)
                $observedPermissions = @($policy.permissions.secrets | ForEach-Object { ([string]$_).ToLowerInvariant() })
                $missingPermissions = @('get', 'list', 'set') | Where-Object { $observedPermissions -notcontains $_ }

                if ($missingPermissions.Count -eq 0) {
                    return [pscustomobject]@{
                        Succeeded = $true
                        AuthorizationMode = $authorizationMode
                        ObservedPermissions = $observedPermissions
                        Diagnostic = 'Deployment principal has get/list/set secret permissions at the vault scope.'
                        Attempts = $attempt
                    }
                }

                $lastDiagnostic = "Deployment principal '$PrincipalObjectId' is missing Key Vault secret permission(s): $($missingPermissions -join ', ')."
            }
            catch {
                $lastDiagnostic = "Key Vault authorization metadata could not be parsed: $($_.Exception.Message)"
            }
        }

        if ($attempt -lt $Attempts) {
            Write-Host "Key Vault secret-write authorization is not ready ($attempt/$Attempts). $lastDiagnostic"
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    [pscustomobject]@{
        Succeeded = $false
        AuthorizationMode = $authorizationMode
        ObservedPermissions = $observedPermissions
        Diagnostic = $lastDiagnostic
        Attempts = $Attempts
    }
}
