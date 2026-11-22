#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('dev')][string]$Environment = 'dev',
    [Parameter(Mandatory)][string]$ExpectedSubscriptionId,
    [Parameter(Mandatory)][string]$TenantCode,
    [Parameter(Mandatory)][guid]$QuarantineId,
    [Parameter(Mandatory)][guid]$ReplayRequestId,
    [Parameter(Mandatory)][guid]$SourceMessageId,
    [Parameter(Mandatory)][string]$CorrelationId,
    [Parameter(Mandatory)][DateTimeOffset]$ApprovedUtc,
    [switch]$ConfirmFirewallLease,
    [ValidateRange(1,300)][int]$TimeoutSeconds = 120,
    [ValidateRange(1,30)][int]$PollIntervalSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmFirewallLease) {
    throw 'This read-only SQL verifier may create a temporary Azure SQL firewall lease. Re-run only after that dev mutation is explicitly approved, with -ConfirmFirewallLease.'
}
if ($TenantCode -notmatch '^[A-Za-z0-9_-]{1,64}$' -or $CorrelationId.Length -gt 128 -or [string]::IsNullOrWhiteSpace($CorrelationId)) {
    throw 'Tenant or correlation identifier is invalid.'
}
$requestedTenantCode = $TenantCode

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureLibrary = Join-Path $PSScriptRoot 'phase10-azure-payment-test-state.ps1'
. $fixtureLibrary -LibraryOnly -Environment dev -ExpectedSubscriptionId $ExpectedSubscriptionId
$script:LeaseOpenedForReplayVerification = $false
$script:FirewallLeaseRestored = $false
$script:FirewallCleanupFailureType = $null
$script:VerificationFailure = $null
$script:VerificationFailureStage = $null
$script:VerificationSnapshot = $null
$script:VerificationStage = 'preflight'

function Get-ReplayOperationsSnapshot {
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][int]$TenantId
    )

    $script:VerificationStage = 'query-quarantine-sql'
    $rows = @(Invoke-AzureFixtureSql -Database $Database -Query @'
SELECT
    q.Id AS QuarantineId,
    q.SourceMessageId,
    q.TenantId,
    q.CorrelationId,
    q.State AS QuarantineState,
    q.ReplayAttemptCount,
    q.ReplayedUtc,
    r.Id AS ReplayRequestId,
    r.QuarantineId AS RequestQuarantineId,
    r.ApprovedUtc,
    r.PublishedUtc,
    r.ProcessedUtc,
    r.LastError
FROM operations.DlqQuarantineRecords AS q
LEFT JOIN operations.DlqReplayRequests AS r ON r.QuarantineId = q.Id
WHERE q.Id = @quarantineId;
'@ -Parameters @{ quarantineId = $QuarantineId.ToString('D') })

    if ($rows.Count -eq 0) { $script:VerificationStage = 'quarantine-row-not-visible'; return $null }
    $script:VerificationStage = 'validate-quarantine-tenant'
    if ($rows.Count -ne 1) { throw 'Replay query returned a non-unique quarantine record.' }
    $row = $rows[0]
    if ([int]$row.TenantId -ne $TenantId) { throw 'Quarantine tenant does not match the active registry tenant.' }
    $script:VerificationStage = 'validate-quarantine-source'
    if ([string]$row.SourceMessageId -ne $SourceMessageId.ToString('D')) { throw 'Quarantine source message does not match the requested test envelope.' }
    $script:VerificationStage = 'validate-quarantine-correlation'
    if ([string]$row.CorrelationId -ne $CorrelationId) { throw 'Quarantine correlation ID does not match the requested test envelope.' }
    $script:VerificationStage = 'validate-quarantine-replay-request'
    if ($null -ne $row.ReplayRequestId -and [string]$row.ReplayRequestId -ne $ReplayRequestId.ToString('D')) { throw 'Quarantine is linked to a different replay request.' }
    $script:VerificationStage = 'validate-quarantine-approval-time'
    $persistedApprovedUtc = if ($null -eq $row.ApprovedUtc -or $row.ApprovedUtc -is [DBNull]) { $null } else { Convert-SqlUtcDateTime -Value $row.ApprovedUtc }
    if ($null -ne $persistedApprovedUtc -and [Math]::Abs($persistedApprovedUtc.Subtract($ApprovedUtc.UtcDateTime).TotalMilliseconds) -gt 1000) { throw 'Persisted approval time does not match the protected API response.' }
    return $row
}

function Get-ReplayBusinessEffects {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][int]$TenantId)

    $script:VerificationStage = 'query-replay-effects-sql'
    $rows = @(Invoke-AzureFixtureSql -Database $Database -Query @'
SELECT
    COALESCE((SELECT COUNT_BIG(*) FROM operations.ConsumerInboxMessages WHERE CorrelationId = @correlationId AND TenantId = @tenantId AND ConsumerName = N'Inventory'), 0) AS InventoryInboxCount,
    COALESCE((SELECT COUNT_BIG(*) FROM operations.ConsumerInboxMessages WHERE CorrelationId = @correlationId AND TenantId = @tenantId AND ConsumerName = N'Notifications'), 0) AS NotificationsInboxCount,
    COALESCE((SELECT COUNT_BIG(*) FROM inventory.InventoryReservations WHERE CorrelationId = @correlationId AND TenantId = @tenantId), 0) AS InventoryReservationCount,
    COALESCE((SELECT COUNT_BIG(*) FROM notifications.NotificationDeliveries WHERE CorrelationId = @correlationId AND TenantId = @tenantId), 0) AS NotificationDeliveryCount,
    (SELECT MAX(ProcessedUtc) FROM operations.ConsumerInboxMessages WHERE CorrelationId = @correlationId AND TenantId = @tenantId AND ConsumerName = N'Inventory') AS InventoryInboxProcessedUtc,
    (SELECT MAX(ProcessedUtc) FROM operations.ConsumerInboxMessages WHERE CorrelationId = @correlationId AND TenantId = @tenantId AND ConsumerName = N'Notifications') AS NotificationsInboxProcessedUtc,
    (SELECT MAX(ReservedUtc) FROM inventory.InventoryReservations WHERE CorrelationId = @correlationId AND TenantId = @tenantId) AS InventoryReservedUtc,
    (SELECT MAX(AcceptedUtc) FROM notifications.NotificationDeliveries WHERE CorrelationId = @correlationId AND TenantId = @tenantId) AS NotificationAcceptedUtc,
    COALESCE((SELECT COUNT_BIG(*) FROM operations.ConsumerInboxMessages WHERE CorrelationId = @correlationId AND TenantId <> @tenantId), 0)
      + COALESCE((SELECT COUNT_BIG(*) FROM inventory.InventoryReservations WHERE CorrelationId = @correlationId AND TenantId <> @tenantId), 0)
      + COALESCE((SELECT COUNT_BIG(*) FROM notifications.NotificationDeliveries WHERE CorrelationId = @correlationId AND TenantId <> @tenantId), 0) AS OtherTenantEffectCount;
'@ -Parameters @{ correlationId = $CorrelationId; tenantId = [string]$TenantId })
    if ($rows.Count -ne 1) { $script:VerificationStage = 'replay-effects-row-count'; throw 'Business-effect query did not return exactly one aggregate row.' }
    return $rows[0]
}

function Resolve-ReplayTenantDatabase {
    param([Parameter(Mandatory)][string]$Code)
    $target = Get-AzureFixtureTarget
    $registry = [string]$target.azureOperationsDatabaseName
    $rows = @(Invoke-AzureFixtureSql -Database $registry -Query @'
SELECT Id AS TenantId, Code AS TenantCode, Status AS TenantStatus, TenantTier
FROM dbo.Tenants WHERE Code = @code;
'@ -Parameters @{ code = $Code })
    if ($rows.Count -ne 1 -or [string]$rows[0].TenantStatus -ne 'Active') { throw 'Tenant did not resolve to exactly one active shared-registry row.' }
    $businessDatabase = switch ([string]$rows[0].TenantTier) {
        'SharedPool' { $registry }
        'Dedicated' { Get-AzureFixtureDedicatedDatabase -Code $Code }
        default { throw 'Tenant tier is not supported by the Phase 10 database topology.' }
    }
    $businessTenant = @(Invoke-AzureFixtureSql -Database $businessDatabase -Query @'
SELECT Id AS TenantId, Code AS TenantCode FROM dbo.Tenants WHERE Code = @code;
'@ -Parameters @{ code = $Code })
    if ($businessTenant.Count -ne 1 -or [int]$businessTenant[0].TenantId -ne [int]$rows[0].TenantId) {
        throw 'Business database tenant identity does not match the shared registry.'
    }
    return [pscustomobject]@{
        tenantId = [int]$rows[0].TenantId
        tenantCode = [string]$rows[0].TenantCode
        tier = [string]$rows[0].TenantTier
        operationsDatabase = $registry
        businessDatabase = $businessDatabase
    }
}

function Convert-ReplayTimestamp {
    param($Value)
    if ($null -eq $Value -or $Value -is [DBNull]) { return $null }
    return (Convert-SqlUtcDateTime -Value $Value).ToString('o')
}

function Convert-SqlUtcDateTime {
    param([Parameter(Mandatory)]$Value)
    $timestamp = [DateTime]$Value
    if ($timestamp.Kind -eq [DateTimeKind]::Unspecified) {
        return [DateTime]::SpecifyKind($timestamp, [DateTimeKind]::Utc)
    }
    return $timestamp.ToUniversalTime()
}

try {
    if ($Environment -ne 'dev') { throw 'Only Azure dev is supported.' }
    $script:VerificationStage = 'initialize-sql-and-topology'
    Initialize-AzureFixtureSql
    Initialize-AzureFixtureTopology
    $target = Get-AzureFixtureTarget
    $script:VerificationStage = 'open-firewall-lease'
    Open-AzureFixtureFirewall
    $script:LeaseOpenedForReplayVerification = $true

    $script:VerificationStage = 'resolve-tenant-database'
    $tenant = Resolve-ReplayTenantDatabase -Code $requestedTenantCode
    $tenantId = [int]$tenant.tenantId
    $operationsDatabase = [string]$target.azureOperationsDatabaseName
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastSnapshot = $null

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $script:VerificationStage = 'read-quarantine-and-replay-request'
        $operation = Get-ReplayOperationsSnapshot -Database $operationsDatabase -TenantId $tenantId
        if ($null -ne $operation) {
            if ([string]$operation.ReplayRequestId -and [string]$operation.ReplayRequestId -ne $ReplayRequestId.ToString('D')) {
                throw 'The quarantine is associated with another replay request; refusing to infer a matching replay.'
            }
            $script:VerificationStage = 'read-downstream-effects'
            $effects = Get-ReplayBusinessEffects -Database ([string]$tenant.businessDatabase) -TenantId $tenantId
            $lastSnapshot = [ordered]@{
                tenantCode = $requestedTenantCode
                correlationId = $CorrelationId
                quarantine = [ordered]@{
                    id = [string]$operation.QuarantineId
                    sourceMessageId = [string]$operation.SourceMessageId
                    state = [string]$operation.QuarantineState
                    replayAttemptCount = [int]$operation.ReplayAttemptCount
                    replayedUtc = Convert-ReplayTimestamp $operation.ReplayedUtc
                }
                replayRequest = [ordered]@{
                    id = if ($null -eq $operation.ReplayRequestId) { '' } else { [string]$operation.ReplayRequestId }
                    quarantineId = [string]$operation.RequestQuarantineId
                    approvedUtc = Convert-ReplayTimestamp $operation.ApprovedUtc
                    publishedUtc = Convert-ReplayTimestamp $operation.PublishedUtc
                    processedUtc = Convert-ReplayTimestamp $operation.ProcessedUtc
                    lastError = if ($null -eq $operation.LastError -or $operation.LastError -is [DBNull]) { $null } else { 'present' }
                }
                effects = [ordered]@{
                    inventoryInboxCount = [int64]$effects.InventoryInboxCount
                    notificationsInboxCount = [int64]$effects.NotificationsInboxCount
                    inventoryReservationCount = [int64]$effects.InventoryReservationCount
                    notificationDeliveryCount = [int64]$effects.NotificationDeliveryCount
                    otherTenantEffectCount = [int64]$effects.OtherTenantEffectCount
                    inventoryInboxProcessedUtc = Convert-ReplayTimestamp $effects.InventoryInboxProcessedUtc
                    notificationsInboxProcessedUtc = Convert-ReplayTimestamp $effects.NotificationsInboxProcessedUtc
                    inventoryReservedUtc = Convert-ReplayTimestamp $effects.InventoryReservedUtc
                    notificationAcceptedUtc = Convert-ReplayTimestamp $effects.NotificationAcceptedUtc
                }
            }
            $script:VerificationSnapshot = $lastSnapshot
            $processingRecorded = -not [string]::IsNullOrWhiteSpace([string]$lastSnapshot.replayRequest.processedUtc) `
                -and -not [string]::IsNullOrWhiteSpace([string]$lastSnapshot.quarantine.replayedUtc) `
                -and $lastSnapshot.effects.inventoryInboxCount -ge 1 `
                -and $lastSnapshot.effects.notificationsInboxCount -ge 1 `
                -and $lastSnapshot.effects.inventoryReservationCount -ge 1 `
                -and $lastSnapshot.effects.notificationDeliveryCount -ge 1
            if ($processingRecorded) { break }
        }
        $script:VerificationStage = 'wait-for-replay-effects'
        Start-Sleep -Seconds ([Math]::Min($PollIntervalSeconds, [Math]::Max(1, ($deadline - [DateTimeOffset]::UtcNow).TotalSeconds)))
    }

    if ($null -eq $lastSnapshot) { throw 'No matching Azure dev quarantine evidence was found.' }
}
catch {
    # Do not serialize provider/SQL/Azure exception text, which may include sensitive values.
    $failureType = $_.Exception.GetType().Name
    $script:VerificationFailure = $failureType
    $script:VerificationFailureStage = $script:VerificationStage
}
finally {
    $script:VerificationStage = 'restore-firewall-lease'
    if ($script:LeaseOpenedForReplayVerification) {
        try { Close-AzureFixtureFirewall; $script:FirewallLeaseRestored = $true }
        catch { $script:FirewallLeaseRestored = $false; $script:FirewallCleanupFailureType = $_.Exception.GetType().Name }
    }
}

$result = [ordered]@{
    schemaVersion = 'phase10-azure-dlq-replay-sql-evidence-v1'
    environment = 'dev'
    status = if ($null -ne $script:VerificationSnapshot -and $null -eq $script:VerificationFailure -and $script:FirewallLeaseRestored) { 'SNAPSHOT_READY_FOR_VALIDATION' } else { 'INCOMPLETE' }
    expected = [ordered]@{
        tenantCode = $requestedTenantCode
        quarantineId = $QuarantineId.ToString('D')
        replayRequestId = $ReplayRequestId.ToString('D')
        sourceMessageId = $SourceMessageId.ToString('D')
        correlationId = $CorrelationId
        approvedUtc = $ApprovedUtc.ToUniversalTime().ToString('o')
    }
    snapshot = $script:VerificationSnapshot
    failureType = $script:VerificationFailure
    failureStage = $script:VerificationFailureStage
    firewallLeaseRestored = $script:FirewallLeaseRestored
    firewallCleanupFailureType = $script:FirewallCleanupFailureType
    completedUtc = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json -Depth 12 -Compress
if ($result.status -ne 'SNAPSHOT_READY_FOR_VALIDATION') { exit 1 }
