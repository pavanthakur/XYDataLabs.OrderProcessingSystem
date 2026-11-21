function Get-ReplayDrillEnvironmentValue {
    param([object[]]$EnvironmentVariables, [string]$Name)

    $entries = @($EnvironmentVariables | Where-Object { $_.name -eq $Name })
    if ($entries.Count -gt 1) { return [pscustomobject]@{ count = $entries.Count; value = $null } }
    if ($entries.Count -eq 0) { return [pscustomobject]@{ count = 0; value = $null } }
    return [pscustomobject]@{ count = 1; value = [string]$entries[0].value }
}
