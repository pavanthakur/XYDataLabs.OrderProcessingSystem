function Get-GitHubBranchPolicy {
    param(
        [string]$PolicyFilePath = (Join-Path $PSScriptRoot 'branch-policy.json')
    )

    if (-not (Test-Path $PolicyFilePath)) {
        throw "Branch policy file not found: $PolicyFilePath"
    }

    try {
        $policy = Get-Content -Path $PolicyFilePath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse branch policy file '$PolicyFilePath': $($_.Exception.Message)"
    }

    foreach ($environmentKey in @('dev', 'staging', 'prod')) {
        if (-not $policy.ContainsKey($environmentKey)) {
            throw "Branch policy is missing required environment key '$environmentKey'."
        }

        foreach ($propertyName in @('branch', 'environment')) {
            $value = $policy[$environmentKey][$propertyName]
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw "Branch policy entry '$environmentKey' is missing required property '$propertyName'."
            }
        }
    }

    return $policy
}

function Get-GitHubBranchPolicyEntry {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'staging', 'prod')]
        [string]$EnvironmentKey
    )

    return $Policy[$EnvironmentKey]
}

function Get-GitHubBranchList {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy
    )

    $branches = New-Object 'System.Collections.Generic.List[string]'
    foreach ($environmentKey in @('dev', 'staging', 'prod')) {
        $branch = $Policy[$environmentKey].branch
        if (-not [string]::IsNullOrWhiteSpace($branch) -and -not $branches.Contains($branch)) {
            $branches.Add($branch)
        }
    }

    return $branches.ToArray()
}

function Get-GitHubEnvironmentList {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy
    )

    $environments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($environmentKey in @('dev', 'staging', 'prod')) {
        $environmentName = $Policy[$environmentKey].environment
        if (-not [string]::IsNullOrWhiteSpace($environmentName) -and -not $environments.Contains($environmentName)) {
            $environments.Add($environmentName)
        }
    }

    return $environments.ToArray()
}
