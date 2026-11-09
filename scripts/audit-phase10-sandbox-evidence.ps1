#Requires -Version 7.0
# Read-only supplemental audit. Never changes a raw case, provider setting or payment.
param([Parameter(Mandatory)][string]$SummaryPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$root=Split-Path -Parent $PSScriptRoot
$allowed=[IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'
foreach($path in @($SummaryPath,$OutputPath)){if(-not[IO.Path]::GetFullPath($path).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence paths must stay under TestResults.'}}
if(Test-Path $OutputPath){throw 'Supplemental evidence already exists; preserve the historical audit.'}
$summary=Get-Content $SummaryPath -Raw|ConvertFrom-Json
if($summary.mode-ne'sandbox'-or$summary.negative-or$summary.status-eq'running'){throw 'A finished positive sandbox report is required.'}
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
$results=@()
function ConvertTo-EvidenceUtc($value){
    if($value-is[DateTime]){return $value.ToUniversalTime()}
    return [DateTimeOffset]::Parse($value,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}
foreach($run in $summary.results){if(-not$run.rows){continue};foreach($row in $run.rows){
if(-not[IO.Path]::GetFullPath($run.reportDirectory).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)-or$row.tenantCode-notmatch'^[A-Za-z0-9_-]{1,64}$'){throw 'Unapproved report source or tenant.'}
    $proof=[ordered]@{tenant=$row.tenantCode;provider=$row.paymentProvider;rawJourney=$row.journeyOutcome;sourceReport=$run.reportDirectory;paymentEvidenceStatus='not-proven';challengeAcceptance=$(if($row.observedChallenge-eq'presented'-and$row.challengeOutcome-eq'passed'){'passed'}else{'not-proven'});note='Supplemental SQL/dependency audit does not turn a missing visible challenge into PASS.'}
    $dependencyPath=Join-Path $run.reportDirectory 'provider-dependencies.json'
    if(-not(Test-Path $dependencyPath)){$results+=$proof;continue}
    $lines=(Get-Content $dependencyPath -Raw|ConvertFrom-Json).evidence
    $fetches=@(foreach($line in $lines){if($line-match 'Provider=(\S+) Simulation=False Operation=fetch-charge ProviderPaymentId=(\S+) Amount=(\S+) Currency=(\S+) Status=(completed|captured|paid)\b' -and $Matches[1]-eq$row.paymentProvider){@{id=$Matches[2];amount=[decimal]::Parse($Matches[3],[Globalization.CultureInfo]::InvariantCulture);currency=$Matches[4]}}})
    $proof.confirmedDependencyCount=$fetches.Count
    $database=Resolve-Phase10LocalTenantDatabase -TenantCode $row.tenantCode -Settings $settings
    $cs=New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
    Assert-Phase10HostSqlIdentity -ConnectionString $cs
    $cx=[System.Data.SqlClient.SqlConnection]::new($cs);$found=@()
    try{
        $cx.Open()
        foreach($fetch in @($fetches|Sort-Object id -Unique)){
            if($fetch.id-match'^DET-'){continue}
            $transactionId=$fetch.id
            if($row.paymentProvider-eq'Razorpay'){
                $confirmationPath=Join-Path $run.reportDirectory "$($row.tenantCode)/razorpay/provider-confirmation.json"
                if(-not(Test-Path $confirmationPath)){continue}
                $confirmation=(Get-Content $confirmationPath -Raw|ConvertFrom-Json).confirmation
                if($confirmation.paymentId-ne$fetch.id-or-not$confirmation.remoteStatusConfirmed-or-not$confirmation.isSuccess){continue}
                # Razorpay charge records retain the provider order ID; the authoritative fetch uses its payment ID.
                $transactionId=$confirmation.providerOrderId
            }
            $q=$cx.CreateCommand();$q.CommandText=@'
SELECT o.OrderId,o.OrderReferenceId,o.TotalPrice,o.CurrencyCode,o.Status,ct.Amount,ct.CurrencyCode,
 (SELECT COUNT(*) FROM payments.CardTransactions c WHERE c.TenantId=o.TenantId AND c.CustomerOrderId=ct.CustomerOrderId AND c.TransactionType='charge' AND c.IsTransactionSuccess=1) ChargeCount,
 (SELECT COUNT(*) FROM payments.PaymentAttempts p WHERE p.TenantId=o.TenantId AND p.CustomerOrderId=ct.CustomerOrderId AND p.Status='Succeeded' AND p.PaymentProviderName=@provider) AttemptCount
FROM payments.CardTransactions ct JOIN dbo.Tenants t ON t.Id=ct.TenantId
JOIN orders.Orders o ON o.TenantId=ct.TenantId AND ct.CustomerOrderId=CONCAT('ORDER-',o.OrderId)
WHERE t.Code=@tenant AND ct.TransactionId=@payment AND ct.TransactionType='charge' AND ct.IsTransactionSuccess=1
AND ct.CreatedDate>=@started AND ct.CreatedDate<=@finished;
'@
            foreach($pair in @{tenant=$row.tenantCode;payment=$transactionId;provider=$row.paymentProvider;started=(ConvertTo-EvidenceUtc $row.startedUtc).AddSeconds(-5);finished=(ConvertTo-EvidenceUtc $row.finishedUtc).AddSeconds(5)}.GetEnumerator()){[void]$q.Parameters.AddWithValue('@'+$pair.Key,$pair.Value)}
            $r=$q.ExecuteReader()
            while($r.Read()){
                $valid=$r.GetString(4)-eq'Paid'-and$r.GetDecimal(2)-eq$fetch.amount-and$r.GetDecimal(5)-eq$fetch.amount-and$r.GetString(3)-eq$fetch.currency-and$r.GetString(6)-eq$fetch.currency-and$r.GetInt32(7)-eq 1-and$r.GetInt32(8)-eq 1
                $create=$lines|Where-Object {$_-like "*Provider=$($row.paymentProvider) Simulation=False Operation=create-charge*"}
                if($valid-and$create){$found+=@{orderId=$r.GetInt32(0);orderReference=$r.GetGuid(1).ToString();paymentId=$fetch.id;amount=$fetch.amount;currency=$fetch.currency}}
            }
            $r.Dispose();$q.Dispose()
        }
    }finally{$cx.Dispose()}
    $proof.matchingRecordCount=$found.Count
    if($found.Count-eq 1){$proof.paymentEvidenceStatus='passed';$proof.correlated=$found[0]}
    $results+=$proof
}}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
@{kind='read-only-supplemental-audit';capturedUtc=[DateTime]::UtcNow.ToString('o');source=$SummaryPath;rawReportsPreserved=$true;results=$results;certifiesVisibleChallenge=$false}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $OutputPath
Write-Host "Supplemental payment evidence: $OutputPath"
