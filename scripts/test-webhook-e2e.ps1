#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end webhook test — all tenants × all payment provider permutations.
.DESCRIPTION
    Tests the complete webhook pipeline:
      - Valid webhook per native (tenant, provider) pair     → 202, InboxMsg Processed, PA Succeeded
      - Cross-provider webhook (wrong provider for tenant)   → 202, InboxMsg Processed, no PA match (expected)
      - Invalid HMAC                                         → 401, no InboxMessage created
      - Duplicate event replay (dedup)                       → 202+202, both Processed (2nd=dedup hit)
      - Unsupported provider                                 → 400
      - Missing tenant header                                → 400

    Tenant/provider matrix (from Tenants table):
      TenantA  SharedPool  Razorpay
      TenantB  SharedPool  Razorpay
      TenantC  Dedicated   OpenPay

    Prerequisites:
      - Local HTTP profile running: http://localhost:5010
    - Webhooks:Razorpay:Secret matches LOCAL_RAZORPAY_WEBHOOK_SECRET, or the local test fallback
    - Webhooks:OpenPay:Secret matches LOCAL_OPENPAY_WEBHOOK_SECRET, or the local test fallback

.EXAMPLE
    .\scripts\test-webhook-e2e.ps1
    .\scripts\test-webhook-e2e.ps1 -ApiBaseUrl http://localhost:5010 -WorkerWaitSeconds 15
#>
param(
    [string]$ApiBaseUrl          = "http://localhost:5010",
    [string]$RazorpaySecret,
    [string]$OpenPaySecret,
    [string]$SharedDbServer      = "localhost",
    [string]$SharedDbName        = "",
    [string]$TenantCDbServer     = "localhost",
    [string]$TenantCDbName       = "",
    [int]   $WorkerWaitSeconds   = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($env:DOCKER_CONFIG)) {
    $env:DOCKER_CONFIG = Join-Path $env:TEMP 'orderprocessing-docker-config'
}
if (-not (Test-Path $env:DOCKER_CONFIG)) {
    New-Item -ItemType Directory -Path $env:DOCKER_CONFIG | Out-Null
}

$testRun = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$failed  = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
$envLocalPath = Join-Path $repoRoot 'Resources\Docker\.env.local'

function Get-SecretValueFromEnvLocal {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path $envLocalPath)) {
        return $null
    }

    $line = Get-Content $envLocalPath | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value.Trim()
}

if ([string]::IsNullOrWhiteSpace($RazorpaySecret)) {
    $RazorpaySecret = Get-SecretValueFromEnvLocal -Name 'LOCAL_RAZORPAY_WEBHOOK_SECRET'
}

if ([string]::IsNullOrWhiteSpace($RazorpaySecret)) {
    $RazorpaySecret = 'razorpay-test-secret'
}

if ([string]::IsNullOrWhiteSpace($OpenPaySecret)) {
    $OpenPaySecret = Get-SecretValueFromEnvLocal -Name 'LOCAL_OPENPAY_WEBHOOK_SECRET'
}

if ([string]::IsNullOrWhiteSpace($OpenPaySecret)) {
    $OpenPaySecret = 'openpay-test-secret'
}

$DockerSqlPassword = Get-SecretValueFromEnvLocal -Name 'LOCAL_SQL_PASSWORD'
$UseDockerSql = $ApiBaseUrl -match ':502(?:0|1)(?:/|$)|:503(?:0|1)(?:/|$)|:504(?:0|1)(?:/|$)'

function Resolve-Phase9DatabaseNames {
    param(
        [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
        [string]$SharedDbName,
        [string]$TenantCDbName
    )

    $resolvedSharedDbName = $SharedDbName
    $resolvedTenantCDbName = $TenantCDbName

    if ([string]::IsNullOrWhiteSpace($resolvedSharedDbName)) {
        if ($ApiBaseUrl -match ':502(?:0|1)(?:/|$)') {
            $resolvedSharedDbName = 'OrderProcessingSystem_Dev'
        }
        elseif ($ApiBaseUrl -match ':503(?:0|1)(?:/|$)') {
            $resolvedSharedDbName = 'OrderProcessingSystem_Stg'
        }
        elseif ($ApiBaseUrl -match ':504(?:0|1)(?:/|$)') {
            $resolvedSharedDbName = 'OrderProcessingSystem_Prod'
        }
        else {
            $resolvedSharedDbName = 'OrderProcessingSystem_Local'
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTenantCDbName)) {
        if ($ApiBaseUrl -match ':502(?:0|1)(?:/|$)') {
            $resolvedTenantCDbName = 'OrderProcessingSystem_TenantC_Dev'
        }
        elseif ($ApiBaseUrl -match ':503(?:0|1)(?:/|$)') {
            $resolvedTenantCDbName = 'OrderProcessingSystem_TenantC_Stg'
        }
        elseif ($ApiBaseUrl -match ':504(?:0|1)(?:/|$)') {
            $resolvedTenantCDbName = 'OrderProcessingSystem_TenantC_Prod'
        }
        else {
            $resolvedTenantCDbName = 'OrderProcessingSystem_TenantC'
        }
    }

    return @{
        SharedDbName = $resolvedSharedDbName
        TenantCDbName = $resolvedTenantCDbName
    }
}

$dbNames = Resolve-Phase9DatabaseNames -ApiBaseUrl $ApiBaseUrl -SharedDbName $SharedDbName -TenantCDbName $TenantCDbName
$SharedDbName = $dbNames.SharedDbName
$TenantCDbName = $dbNames.TenantCDbName

function Assert-Phase9RuntimeDbContract {
    param(
        [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
        [Parameter(Mandatory = $true)][string]$SharedDbName,
        [Parameter(Mandatory = $true)][string]$TenantCDbName,
        [Parameter(Mandatory = $true)][bool]$UseDockerSql
    )

    $isDockerProfile = $ApiBaseUrl -match ':502(?:0|1)(?:/|$)|:503(?:0|1)(?:/|$)|:504(?:0|1)(?:/|$)'
    if ($isDockerProfile -and -not $UseDockerSql) {
        throw "Docker profile detected from ApiBaseUrl=$ApiBaseUrl, but Docker SQL mode was not enabled."
    }

    if ($isDockerProfile) {
        $expectedShared = switch ($ApiBaseUrl) {
            { $_ -match ':502(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_Dev' ; break }
            { $_ -match ':503(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_Stg' ; break }
            { $_ -match ':504(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_Prod' ; break }
        }

        $expectedTenantC = switch ($ApiBaseUrl) {
            { $_ -match ':502(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_TenantC_Dev' ; break }
            { $_ -match ':503(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_TenantC_Stg' ; break }
            { $_ -match ':504(?:0|1)(?:/|$)' } { 'OrderProcessingSystem_TenantC_Prod' ; break }
        }

        if ($SharedDbName -ne $expectedShared -or $TenantCDbName -ne $expectedTenantC) {
            throw "Docker profile/db-name mismatch. ApiBaseUrl=$ApiBaseUrl SharedDbName=$SharedDbName TenantCDbName=$TenantCDbName ExpectedShared=$expectedShared ExpectedTenantC=$expectedTenantC"
        }
    }
}

Assert-Phase9RuntimeDbContract -ApiBaseUrl $ApiBaseUrl -SharedDbName $SharedDbName -TenantCDbName $TenantCDbName -UseDockerSql $UseDockerSql

# ── HMAC helpers ─────────────────────────────────────────────────────────────
function Get-RazorpaySignature([string]$Payload, [string]$Secret) {
    # HMAC-SHA256 of payload, uppercase hex — matches WebhookSignatureValidator.ValidateRazorpay
    $key  = [Text.Encoding]::UTF8.GetBytes($Secret)
    $data = [Text.Encoding]::UTF8.GetBytes($Payload)
    $hmac = [Security.Cryptography.HMACSHA256]::new($key)
    $hash = $hmac.ComputeHash($data)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToUpperInvariant()
}

function Get-OpenPaySignature([string]$Payload, [string]$Secret) {
    # HMAC-SHA256 of payload, base64 — matches WebhookSignatureValidator.ValidateOpenPay
    $key  = [Text.Encoding]::UTF8.GetBytes($Secret)
    $data = [Text.Encoding]::UTF8.GetBytes($Payload)
    $hmac = [Security.Cryptography.HMACSHA256]::new($key)
    $hash = $hmac.ComputeHash($data)
    return [Convert]::ToBase64String($hash)
}

function ConvertTo-RawJsonPayload {
    param([Parameter(Mandatory = $true)]$InputObject)

    return [System.Text.Json.JsonSerializer]::Serialize(
        $InputObject,
        [System.Text.Json.JsonSerializerOptions]::new([System.Text.Json.JsonSerializerDefaults]::Web))
}

function New-WebhookHttpClient {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    return [System.Net.Http.HttpClient]::new($handler, $true)
}

function Get-ShortSha256([string]$Value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 12)
}

# ── DB helpers ───────────────────────────────────────────────────────────────
function Invoke-Sql([string]$Server, [string]$Database, [string]$Query) {
    if ($UseDockerSql) {
        if ([string]::IsNullOrWhiteSpace($DockerSqlPassword)) {
            throw "Docker SQL mode is active for $ApiBaseUrl, but LOCAL_SQL_PASSWORD was not found in Resources\Docker\.env.local."
        }

        $out = docker exec orderprocessing-sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -S localhost `
            -U sa `
            -P $DockerSqlPassword `
            -C `
            -d $Database `
            -Q $Query `
            -h -1 -W 2>&1
    } else {
        $out = sqlcmd -S $Server -d $Database -E -C -Q $Query -h -1 -W 2>&1
    }
    return @(
        $out |
            Where-Object {
                $_ -and
                ($_ -notmatch '^\s*-+\s*$') -and
                ($_ -notmatch '^\s*\(\d+ rows affected\)') -and
                ($_.ToString().Trim() -ne '')
            } |
            ForEach-Object { $_.ToString().Trim() }
    )
}

function Get-InboxStatus([int]$Id, [string]$Server, [string]$Database) {
    $rows = @(Invoke-Sql $Server $Database "SELECT TOP 1 Status FROM InboxMessages WHERE Id=$Id")
    if (-not $rows -or $rows.Count -eq 0) {
        return ''
    }

    return [string]$rows[0]
}

function Get-AttemptStatus([string]$ProviderRef, [int]$TenantId, [string]$Server, [string]$Database) {
    $rows = @(Invoke-Sql $Server $Database `
        "SELECT TOP 1 Status FROM PaymentAttempts WHERE ProviderReferenceId='$ProviderRef' AND TenantId=$TenantId")
    if (-not $rows -or $rows.Count -eq 0) {
        return ''
    }

    return [string]$rows[0]
}

function Get-SqlScalarInt([string]$Server, [string]$Database, [string]$Query) {
    $rows = @(Invoke-Sql $Server $Database $Query)
    if (-not $rows -or $rows.Count -eq 0) {
        return 0
    }

    $value = [string]$rows[0]
    if ([string]::IsNullOrWhiteSpace($value)) {
        return 0
    }

    return [int]$value
}

# ── HTTP helper ───────────────────────────────────────────────────────────────
function Send-Webhook {
    param(
        [string]$ProviderName,
        [string]$TenantCode,
        [string]$Payload,
        [string]$Signature,
        [string]$SignatureHeader,
        [string]$EventId,
        [string]$EventType = "payment.captured"
    )
    $client = New-WebhookHttpClient
    $payloadContent = [System.Net.Http.StringContent]::new($Payload, [System.Text.Encoding]::UTF8, 'application/json')
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$ApiBaseUrl/api/v1/webhook/$ProviderName")
    $request.Content = $payloadContent
    $request.Headers.TryAddWithoutValidation("X-Tenant-Code", $TenantCode) | Out-Null
    $request.Headers.TryAddWithoutValidation($SignatureHeader, $Signature) | Out-Null
    $request.Headers.TryAddWithoutValidation("X-Provider-Event-Id", $EventId) | Out-Null
    $request.Headers.TryAddWithoutValidation("X-Provider-Event-Type", $EventType) | Out-Null
    if ($SignatureHeader -ne 'X-Webhook-Signature') {
        $request.Headers.TryAddWithoutValidation("X-Webhook-Signature", $Signature) | Out-Null
    }
    $secretHash = if ($ProviderName -eq 'OpenPay') { Get-ShortSha256 $OpenPaySecret } else { Get-ShortSha256 $RazorpaySecret }
    Write-Host ("    -> {0} payload hash={1} len={2} secret hash={3}" -f $ProviderName, (Get-ShortSha256 $Payload), $Payload.Length, $secretHash) -ForegroundColor DarkGray
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            try { $parsed = $body | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $body }
        }
        return @{
            Status = [int]$response.StatusCode
            Body   = $parsed
        }
    } catch {
        $code = [int]($_.Exception.Response?.StatusCode ?? 0)
        $body = $_.ErrorDetails?.Message ?? $_.Exception.Message
        return @{ Status = $code; Body = $body }
    } finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}

# ── Result tracking ───────────────────────────────────────────────────────────
function Add-Result([string]$Tag, [string]$Description, [bool]$Pass, [string]$Detail) {
    if (-not $Pass) { $script:failed++ }
    $script:results.Add([PSCustomObject]@{
        Tag         = $Tag
        Description = $Description
        Status      = if ($Pass) { 'PASS' } else { 'FAIL' }
        Detail      = $Detail
    })
    $icon  = if ($Pass) { '✓' } else { '✗' }
    $color = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1,-45} {2}" -f $icon, $Description, $Detail) -ForegroundColor $color
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 78) -ForegroundColor Cyan
Write-Host ("  WEBHOOK E2E TEST — LOCAL HTTP   $ApiBaseUrl   run=$testRun") -ForegroundColor Cyan
Write-Host ('═' * 78) -ForegroundColor Cyan

# ── 1. Read tenants ───────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[SETUP] Reading tenants from DB...' -ForegroundColor Yellow

$tenantRows = Invoke-Sql $SharedDbServer $SharedDbName `
    "SELECT Id, Code, ISNULL(PaymentProviderCode,'(none)') FROM Tenants WHERE Status='Active' ORDER BY Id"

$tenants = @{}
foreach ($row in $tenantRows) {
    $cols = @(($row -split '\s+') | Where-Object { $_.Trim() -ne '' })
    if ($cols.Count -ge 3) {
        $tid   = [int]$cols[0].Trim()
        $code  = $cols[1].Trim()
        $prov  = $cols[2].Trim()
        $tenants[$code] = @{ Id = $tid; Provider = $prov }
        Write-Host ("    $code  Id=$tid  Provider=$prov") -ForegroundColor DarkGray
    }
}

if ($tenants.Count -eq 0) {
    Write-Host 'ERROR: No active tenants found in DB. Is the DB seeded?' -ForegroundColor Red
    exit 1
}

# Resolve per-tenant DB for InboxMessage verification
function Get-DbForTenant([string]$TenantCode) {
    # TenantC is dedicated; TenantA/B are shared pool
    if ($TenantCode -eq 'TenantC') {
        return @{ Server = $TenantCDbServer; Database = $TenantCDbName }
    }
    return @{ Server = $SharedDbServer; Database = $SharedDbName }
}

# ── 2. Prepare test ProviderReferenceIds ──────────────────────────────────────
Write-Host ''
Write-Host '[SETUP] Preparing test PaymentAttempts with known ProviderReferenceIds...' -ForegroundColor Yellow

$testRefs = @{
    TenantA       = "rzp_pay_e2e_${testRun}_A"
    TenantB       = "rzp_pay_e2e_${testRun}_B"
    TenantC       = "op_charge_e2e_${testRun}_C"
    TenantAFailed = "rzp_pay_e2e_${testRun}_A_fail"
}

# TenantA and TenantB — update one existing UnknownNeedsReconciliation attempt
# Also seed a second TenantA attempt for the payment.failed S13 scenario
foreach ($code in @('TenantA', 'TenantB')) {
    if (-not $tenants.ContainsKey($code)) { continue }
    $tid = $tenants[$code].Id
    $ref = $testRefs[$code]
    $provider = $tenants[$code].Provider
    Invoke-Sql $SharedDbServer $SharedDbName @"
UPDATE TOP(1) [PaymentAttempts]
   SET [ProviderReferenceId] = '$ref'
 WHERE [TenantId] = $tid
   AND [Status] = 'UnknownNeedsReconciliation'
   AND ([ProviderReferenceId] IS NULL OR [ProviderReferenceId] = '')
"@ | Out-Null
    $check = Invoke-Sql $SharedDbServer $SharedDbName `
        "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
    if ($check) {
        Write-Host "    $code : PaymentAttempt updated → ProviderReferenceId='$ref'" -ForegroundColor DarkGray
    } else {
        # No UnknownNeedsReconciliation attempt available — insert a fresh test row
        $oid = "TEST-WH-E2E-$testRun-$code"
        Invoke-Sql $SharedDbServer $SharedDbName @"
INSERT INTO [PaymentAttempts]
  ([CustomerOrderId],[AttemptOrderId],[PaymentTraceId],[AttemptNumber],
   [Status],[PaymentProviderName],[ProviderReferenceId],[TenantId],[CreatedDate])
VALUES
  ('$oid','AT-E2E-$testRun-$code','trace-e2e-$testRun-$code',1,
   'UnknownNeedsReconciliation','$provider','$ref',$tid,GETUTCDATE())
"@ | Out-Null
        $check2 = Invoke-Sql $SharedDbServer $SharedDbName `
            "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
        if ($check2) {
            Write-Host "    $code : PaymentAttempt inserted (fresh) → ProviderReferenceId='$ref'" -ForegroundColor DarkGray
        } else {
            Write-Host "    $code : WARNING — could not insert test PaymentAttempt" -ForegroundColor DarkYellow
        }
    }
}

# TenantA failed scenario — seed a second attempt for S13
if ($tenants.ContainsKey('TenantA')) {
    $tid = $tenants['TenantA'].Id
    $ref = $testRefs['TenantAFailed']
    Invoke-Sql $SharedDbServer $SharedDbName @"
UPDATE TOP(1) [PaymentAttempts]
   SET [ProviderReferenceId] = '$ref'
 WHERE [TenantId] = $tid
   AND [Status] = 'UnknownNeedsReconciliation'
   AND ([ProviderReferenceId] IS NULL OR [ProviderReferenceId] = '')
"@ | Out-Null
    $check = Invoke-Sql $SharedDbServer $SharedDbName `
        "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
    if ($check) {
        Write-Host "    TenantA (failed) : PaymentAttempt updated for S13 → ProviderReferenceId='$ref'" -ForegroundColor DarkGray
    } else {
        # No UnknownNeedsReconciliation attempt available — insert a fresh test row for S13
        $oid = "TEST-WH-E2E-FAIL-$testRun"
        Invoke-Sql $SharedDbServer $SharedDbName @"
INSERT INTO [PaymentAttempts]
  ([CustomerOrderId],[AttemptOrderId],[PaymentTraceId],[AttemptNumber],
   [Status],[PaymentProviderName],[ProviderReferenceId],[TenantId],[CreatedDate])
VALUES
  ('$oid','AT-E2E-FAIL-$testRun','trace-e2e-fail-$testRun',1,
   'UnknownNeedsReconciliation','Razorpay','$ref',$tid,GETUTCDATE())
"@ | Out-Null
        $check2 = Invoke-Sql $SharedDbServer $SharedDbName `
            "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
        if ($check2) {
            Write-Host "    TenantA (failed) : PaymentAttempt inserted (fresh) for S13 → ProviderReferenceId='$ref'" -ForegroundColor DarkGray
        } else {
            Write-Host '    TenantA (failed) : WARNING — could not insert test PaymentAttempt for S13' -ForegroundColor DarkYellow
        }
    }
}

# TenantC — insert a test attempt into dedicated DB
if ($tenants.ContainsKey('TenantC')) {
    $tid = $tenants['TenantC'].Id
    $ref = $testRefs['TenantC']
    $oid = "TEST-WH-E2E-$testRun"

    $existing = Invoke-Sql $TenantCDbServer $TenantCDbName `
        "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
    if (-not $existing) {
        Invoke-Sql $TenantCDbServer $TenantCDbName @"
INSERT INTO [PaymentAttempts]
  ([CustomerOrderId],[AttemptOrderId],[PaymentTraceId],[AttemptNumber],
   [Status],[PaymentProviderName],[ProviderReferenceId],[TenantId],[CreatedDate])
VALUES
  ('TEST-ORDER-E2E-$testRun','$oid','test-trace-e2e-$testRun',1,
   'UnknownNeedsReconciliation','OpenPay','$ref',$tid,GETUTCDATE())
"@ | Out-Null
    }
    $check = Invoke-Sql $TenantCDbServer $TenantCDbName `
        "SELECT TOP 1 Id FROM PaymentAttempts WHERE TenantId=$tid AND ProviderReferenceId='$ref'"
    if ($check) {
        Write-Host "    TenantC : PaymentAttempt ready in dedicated DB → ProviderReferenceId='$ref'" -ForegroundColor DarkGray
    } else {
        Write-Host '    TenantC : WARNING — could not create test PaymentAttempt in dedicated DB' -ForegroundColor DarkYellow
    }
}

# ── 3. Send webhooks ──────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[TESTS] Sending webhooks...' -ForegroundColor Yellow
Write-Host ('─' * 78) -ForegroundColor DarkGray

$inboxIds = @{}  # scenario tag → InboxMessageId

# Helper: store InboxMessageId from response
function Store-InboxId([string]$Tag, $Response) {
    try {
        $id = [int]$Response.Body.inboxMessageId
        if ($id -gt 0) { $script:inboxIds[$Tag] = $id }
    } catch { }
}

# ── S1: TenantA / Razorpay / valid HMAC ──────────────────────────────────────
$evtS1   = "evt-${testRun}-A-rz-1"
$payS1   = ConvertTo-RawJsonPayload @{ payment_id = $testRefs.TenantA; event = 'payment.captured' }
$sigS1   = Get-RazorpaySignature $payS1 $RazorpaySecret
$rS1     = Send-Webhook 'Razorpay' 'TenantA' $payS1 $sigS1 'X-Razorpay-Signature' $evtS1
Store-InboxId 'S1' $rS1
Add-Result 'S1' 'TenantA/Razorpay valid → 202' ($rS1.Status -eq 202) "HTTP=$($rS1.Status) InboxId=$($inboxIds['S1'])"

# ── S2: TenantB / Razorpay / valid HMAC ──────────────────────────────────────
$evtS2   = "evt-${testRun}-B-rz-1"
$payS2   = ConvertTo-RawJsonPayload @{ payment_id = $testRefs.TenantB; event = 'payment.captured' }
$sigS2   = Get-RazorpaySignature $payS2 $RazorpaySecret
$rS2     = Send-Webhook 'Razorpay' 'TenantB' $payS2 $sigS2 'X-Razorpay-Signature' $evtS2
Store-InboxId 'S2' $rS2
Add-Result 'S2' 'TenantB/Razorpay valid → 202' ($rS2.Status -eq 202) "HTTP=$($rS2.Status) InboxId=$($inboxIds['S2'])"

# ── S3: TenantC / OpenPay / valid HMAC ───────────────────────────────────────
$evtS3   = "evt-${testRun}-C-op-1"
$payS3   = ConvertTo-RawJsonPayload @{ id = $testRefs.TenantC; event = 'payment.captured' }
$sigS3   = Get-OpenPaySignature $payS3 $OpenPaySecret
$rS3     = Send-Webhook 'OpenPay' 'TenantC' $payS3 $sigS3 'X-OpenPay-Signature' $evtS3
Store-InboxId 'S3' $rS3
Add-Result 'S3' 'TenantC/OpenPay valid → 202' ($rS3.Status -eq 202) "HTTP=$($rS3.Status) InboxId=$($inboxIds['S3'])"

# ── S4: TenantA / Razorpay / INVALID HMAC → 401 ──────────────────────────────
$evtS4   = "evt-${testRun}-A-rz-bad"
$payS4   = ConvertTo-RawJsonPayload @{ payment_id = 'rzp_bad'; event = 'payment.captured' }
$sigBad  = '0000000000000000000000000000000000000000000000000000000000000000'
$rS4     = Send-Webhook 'Razorpay' 'TenantA' $payS4 $sigBad 'X-Razorpay-Signature' $evtS4
Add-Result 'S4' 'TenantA/Razorpay invalid HMAC → 401' ($rS4.Status -eq 401) "HTTP=$($rS4.Status)"

# ── S5: TenantB / Razorpay / INVALID HMAC → 401 ──────────────────────────────
$evtS5   = "evt-${testRun}-B-rz-bad"
$rS5     = Send-Webhook 'Razorpay' 'TenantB' $payS4 $sigBad 'X-Razorpay-Signature' $evtS5
Add-Result 'S5' 'TenantB/Razorpay invalid HMAC → 401' ($rS5.Status -eq 401) "HTTP=$($rS5.Status)"

# ── S6: TenantC / OpenPay / INVALID HMAC → 401 ───────────────────────────────
$evtS6   = "evt-${testRun}-C-op-bad"
$rS6     = Send-Webhook 'OpenPay' 'TenantC' $payS4 $sigBad 'X-OpenPay-Signature' $evtS6
Add-Result 'S6' 'TenantC/OpenPay invalid HMAC → 401' ($rS6.Status -eq 401) "HTTP=$($rS6.Status)"

# ── S7: TenantA / OpenPay valid HMAC (cross-provider — TenantA uses Razorpay)
#    Webhook accepted; InboxMsg processed; PaymentAttempt NOT found (expected warning)
$evtS7   = "evt-${testRun}-A-op-cross"
$payS7   = ConvertTo-RawJsonPayload @{ id = 'op_cross_nomatch_A'; event = 'payment.captured' }
$sigS7   = Get-OpenPaySignature $payS7 $OpenPaySecret
$rS7     = Send-Webhook 'OpenPay' 'TenantA' $payS7 $sigS7 'X-OpenPay-Signature' $evtS7
Store-InboxId 'S7' $rS7
Add-Result 'S7' 'TenantA/OpenPay cross-provider → 202 (PA miss OK)' ($rS7.Status -eq 202) "HTTP=$($rS7.Status) InboxId=$($inboxIds['S7'])"

# ── S8: TenantC / Razorpay valid HMAC (cross-provider — TenantC uses OpenPay)
$evtS8   = "evt-${testRun}-C-rz-cross"
$payS8   = ConvertTo-RawJsonPayload @{ payment_id = 'rzp_cross_nomatch_C'; event = 'payment.captured' }
$sigS8   = Get-RazorpaySignature $payS8 $RazorpaySecret
$rS8     = Send-Webhook 'Razorpay' 'TenantC' $payS8 $sigS8 'X-Razorpay-Signature' $evtS8
Store-InboxId 'S8' $rS8
Add-Result 'S8' 'TenantC/Razorpay cross-provider → 202 (PA miss OK)' ($rS8.Status -eq 202) "HTTP=$($rS8.Status) InboxId=$($inboxIds['S8'])"

# ── S9a/S9b: DEDUP — same (TenantA, Razorpay) event posted twice ─────────────
$evtS9   = "evt-${testRun}-A-rz-dedup"
$payS9   = ConvertTo-RawJsonPayload @{ payment_id = "rzp_dedup_test_$testRun"; event = 'payment.captured' }
$sigS9   = Get-RazorpaySignature $payS9 $RazorpaySecret
$rS9a    = Send-Webhook 'Razorpay' 'TenantA' $payS9 $sigS9 'X-Razorpay-Signature' $evtS9
$rS9b    = Send-Webhook 'Razorpay' 'TenantA' $payS9 $sigS9 'X-Razorpay-Signature' $evtS9
Store-InboxId 'S9a' $rS9a
Store-InboxId 'S9b' $rS9b
Add-Result 'S9' 'TenantA/Razorpay DEDUP 1st POST → 202' ($rS9a.Status -eq 202) "HTTP=$($rS9a.Status) InboxId=$($inboxIds['S9a'])"
Add-Result 'S10' 'TenantA/Razorpay DEDUP 2nd POST → 202' ($rS9b.Status -eq 202) "HTTP=$($rS9b.Status) InboxId=$($inboxIds['S9b'])"

# ── S13: TenantA / Razorpay payment.failed — expect 202 + PA transitions to Failed ─
$evtS13  = "evt-${testRun}-A-rz-failed"
$payS13  = ConvertTo-RawJsonPayload @{ payment_id = $testRefs['TenantAFailed']; event = 'payment.failed'; description = 'Insufficient funds' }
$sigS13  = Get-RazorpaySignature $payS13 $RazorpaySecret
$rS13    = Send-Webhook 'Razorpay' 'TenantA' $payS13 $sigS13 'X-Razorpay-Signature' $evtS13 -EventType 'payment.failed'
Store-InboxId 'S13' $rS13
Add-Result 'S13' 'TenantA/Razorpay payment.failed → 202' ($rS13.Status -eq 202) "HTTP=$($rS13.Status) InboxId=$($inboxIds['S13'])"

# ── S11: Unsupported provider → 400 ──────────────────────────────────────────
$rS11 = Send-Webhook 'Stripe' 'TenantA' (ConvertTo-RawJsonPayload @{ event = 'charge.success' }) 'sig' 'X-Stripe-Signature' "evt-${testRun}-stripe"
Add-Result 'S11' "Unsupported provider 'Stripe' → 400" ($rS11.Status -eq 400) "HTTP=$($rS11.Status)"

# ── S12: Missing X-Tenant-Code header → 400 ──────────────────────────────────
try {
    $respS12 = Invoke-RestMethod -Uri "$ApiBaseUrl/api/v1/webhook/Razorpay" -Method POST `
        -Headers @{ 'X-Razorpay-Signature' = 'sig'; 'X-Webhook-Signature' = 'sig'; 'X-Provider-Event-Id' = "evt-${testRun}-notenant" } `
        -Body '{}' -ContentType 'application/json' `
        -StatusCodeVariable scS12 -ErrorAction SilentlyContinue
    Add-Result 'S12' 'Missing X-Tenant-Code → 400' ([int]$scS12 -eq 400) "HTTP=$scS12"
} catch {
    $c12 = [int]($_.Exception.Response?.StatusCode ?? 0)
    Add-Result 'S12' 'Missing X-Tenant-Code → 400' ($c12 -eq 400) "HTTP=$c12"
}

# ── Wait for InboxProcessorWorker ─────────────────────────────────────────────
Write-Host ''
Write-Host "[WAIT] Allowing InboxProcessorWorker $WorkerWaitSeconds seconds to process messages..." -ForegroundColor Yellow
Start-Sleep -Seconds $WorkerWaitSeconds

# ── 4. Verify DB state ────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[VERIFY] Checking DB results...' -ForegroundColor Yellow
Write-Host ('─' * 78) -ForegroundColor DarkGray

# V1: TenantA/Razorpay — InboxMsg=Processed + PA=Succeeded
$db1 = Get-DbForTenant 'TenantA'
$ist1 = if ($inboxIds['S1']) { Get-InboxStatus $inboxIds['S1'] $db1.Server $db1.Database } else { 'no-id' }
$ast1 = Get-AttemptStatus $testRefs.TenantA $tenants['TenantA'].Id $db1.Server $db1.Database
Add-Result 'V1' 'TenantA/Razorpay: InboxMsg=Processed + PA=Succeeded' `
    ($ist1 -eq 'Processed' -and $ast1 -eq 'Succeeded') `
    "InboxMsg[$($inboxIds['S1'])].Status=$ist1 | PA.Status=$ast1"

# V2: TenantB/Razorpay — InboxMsg=Processed + PA=Succeeded
$db2 = Get-DbForTenant 'TenantB'
$ist2 = if ($inboxIds['S2']) { Get-InboxStatus $inboxIds['S2'] $db2.Server $db2.Database } else { 'no-id' }
$ast2 = Get-AttemptStatus $testRefs.TenantB $tenants['TenantB'].Id $db2.Server $db2.Database
Add-Result 'V2' 'TenantB/Razorpay: InboxMsg=Processed + PA=Succeeded' `
    ($ist2 -eq 'Processed' -and $ast2 -eq 'Succeeded') `
    "InboxMsg[$($inboxIds['S2'])].Status=$ist2 | PA.Status=$ast2"

# V3: TenantC/OpenPay — InboxMsg=Processed + PA=Succeeded
$db3 = Get-DbForTenant 'TenantC'
$ist3 = if ($inboxIds['S3']) { Get-InboxStatus $inboxIds['S3'] $db3.Server $db3.Database } else { 'no-id' }
$ast3 = if ($tenants.ContainsKey('TenantC')) {
    Get-AttemptStatus $testRefs.TenantC $tenants['TenantC'].Id $db3.Server $db3.Database
} else { 'tenant-missing' }
Add-Result 'V3' 'TenantC/OpenPay: InboxMsg=Processed + PA=Succeeded' `
    ($ist3 -eq 'Processed' -and $ast3 -eq 'Succeeded') `
    "InboxMsg[$($inboxIds['S3'])].Status=$ist3 | PA.Status=$ast3"

# V4-V6: Invalid HMAC events — no InboxMessage should exist
foreach ($entry in @(
    @{ Tag='V4'; EventId=$evtS4; DbServer=$SharedDbServer; DbName=$SharedDbName; Label='TenantA/Razorpay bad HMAC' }
    @{ Tag='V5'; EventId=$evtS5; DbServer=$SharedDbServer; DbName=$SharedDbName; Label='TenantB/Razorpay bad HMAC' }
    @{ Tag='V6'; EventId=$evtS6; DbServer=$TenantCDbServer; DbName=$TenantCDbName; Label='TenantC/OpenPay bad HMAC' }
)) {
    $count = Get-SqlScalarInt $entry.DbServer $entry.DbName `
        "SELECT COUNT(*) FROM InboxMessages WHERE ProviderEventId='$($entry.EventId)'"
    Add-Result $entry.Tag "$($entry.Label): no InboxMsg created" ($count -eq 0) "InboxMessages with that EventId: $count"
}

# V7: Cross-provider TenantA/OpenPay — inbox processed, no PA transition
$ist7 = if ($inboxIds['S7']) { Get-InboxStatus $inboxIds['S7'] $SharedDbServer $SharedDbName } else { 'no-id' }
Add-Result 'V7' 'TenantA/OpenPay cross: InboxMsg=Processed (PA miss OK)' ($ist7 -eq 'Processed') "InboxMsg[$($inboxIds['S7'])].Status=$ist7"

# V8: Cross-provider TenantC/Razorpay — inbox processed, no PA transition
$ist8 = if ($inboxIds['S8']) { Get-InboxStatus $inboxIds['S8'] $TenantCDbServer $TenantCDbName } else { 'no-id' }
Add-Result 'V8' 'TenantC/Razorpay cross: InboxMsg=Processed (PA miss OK)' ($ist8 -eq 'Processed') "InboxMsg[$($inboxIds['S8'])].Status=$ist8"

# V9: Dedup 1st — InboxMessage must be Processed
$ist9a = if ($inboxIds['S9a']) { Get-InboxStatus $inboxIds['S9a'] $SharedDbServer $SharedDbName } else { 'no-id' }
Add-Result 'V9'  'Dedup 1st: InboxMsg=Processed' ($ist9a -eq 'Processed') "InboxMsg[$($inboxIds['S9a'])].Status=$ist9a"
# V10: DB-level dedup — 2nd POST must NOT insert a new row; exactly 1 InboxMessage for this ProviderEventId
$dedupCount = Get-SqlScalarInt $SharedDbServer $SharedDbName "SELECT COUNT(*) FROM InboxMessages WHERE ProviderEventId='$evtS9'"
$noS9bId    = -not $inboxIds['S9b']
Add-Result 'V10' 'Dedup 2nd: DB-level dedup (no new row, count=1)' ($dedupCount -eq 1 -and $noS9bId) "InboxCount=$dedupCount | S9b-NoId=$noS9bId"

# V11: payment.failed — InboxMsg=Processed + PA=Failed
$ist13 = if ($inboxIds['S13']) { Get-InboxStatus $inboxIds['S13'] $SharedDbServer $SharedDbName } else { 'no-id' }
$ast13 = Get-AttemptStatus $testRefs['TenantAFailed'] $tenants['TenantA'].Id $SharedDbServer $SharedDbName
Add-Result 'V11' 'TenantA/Razorpay payment.failed: InboxMsg=Processed + PA=Failed' `
    ($ist13 -eq 'Processed' -and $ast13 -eq 'Failed') `
    "InboxMsg[$($inboxIds['S13'])].Status=$ist13 | PA.Status=$ast13"

# V12: Outbox bridge — payment.captured must have written an OutboxMessage for TenantA (S1)
# EventType is the integration event class name: 'PaymentAttemptSucceededV1'
$outboxCount = Get-SqlScalarInt $SharedDbServer $SharedDbName `
    "SELECT COUNT(*) FROM OutboxMessages WHERE TenantId=$($tenants['TenantA'].Id) AND EventType LIKE '%PaymentAttemptSucceeded%'"
Add-Result 'V12' 'Outbox bridge: PaymentAttemptSucceededV1 row in OutboxMessages' ($outboxCount -ge 1) "OutboxRows=$outboxCount"

# ── SUMMARY ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 78) -ForegroundColor Cyan

$total  = $results.Count
$passed = $total - $script:failed
$color  = if ($script:failed -eq 0) { 'Green' } else { 'Red' }
Write-Host ("  RESULTS: $passed / $total passed  |  $($script:failed) failed  |  run=$testRun") -ForegroundColor $color
Write-Host ('═' * 78) -ForegroundColor Cyan
Write-Host ''

# Detail table
Write-Host ('  {0,-6} {1,-48} {2,-6} {3}' -f 'Tag', 'Description', 'Status', 'Detail') -ForegroundColor DarkGray
Write-Host ('  ' + ('─' * 74)) -ForegroundColor DarkGray
foreach ($r in $results) {
    $c = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
    $desc = if ($r.Description.Length -gt 47) { $r.Description.Substring(0, 44) + '...' } else { $r.Description }
    Write-Host ('  {0,-6} {1,-48} {2,-6}  {3}' -f $r.Tag, $desc, $r.Status, $r.Detail) -ForegroundColor $c
}

Write-Host ''
if ($script:failed -gt 0) { exit 1 } else { exit 0 }
