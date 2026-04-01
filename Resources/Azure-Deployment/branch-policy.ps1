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

        foreach ($propertyName in @('branch', 'environment', 'canonicalKey', 'resourceSuffix', 'configSuffix', 'databaseSuffix', 'azureSqlDatabaseSuffix', 'displayName')) {
            $value = $policy[$environmentKey][$propertyName]
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw "Branch policy entry '$environmentKey' is missing required property '$propertyName'."
            }
        }
    }

    return $policy
}

function Resolve-GitHubBranchPolicyKey {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentLike
    )

    if ([string]::IsNullOrWhiteSpace($EnvironmentLike)) {
        throw 'Environment value cannot be null or empty.'
    }

    $normalized = $EnvironmentLike.Trim().ToLowerInvariant()

    foreach ($policyKey in @('dev', 'staging', 'prod')) {
        $entry = $Policy[$policyKey]
        $candidates = @(
            $policyKey,
            $entry.branch,
            $entry.environment,
            $entry.canonicalKey,
            $entry.resourceSuffix,
            $entry.configSuffix,
            $entry.displayName
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }

        if ($candidates -contains $normalized) {
            return $policyKey
        }
    }

    throw "Environment value '$EnvironmentLike' does not match any branch policy entry."
}

function Get-GitHubBranchPolicyEntry {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentKey
    )

    $resolvedKey = Resolve-GitHubBranchPolicyKey -Policy $Policy -EnvironmentLike $EnvironmentKey
    return $Policy[$resolvedKey]
}

function Get-GitHubEnvironmentDescriptor {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentKey
    )

    $resolvedKey = Resolve-GitHubBranchPolicyKey -Policy $Policy -EnvironmentLike $EnvironmentKey
    $entry = $Policy[$resolvedKey]

    return [PSCustomObject]@{
        PolicyKey              = $resolvedKey
        Branch                 = $entry.branch
        GitHubEnvironment      = $entry.environment
        CanonicalKey           = $entry.canonicalKey
        ResourceSuffix         = $entry.resourceSuffix
        ConfigSuffix           = $entry.configSuffix
        DatabaseSuffix         = $entry.databaseSuffix
        AzureSqlDatabaseSuffix = $entry.azureSqlDatabaseSuffix
        DisplayName            = $entry.displayName
    }
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
