function Resolve-Phase10DockerE2ERunId {
    [CmdletBinding()]
    param([string]$RunId = '')

    $resolved = if ([string]::IsNullOrWhiteSpace($RunId)) {
        "phase10-docker-http-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
    } else { $RunId }
    # Workflow 99 reserves its packet path before the hook starts.
    if ($resolved -cmatch '\Aphase10-docker-dev-http-[0-9]+-[0-9]+\z') { return $resolved }
    $prefix = 'phase10-docker-http-'
    if (-not $resolved.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw 'RunId must use the canonical local timestamp or workflow 99 packet format.'
    }
    $timestampText = $resolved.Substring($prefix.Length)
    $timestamp = [DateTime]::MinValue
    $valid = [DateTime]::TryParseExact(
        $timestampText,
        'yyyyMMdd-HHmmssfff',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$timestamp
    )
    if (-not $valid) { throw 'RunId must use the canonical local timestamp or workflow 99 packet format.' }
    return $resolved
}
