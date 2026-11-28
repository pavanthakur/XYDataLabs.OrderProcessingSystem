#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../phase10-azure-dev-foundation-bootstrap.ps1'
$sub = '11111111-1111-4111-8111-111111111111'
$directory = '22222222-2222-4222-8222-222222222222'
$bootstrap = '33333333-3333-4333-8333-333333333333'
$runnerId = '44444444-4444-4444-8444-444444444444'
$devScope = "/subscriptions/$sub/resourceGroups/rg-orderprocessing-dev"
$adminRole = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
$group = @{ id = $devScope; location = 'centralindia'; tags = @{ env = 'dev'; app = 'orderprocessing' } }

function Assert-Case($ok, $message) { if (-not $ok) { throw $message } }
function gh {
    $global:LASTEXITCODE = 0
    Assert-Case (($args -join ' ') -eq 'api --hostname github.com repos/pavanthakur/XYDataLabs.OrderProcessingSystem/environments/dev/variables?per_page=100 --paginate --slurp') 'Unexpected GitHub target.'
    $variables = @(
        @{ name = 'ENTRA_DIRECTORY_ID'; value = $directory }
        @{ name = 'AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID'; value = $bootstrap }
    )
    if ($fixture.runnerEnabled) { $variables += @{ name = 'PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID'; value = $runnerId } }
    if ($fixture.incompleteVariables) { ConvertTo-Json -InputObject @(@{ total_count = 4; variables = $variables }) -Depth 5 -Compress; return }
    ConvertTo-Json -InputObject @(@{ total_count = $variables.Count; variables = $variables }) -Depth 5 -Compress
}
function Get-Arg($items, $flag) { $items[[array]::IndexOf($items, $flag) + 1] }
function az {
    $global:LASTEXITCODE = 0
    $operation = $args[0..1] -join ' '
    switch ($operation) {
        'account show' { @{ id = $fixture.account; tenantId = $fixture.directory; state = 'Enabled'; user = @{ type = 'user' } } | ConvertTo-Json -Compress }
        'rest --method' {
            $url = Get-Arg $args '--url'
            if ($url -like "*/servicePrincipals/$bootstrap`?*") {
                @{ id = $bootstrap; accountEnabled = $true; servicePrincipalType = 'Application' } | ConvertTo-Json -Compress
            } elseif ($url -like "*/users/$runnerId`?*") {
                @{ id = $runnerId; accountEnabled = $fixture.runnerValid; userType = 'Member' } | ConvertTo-Json -Compress
            } else { throw 'Unexpected Graph lookup.' }
        }
        'group exists' { ConvertTo-Json -InputObject $fixture.groupExists -Compress }
        'group show' { $group | ConvertTo-Json -Compress }
        'group create' {
            $fixture.writes += 'group'
            Assert-Case ((Get-Arg $args '--subscription') -eq $sub -and (Get-Arg $args '--name') -eq 'rg-orderprocessing-dev' -and
                (Get-Arg $args '--location') -eq 'centralindia' -and $args -contains 'env=dev' -and $args -contains 'app=orderprocessing') 'Group write scope drift.'
            $fixture.groupExists = $true
            $group | ConvertTo-Json -Compress
        }
        'role assignment' {
            Assert-Case ((Get-Arg $args '--scope') -eq $devScope) 'Role scope drift.'
            if ($args[2] -eq 'list') { ConvertTo-Json -InputObject $fixture.grants -Compress; break }
            if ($args[2] -ne 'create') { throw 'Unexpected RBAC operation.' }
            $fixture.writes += 'grant'
            if ($fixture.failGrant) { $global:LASTEXITCODE = 1; Write-Error 'PRIVATE_NATIVE_DETAIL' -ErrorAction Continue; break }
            Assert-Case ((Get-Arg $args '--role') -eq $adminRole -and (Get-Arg $args '--assignee-object-id') -eq $bootstrap -and
                (Get-Arg $args '--condition-version') -eq '2.0' -and (Get-Arg $args '--assignee-principal-type') -eq 'ServicePrincipal') 'Incorrect bootstrap grant.'
            $grant = @{ principalId = $bootstrap; scope = $devScope; principalType = 'ServicePrincipal'; conditionVersion = '2.0';
                roleDefinitionId = "/subscriptions/$sub/providers/Microsoft.Authorization/roleDefinitions/$adminRole"; condition = (Get-Arg $args '--condition') }
            if (-not $fixture.hideGrant) { $fixture.grants += $grant }
            $grant | ConvertTo-Json -Compress
        }
        default { throw 'Unexpected Azure call.' }
    }
}
function Read-Host { return $fixture.phrase }
function Reset-Fixture {
    $script:fixture = @{ groupExists = $false; grants = @(); writes = @(); account = $sub; directory = $directory;
        runnerEnabled = $false; runnerValid = $true; failGrant = $false; hideGrant = $false; phrase = 'APPLY DEV FOUNDATION' }
}
function Run-Case([string]$mode = 'Plan', [switch]$WhatIf) {
    $result = [Collections.Generic.List[string]]::new()
    $failed = $false
    try {
        & $scriptPath -Mode $mode -ExpectedSubscriptionId $sub -ExpectedDirectoryId $directory -Confirm:$false -WhatIf:$WhatIf 6>$null |
            ForEach-Object { $result.Add($_) }
    } catch {
        if ($_.Exception.Message -notlike '00b foundation bootstrap*') { throw }
        $failed = $true
    }
    $raw = $result -join "`n"
    Assert-Case ($raw -notmatch 'PRIVATE_NATIVE_DETAIL') 'Report leaked native error text.'
    $report = $raw | ConvertFrom-Json
    Assert-Case ($failed -eq ($report.status -ne 'PASS')) 'Exit/report statuses disagree.'
    return $report
}

Reset-Fixture
$r = Run-Case
Assert-Case ($r.status -eq 'PASS' -and $fixture.writes.Count -eq 0 -and $r.plan.Count -eq 2) 'Plan must not write.'
$r = Run-Case Apply
Assert-Case ($r.status -eq 'PASS' -and ($fixture.writes -join ',') -eq 'group,grant' -and $r.completed.Count -eq 2) 'Fresh Apply failed.'
$r = Run-Case Apply
Assert-Case ($r.status -eq 'PASS' -and $r.plan[0] -eq 'no-change' -and $fixture.writes.Count -eq 2) 'Repeat Apply was not a no-op.'
$fixture.runnerEnabled = $true
$r = Run-Case Apply
Assert-Case ($r.status -eq 'BLOCKED' -and $fixture.writes.Count -eq 2) 'Existing Storage-only condition was overwritten.'

Reset-Fixture
$fixture.groupExists = $true
$fixture.runnerEnabled = $true
$r = Run-Case Apply
Assert-Case ($r.status -eq 'PASS' -and $fixture.writes -eq 'grant' -and $fixture.grants[0].condition.Contains($runnerId)) 'Pinned-runner grant was not created on existing group.'
$fixture.grants += $fixture.grants[0].Clone()
Assert-Case ((Run-Case Apply).status -eq 'BLOCKED' -and $fixture.writes.Count -eq 1) 'Duplicate grant was not rejected.'
$fixture.grants = @($fixture.grants[0])
$competitor = $fixture.grants[0].Clone()
$competitor.principalId = $runnerId
$fixture.grants += $competitor
$r = Run-Case Apply
Assert-Case ($r.status -eq 'BLOCKED' -and $r.directBootstrapAdminCount -eq 2 -and $r.reason -like 'Another principal*' -and
    $fixture.writes.Count -eq 1) 'Competing principal was not diagnosed and rejected.'

foreach ($scenario in @('subscription', 'directory', 'runner', 'confirmation', 'whatif', 'incomplete-variables')) {
    Reset-Fixture
    switch ($scenario) {
        'subscription' { $fixture.account = $directory }
        'directory' { $fixture.directory = $sub }
        'runner' { $fixture.runnerEnabled = $true; $fixture.runnerValid = $false }
        'confirmation' { $fixture.phrase = '' }
        'incomplete-variables' { $fixture.incompleteVariables = $true }
    }
    $r = Run-Case Apply -WhatIf:($scenario -eq 'whatif')
    Assert-Case ($r.status -eq 'BLOCKED' -and $fixture.writes.Count -eq 0) "Unsafe $scenario was not rejected."
}

Reset-Fixture
$fixture.failGrant = $true
$r = Run-Case Apply
Assert-Case ($r.status -eq 'FAIL' -and $r.completed[0] -eq 'dev-resource-group-verified' -and $fixture.groupExists) 'Partial state was not preserved.'
$r = Run-Case
Assert-Case ($r.plan -eq 'create-constrained-bootstrap-assignment' -and $fixture.writes.Count -eq 2) 'Recovery plan must not recreate or delete the group.'
$fixture.failGrant = $false
$fixture.hideGrant = $true
$r = Run-Case Apply
Assert-Case ($r.status -eq 'FAIL' -and $r.stage -eq 'verify-assignment') 'Missing read-back must fail.'
Write-Host '00b mocked bootstrap scenarios passed.'
