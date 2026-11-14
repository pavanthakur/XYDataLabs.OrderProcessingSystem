# Helpers for a single-run Azure SQL firewall lease. The caller must pass an
# injected CLI function in tests; production invokes the az executable.
function Get-Phase10FirewallRuleName {
    param(
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Attempt,
        [Parameter(Mandatory)][string]$InvocationId
    )

    $safeParts = @($Environment, $RunId, $Attempt, $InvocationId) | ForEach-Object {
        ([regex]::Replace($_.ToLowerInvariant(), '[^a-z0-9-]', '-').Trim('-'))
    }
    $suffix = ($safeParts -join '-')
    $name = "p10-$suffix"
    if ($name.Length -gt 128) {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($name))).Substring(0, 16).ToLowerInvariant()
        $name = $name.Substring(0, 111).TrimEnd('-') + "-$hash"
    }

    return $name
}

function Get-Phase10FirewallRuleState {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$RuleName,
        [Parameter(Mandatory)][scriptblock]$InvokeAz
    )

    $output = & $InvokeAz @('sql','server','firewall-rule','show','--resource-group',$ResourceGroup,'--server',$Server,'--name',$RuleName,'--output','json')
    if ($LASTEXITCODE -eq 0) {
        if ([string]::IsNullOrWhiteSpace(($output | Out-String))) { throw "Firewall rule lookup returned empty data for '$RuleName'." }
        try { return ($output | Out-String | ConvertFrom-Json -ErrorAction Stop) } catch { throw "Firewall rule lookup returned invalid data for '$RuleName'." }
    }

    $message = ($output | Out-String)
    if ($message -match '(?i)(ResourceNotFound|FirewallRuleNotFound|was not found|could not be found)') { return $null }
    throw "Cannot establish firewall rule state for '$RuleName'; Azure returned an error."
}

function New-Phase10FirewallLease {
    param(
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$PublicIp,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Attempt,
        [Parameter(Mandatory)][string]$InvocationId,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][scriptblock]$InvokeAz
    )

    $name = Get-Phase10FirewallRuleName -Environment $Environment -RunId $RunId -Attempt $Attempt -InvocationId $InvocationId
    if ($null -ne (Get-Phase10FirewallRuleState -ResourceGroup $ResourceGroup -Server $Server -RuleName $name -InvokeAz $InvokeAz)) {
        throw "Firewall rule name collision for '$name'; refusing to modify an existing rule."
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        environment = $Environment
        subscriptionId = $SubscriptionId
        resourceGroup = $ResourceGroup
        sqlServer = $Server
        ruleName = $name
        runId = $RunId
        attempt = $Attempt
        invocationId = $InvocationId
        publicIp = $PublicIp
        state = 'creation-intent'
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $parent = Split-Path -Parent $ManifestPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8

    $result = & $InvokeAz @('sql','server','firewall-rule','create','--resource-group',$ResourceGroup,'--server',$Server,'--name',$name,'--start-ip-address',$PublicIp,'--end-ip-address',$PublicIp,'--output','json')
    $createExit = $LASTEXITCODE
    if ($createExit -ne 0) {
        $manifest.state = 'creation-ambiguous'
        $manifest.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
        # Reconcile this exact name; never retry create and never delete an
        # unverified object after an ambiguous CLI response.
        $created = Get-Phase10FirewallRuleState -ResourceGroup $ResourceGroup -Server $Server -RuleName $name -InvokeAz $InvokeAz
        if ($null -eq $created -or $created.startIpAddress -ne $PublicIp -or $created.endIpAddress -ne $PublicIp) {
            throw "Firewall creation failed and ownership of '$name' could not be proven; recovery manifest retained at '$ManifestPath'."
        }
    }

    $verified = Get-Phase10FirewallRuleState -ResourceGroup $ResourceGroup -Server $Server -RuleName $name -InvokeAz $InvokeAz
    if ($null -eq $verified -or $verified.startIpAddress -ne $PublicIp -or $verified.endIpAddress -ne $PublicIp) {
        throw "Created firewall rule '$name' did not match the requested IP; recovery manifest retained at '$ManifestPath'."
    }
    $manifest.state = 'created'
    $manifest.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
    return [pscustomobject]@{ RuleName = $name; ManifestPath = $ManifestPath }
}

function Remove-Phase10FirewallLease {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][scriptblock]$InvokeAz,
        [int]$MaxAttempts = 3
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw 'Firewall lease manifest is missing; refusing cleanup without ownership evidence.' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.schemaVersion -eq 1 -and $manifest.state -eq 'removed') { return }
    if ($manifest.schemaVersion -ne 1 -or $manifest.state -notin @('creation-intent','created','creation-ambiguous','cleanup-pending')) {
        throw 'Firewall lease manifest does not prove ownership of a created rule; refusing cleanup.'
    }

    $manifest.state = 'cleanup-pending'
    $manifest.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $existing = Get-Phase10FirewallRuleState -ResourceGroup $manifest.resourceGroup -Server $manifest.sqlServer -RuleName $manifest.ruleName -InvokeAz $InvokeAz
        if ($null -eq $existing) {
            $manifest.state = 'removed'
            $manifest.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
            return
        }
        if ($existing.startIpAddress -ne $manifest.publicIp -or $existing.endIpAddress -ne $manifest.publicIp) {
            throw "Firewall rule '$($manifest.ruleName)' no longer matches this lease; refusing deletion."
        }
        $null = & $InvokeAz @('sql','server','firewall-rule','delete','--resource-group',$manifest.resourceGroup,'--server',$manifest.sqlServer,'--name',$manifest.ruleName,'--yes','--only-show-errors')
        if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds ([Math]::Min($attempt, 3)); continue }
    }

    $absent = Get-Phase10FirewallRuleState -ResourceGroup $manifest.resourceGroup -Server $manifest.sqlServer -RuleName $manifest.ruleName -InvokeAz $InvokeAz
    if ($null -ne $absent) { throw "Firewall rule '$($manifest.ruleName)' remains after bounded cleanup; recovery manifest retained." }
    $manifest.state = 'removed'
    $manifest.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
}
