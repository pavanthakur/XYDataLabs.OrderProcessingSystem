# Read-only SQL proof shared by physical and Azure payment verification.
function Get-Phase10PaidOrderEvidence {
    param([Parameter(Mandatory)][string]$TenantCode,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CustomerOrderIds,
        [string]$ExpectedReference,
        [Parameter(Mandatory)][scriptblock]$Query)
    if ($TenantCode -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Invalid tenant evidence key.' }
    $passed=0
    $unique=@($CustomerOrderIds | Sort-Object -Unique)
    foreach($order in $unique){
        if($order -notmatch '^ORDER-([0-9]{1,10})$'){continue}
        $number=[long]$Matches[1]
        if($number -le 0 -or $number -gt [int]::MaxValue){continue}
        $rows=@(& $Query @"
SELECT o.Status AS OrderStatus, CONVERT(nvarchar(36),o.OrderReferenceId) AS OrderReferenceId,
 (SELECT COUNT(*) FROM payments.CardTransactions ct WHERE ct.TenantId=o.TenantId AND ct.CustomerOrderId=N'$order' AND ct.TransactionType='charge' AND ct.IsTransactionSuccess=1) AS SuccessfulCharges,
 (SELECT COUNT(*) FROM payments.CardTransactions ct WHERE ct.TenantId=o.TenantId AND ct.CustomerOrderId=N'$order' AND ct.TransactionType='charge' AND ct.IsTransactionSuccess=1 AND ct.Amount=o.TotalPrice AND ct.CurrencyCode=o.CurrencyCode AND ct.TransactionStatus='completed') AS MatchingCharges,
 (SELECT COUNT(*) FROM payments.PaymentAttempts pa WHERE pa.TenantId=o.TenantId AND pa.CustomerOrderId=N'$order' AND pa.Status='Succeeded') AS SucceededAttempts
FROM orders.Orders o JOIN dbo.Tenants t ON t.Id=o.TenantId
WHERE t.Code=N'$TenantCode' AND o.OrderId=$number;
"@)
        if($rows.Count -eq 1 -and $rows[0].OrderStatus -eq 'Paid' -and $rows[0].SuccessfulCharges -eq 1 -and
            $rows[0].MatchingCharges -eq 1 -and $rows[0].SucceededAttempts -eq 1 -and
            ([string]::IsNullOrWhiteSpace($ExpectedReference) -or $rows[0].OrderReferenceId -eq $ExpectedReference)){ $passed++ }
    }
    [pscustomobject]@{Expected=$CustomerOrderIds.Count;Verified=$passed;Passed=($unique.Count -gt 0 -and $unique.Count -eq $CustomerOrderIds.Count -and $passed -eq $unique.Count)}
}
