$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../phase10-paid-order-evidence.ps1')
$script:row=@{OrderStatus='Paid';OrderReferenceId='reference';SuccessfulCharges=1;MatchingCharges=1;SucceededAttempts=1}
$query={param($sql) if($sql -notmatch "t.Code=N'TenantD' AND o.OrderId=1" -or $sql -notmatch 'ct.TenantId=o.TenantId'){throw 'Missing tenant/order SQL scope'};[pscustomobject]$script:row}
$valid=Get-Phase10PaidOrderEvidence -TenantCode TenantD -CustomerOrderIds @('ORDER-1') -ExpectedReference reference -Query $query
if(-not $valid.Passed){throw 'Valid scoped order proof rejected'}
foreach($property in @('OrderStatus','SuccessfulCharges','MatchingCharges','SucceededAttempts','OrderReferenceId')){
    $original=$script:row[$property];$script:row[$property]=if($property -eq 'OrderStatus'){'Created'}elseif($property -eq 'OrderReferenceId'){'wrong'}else{0}
    if((Get-Phase10PaidOrderEvidence -TenantCode TenantD -CustomerOrderIds @('ORDER-1') -ExpectedReference reference -Query $query).Passed){throw "Missing $property incorrectly passed"}
    $script:row[$property]=$original
}
foreach($orders in @(@(),@('ORDER-1','ORDER-1'),@('ORDER-1; DROP TABLE orders.Orders'))){
    if((Get-Phase10PaidOrderEvidence -TenantCode TenantD -CustomerOrderIds $orders -Query $query).Passed){throw 'Invalid/missing/duplicate order anchors passed'}
}
Write-Host 'Paid-order evidence tests passed: scoped Paid state, unique success, terms, attempt, reference and invalid anchors.'
