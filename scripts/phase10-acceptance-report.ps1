function Resolve-Phase10ContinuationDecision {
    param([Parameter(Mandatory)][object]$Summary)
    if ($Summary.status -notin @('passed','partial')) { throw "Structured continuation status '$($Summary.status)' is not an accepted result." }
    $gaps = @($Summary.results | Where-Object status -eq 'gap-observed')
    $unapproved = @($gaps | Where-Object { $_.gap -notmatch '^No order-based Check payment status / Resume payment action\.' })
    if ($unapproved.Count) { throw 'Continuation reported a functional gap outside the approved DW-023 deferral.' }
    if ($Summary.status -eq 'passed' -and $gaps.Count) { throw 'Continuation summary claims PASS while containing gap results.' }
    if ($Summary.status -eq 'partial' -and -not $gaps.Count) { throw 'Continuation summary is partial but contains no structured gap evidence.' }
    return [pscustomobject]@{
        Status = if ($gaps.Count) { 'deferred' } else { 'passed' }
        StructuredStatus = [string]$Summary.status
        DeferredCount = $gaps.Count
        Deferrals = if ($gaps.Count) { @('DW-023') } else { @() }
    }
}
