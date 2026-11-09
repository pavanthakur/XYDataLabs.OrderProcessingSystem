#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TenantCode,[Parameter(Mandatory)][int]$OrderId,
    [Parameter(Mandatory)][ValidateSet('success','failure','cancelled','currency-rejected')][string]$ExpectedOutcome,
    [decimal]$ExpectedAmount=-1,[string]$ExpectedCurrency,[string]$ExpectedReference)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
Assert-Phase10ComposeProject
$settings=Get-Phase10LocalSettings -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Resources/Docker/.env.local')
$database=Resolve-Phase10LocalTenantDatabase -TenantCode $TenantCode -Settings $settings
$cs=New-Phase10HostSqlConnectionString -Database $database -Password $settings.LOCAL_SQL_PASSWORD
Assert-Phase10HostSqlIdentity -ConnectionString $cs
$connection=[System.Data.SqlClient.SqlConnection]::new($cs)
try {
    $connection.Open();$command=$connection.CreateCommand()
    $command.CommandText=@'
SELECT o.Status,
 (SELECT COUNT(*) FROM payments.CardTransactions ct WHERE ct.TenantId=o.TenantId AND ct.CustomerOrderId=@reference AND ct.TransactionType='charge' AND ct.IsTransactionSuccess=1) AS SuccessfulCharges,
 (SELECT COUNT(*) FROM payments.PaymentAttempts pa WHERE pa.TenantId=o.TenantId AND pa.CustomerOrderId=@reference AND pa.Status='Failed') AS FailedAttempts,
 o.TotalPrice,o.CurrencyCode,o.OrderReferenceId,
 (SELECT COUNT(*) FROM payments.PaymentAttempts pa WHERE pa.TenantId=o.TenantId AND pa.CustomerOrderId=@reference AND pa.Status='Succeeded') AS SucceededAttempts,
 (SELECT COUNT(*) FROM payments.PaymentAttempts pa WHERE pa.TenantId=o.TenantId AND pa.CustomerOrderId=@reference) AS AllAttempts,
 (SELECT COUNT(*) FROM payments.CardTransactions ct WHERE ct.TenantId=o.TenantId AND ct.CustomerOrderId=@reference) AS AllTransactions,
 (SELECT COUNT(*) FROM payments.PayinLogs pl WHERE pl.TenantId=o.TenantId AND pl.CustomerOrderId=@reference) AS AllPayinLogs
FROM orders.Orders o JOIN dbo.Tenants t ON t.Id=o.TenantId WHERE o.OrderId=@orderId AND t.Code=@tenant;
'@
    [void]$command.Parameters.AddWithValue('@reference',"ORDER-$OrderId")
    [void]$command.Parameters.AddWithValue('@orderId',$OrderId)
    [void]$command.Parameters.AddWithValue('@tenant',$TenantCode)
    $reader=$command.ExecuteReader()
    if(-not $reader.Read()){throw 'Negative test order was not found in the expected tenant database.'}
    $status=$reader.GetString(0);$successful=$reader.GetInt32(1);$failed=$reader.GetInt32(2)
    $actualAmount=$reader.GetDecimal(3);$actualCurrency=$reader.GetString(4);$actualReference=$reader.GetGuid(5).ToString()
    if($ExpectedOutcome-eq'success'){
        if($status -ne 'Paid' -or $successful -ne 1 -or $reader.GetInt32(6) -ne 1 -or $actualAmount -ne $ExpectedAmount -or $actualCurrency -ne $ExpectedCurrency -or $actualReference -ne $ExpectedReference){throw 'Positive payment SQL verification failed: Paid order, unique successful charge and matching terms were not proven.'}
    }elseif($ExpectedOutcome-eq'currency-rejected'){
        if($status -ne 'Created' -or $reader.GetInt32(7) -ne 0 -or $reader.GetInt32(8) -ne 0 -or $reader.GetInt32(9) -ne 0 -or
            $actualAmount -ne $ExpectedAmount -or $actualCurrency -ne $ExpectedCurrency -or $actualReference -ne $ExpectedReference){throw 'Currency rejection must preserve order terms and create no attempts, transactions or payin logs.'}
    }elseif($status-ne'Created'-or$successful-ne 0-or($ExpectedOutcome-eq'failure'-and$failed-lt 1)){throw 'Negative payment SQL verification failed: unpaid order and expected attempt state were not proven.'}
    @{tenantCode=$TenantCode;orderId=$OrderId;expectedOutcome=$ExpectedOutcome;orderStatus=$status;successfulCharges=$successful;failedAttempts=$failed;
      allAttempts=$reader.GetInt32(7);allTransactions=$reader.GetInt32(8);allPayinLogs=$reader.GetInt32(9);status='passed'}|ConvertTo-Json -Compress
}finally{$connection.Dispose()}
