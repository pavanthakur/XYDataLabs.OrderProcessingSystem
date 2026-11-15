#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../phase10-razorpay-order-lookup-core.ps1')
$script:passed = 0
function Assert-Test($Name, [scriptblock]$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function Assert-Throws([scriptblock]$Body) { $threw=$false; try { & $Body | Out-Null } catch { $threw=$true }; if (-not $threw) { throw 'Expected refusal.' } }
function New-Order { [pscustomobject]@{ id='order_fixture'; amount=20000; currency='INR'; status='created'; amount_paid=0; amount_due=20000; attempts=0 } }
function New-Payment { [pscustomobject]@{ id='pay_fixture'; order_id='order_fixture'; amount=20000; currency='INR'; status='captured'; card='must-not-appear'; email='must-not-appear' } }
$parameters=@{ OrderId='order_fixture'; KeyId='rzp_test_fixture'; PrivateKey='private-fixture'; ExpectedAmountMinor=20000; ExpectedCurrency='INR' }
$script:calls=@()
$script:order=New-Order; $script:payments=@()
$fakeRequest={ param($Uri,$Headers)
    $script:calls+= $Uri
    if ($Uri -notmatch '^https://api\.razorpay\.com/v1/orders/order_fixture(?:/payments\?count=100&skip=\d+)?$') { throw 'Unexpected provider URI' }
    if ($Uri -like '*/payments?*') { return [pscustomobject]@{count=$script:payments.Count;items=$script:payments} }
    return $script:order
}
Assert-Test 'No payment attempts is not fabricated payment success' {
    $result=Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest
    if ($result.classification -ne 'NO_PAYMENT_ATTEMPTS' -or $result.newCharges -ne 0 -or $script:calls.Count -ne 2) { throw 'Bad empty-order evidence' }
}
Assert-Test 'Captured payment and matching paid order are identified; sensitive payload fields excluded' {
    $script:order.status='paid';$script:order.amount_paid=20000;$script:order.amount_due=0;$script:order.attempts=1;$script:payments=@(New-Payment)
    $result=Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest
    if ($result.classification -ne 'PAID' -or ($result | ConvertTo-Json -Depth 8) -match 'must-not-appear|private-fixture|rzp_test_fixture|Authorization') { throw 'Unsafe/incorrect evidence' }
}
Assert-Test 'Authorized is not captured' {
    $script:payments[0].status='authorized'
    if ((Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest).classification -ne 'AUTHORIZED_NOT_CAPTURED') { throw 'Authorization mislabelled' }
}
Assert-Test 'Failed attempts remain failed without retry' {
    $script:payments[0].status='failed';$script:order.amount_paid=0;$script:order.amount_due=20000;$script:order.status='attempted'
    if ((Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest).classification -ne 'ONLY_FAILED_ATTEMPTS') { throw 'Failed payment mislabelled' }
}
Assert-Test 'Live key and URI injection are rejected before requests' {
    $before=$script:calls.Count
    $bad=$parameters.Clone();$bad.KeyId='rzp_live_fixture';Assert-Throws {Get-Phase10RazorpayOrderEvidence @bad -Request $fakeRequest}
    $bad=$parameters.Clone();$bad.OrderId='order_fixture/../../payments';Assert-Throws {Get-Phase10RazorpayOrderEvidence @bad -Request $fakeRequest}
    if ($script:calls.Count -ne $before) { throw 'Unsafe input reached provider' }
}
Assert-Test 'Mismatched amount fails closed' {
    $script:order.amount=1;Assert-Throws {Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest};$script:order.amount=20000
}
Assert-Test 'Cross-order payments fail closed' {
    $script:payments[0].order_id='order_other';Assert-Throws {Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest};$script:payments[0].order_id='order_fixture'
}
Assert-Test 'Duplicate payment evidence fails closed' {
    $script:order.attempts=2;$script:payments=@(New-Payment;New-Payment);Assert-Throws {Get-Phase10RazorpayOrderEvidence @parameters -Request $fakeRequest}
}
Assert-Test 'Provider error omits raw credentials and URL diagnostics' {
    try { Get-Phase10RazorpayOrderEvidence @parameters -Request {throw 'private-fixture raw-provider-payload'}; throw 'Expected exception' }
    catch { if ($_.Exception.Message -match 'private-fixture|raw-provider-payload|Expected exception') { throw 'Unsafe error' } }
}
Assert-Test 'Unbounded pagination refuses incomplete evidence' {
    Assert-Throws {Get-Phase10RazorpayOrderEvidence @parameters -Request {param($Uri,$Headers)
        if ($Uri -like '*/payments?*') { return [pscustomobject]@{count=100;items=@(1..100 | ForEach-Object { New-Payment })} }; New-Order
    }}
}
Write-Host "Passed $script:passed read-only provider diagnostic tests. No network/identity/database access."
