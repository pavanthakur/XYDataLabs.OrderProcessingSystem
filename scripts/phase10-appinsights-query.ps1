function Get-Phase10AppInsightsFailureCategory {
    param([AllowNull()][string] $OutputText)

    if ($OutputText -match '(?i)BadArgumentError|invalid properties|invalid query|syntax error') { return 'invalidQuery' }
    if ($OutputText -match '(?i)Forbidden|AuthorizationFailed|insufficient privileges|does not have.*permission') { return 'accessDenied' }
    if ($OutputText -match '(?i)TooManyRequests|throttl') { return 'throttled' }
    if ($OutputText -match '(?i)not found|ResourceNotFound') { return 'resourceNotFound' }
    return 'cliFailure'
}

function ConvertFrom-Phase10AppInsightsCliResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Output,
        [Parameter(Mandatory)][int] $ExitCode,
        [Parameter(Mandatory)][string] $Operation
    )

    $rawText = (@($Output | ForEach-Object { [string] $_ }) -join [Environment]::NewLine).Trim()
    if ($ExitCode -ne 0) {
        $category = Get-Phase10AppInsightsFailureCategory -OutputText $rawText
        throw "App Insights query '$Operation' failed (Azure CLI exit $ExitCode; $category)."
    }
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        throw "App Insights query '$Operation' returned an empty response (responseInvalid)."
    }

    try { $response = $rawText | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "App Insights query '$Operation' returned malformed JSON (responseInvalid)." }

    if ($null -ne $response.PSObject.Properties['error'] -and $null -ne $response.PSObject.Properties['error'].Value) {
        throw "App Insights query '$Operation' returned an Azure error payload (responseError)."
    }
    if ($null -eq $response.PSObject.Properties['tables'] -or $response.tables -isnot [array]) {
        throw "App Insights query '$Operation' returned no tables collection (responseInvalid)."
    }
    foreach ($table in $response.tables) {
        if ($null -eq $table.PSObject.Properties['columns'] -or $null -eq $table.PSObject.Properties['rows']) {
            throw "App Insights query '$Operation' returned an invalid table (responseInvalid)."
        }
        if ($table.columns -isnot [array] -or $table.rows -isnot [array]) {
            throw "App Insights query '$Operation' returned invalid table collections (responseInvalid)."
        }
    }

    return $response
}

function ConvertTo-Phase10AppInsightsRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Response)

    if ($Response.tables.Count -eq 0) { return @() }
    $table = $Response.tables[0]
    $columnNames = @($table.columns | ForEach-Object { [string] $_.name })
    $rows = @()
    foreach ($row in $table.rows) {
        if ($row.Count -ne $columnNames.Count) {
            throw 'App Insights table row has a column-count mismatch (responseInvalid).'
        }
        $item = [ordered]@{}
        for ($index = 0; $index -lt $columnNames.Count; $index++) { $item[$columnNames[$index]] = $row[$index] }
        $rows += [PSCustomObject]$item
    }
    return $rows
}
