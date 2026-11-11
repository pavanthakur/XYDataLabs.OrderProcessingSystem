function Get-Phase10NfrAggregate {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Categories)

    $nonPassing = @($Categories.GetEnumerator() |
        Where-Object { $_.Value.status -ne 'passed' } |
        ForEach-Object { "$($_.Key)=$($_.Value.status)" })
    $hasFailed = @($Categories.Values | Where-Object { $_.status -eq 'failed' }).Count -gt 0

    [pscustomobject]@{
        Status = if ($hasFailed) { 'failed' } elseif ($nonPassing.Count -gt 0) { 'incomplete' } else { 'passed' }
        NonPassing = $nonPassing
    }
}
