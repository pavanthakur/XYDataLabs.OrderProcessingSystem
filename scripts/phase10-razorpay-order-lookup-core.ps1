# Provider read-only diagnostic. No charge, capture, refund, cancellation or SQL mutation.
function Get-Phase10RazorpayOrderEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OrderId,
        [Parameter(Mandatory)][string]$KeyId,
        [Parameter(Mandatory)][string]$PrivateKey,
        [Parameter(Mandatory)][long]$ExpectedAmountMinor,
        [Parameter(Mandatory)][string]$ExpectedCurrency,
        [scriptblock]$Request = {
            param($Uri, $Headers)
            Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
        }
    )
    if ($OrderId -cnotmatch '^order_[A-Za-z0-9]{1,80}$' -or $KeyId -cnotmatch '^rzp_test_[A-Za-z0-9]+$' -or
        [string]::IsNullOrWhiteSpace($PrivateKey) -or $ExpectedAmountMinor -le 0 -or $ExpectedCurrency -cne 'INR') {
        throw 'Invalid order/sandbox credentials or expected terms; no provider request was made.'
    }
    $headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${KeyId}:${PrivateKey}")) }
    try {
        try { $order = & $Request "https://api.razorpay.com/v1/orders/$OrderId" $headers }
        catch { throw 'Razorpay order GET failed; raw provider/credential diagnostics omitted.' }
        if ($order.id -cne $OrderId -or $order.amount -ne $ExpectedAmountMinor -or $order.currency -cne $ExpectedCurrency) {
            throw 'Provider order identity/amount/currency mismatch; acceptance blocked.'
        }
        if ($order.status -notin @('created','attempted','paid') -or $order.amount_paid -lt 0 -or $order.amount_due -lt 0 -or
            ($order.amount_paid + $order.amount_due) -ne $ExpectedAmountMinor -or $order.attempts -lt 0) {
            throw 'Malformed provider order accounting/status; acceptance blocked.'
        }
        $payments = @()
        $complete = $false
        for ($page = 0; $page -lt 10; $page++) {
            try { $response = & $Request "https://api.razorpay.com/v1/orders/$OrderId/payments?count=100&skip=$($page * 100)" $headers }
            catch { throw 'Razorpay order payments GET failed; raw provider/credential diagnostics omitted.' }
            if ($null -eq $response.items -or $response.count -ne @($response.items).Count) { throw 'Malformed provider payment collection; acceptance blocked.' }
            $payments += @($response.items)
            if (@($response.items).Count -lt 100) { $complete = $true; break }
        }
        if (-not $complete) { throw 'Provider pagination limit reached; incomplete evidence, acceptance blocked.' }
        if ($order.attempts -ne $payments.Count) { throw 'Order/payment attempt count changed or is inconsistent; repeat a read-only review, never a charge.' }
        $ids = @{}
        foreach ($payment in $payments) {
            if ($payment.id -cnotmatch '^pay_[A-Za-z0-9]{1,80}$' -or $ids.ContainsKey([string]$payment.id) -or
                $payment.order_id -cne $OrderId -or $payment.amount -ne $ExpectedAmountMinor -or $payment.currency -cne $ExpectedCurrency -or
                $payment.status -notin @('created','authorized','captured','refunded','failed')) {
                throw 'Provider payment identity/terms/status inconsistent; acceptance blocked.'
            }
            $ids[[string]$payment.id] = $true
        }
        $classification = if ($payments.Count -eq 0 -and $order.status -eq 'created' -and $order.amount_paid -eq 0 -and $order.attempts -eq 0) { 'NO_PAYMENT_ATTEMPTS' }
            elseif (@($payments | Where-Object status -eq 'authorized').Count) { 'AUTHORIZED_NOT_CAPTURED' }
            elseif (@($payments | Where-Object status -eq 'captured').Count -eq 1 -and $order.status -eq 'paid' -and $order.amount_paid -eq $ExpectedAmountMinor) { 'PAID' }
            elseif ($payments.Count -gt 0 -and @($payments | Where-Object status -ne 'failed').Count -eq 0 -and $order.amount_paid -eq 0) { 'ONLY_FAILED_ATTEMPTS' }
            else { 'UNRESOLVED' }
        [pscustomobject]@{
            schemaVersion = 1; operation = 'read-only-provider-order-lookup'; sandbox = $true
            orderId = $OrderId; amountMinor = $order.amount; currency = $order.currency
            orderStatus = $order.status; amountPaidMinor = $order.amount_paid; amountDueMinor = $order.amount_due
            attempts = $order.attempts; classification = $classification; paymentCount = $payments.Count
            payments = @($payments | Select-Object id, status, amount, currency)
            complete = $true; newCharges = 0
        }
    } finally { $headers.Clear(); $PrivateKey = $null; $KeyId = $null }
}
