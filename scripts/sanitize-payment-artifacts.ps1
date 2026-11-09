# Mechanical redaction of generated test artifacts only. Never touches source or F:.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults')) + [IO.Path]::DirectorySeparatorChar
$target = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
if (-not $target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {throw 'Only generated project TestResults artifacts may be sanitized.'}
$item=Get-Item -LiteralPath $target
$files=if($item.PSIsContainer){Get-ChildItem -LiteralPath $target -Recurse -File -Include '*.json','*.md','*.log','*.txt','*.html'}else{@($item)}
foreach($file in $files){
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing reparse-point artifact.'}
    $original=[IO.File]::ReadAllText($file.FullName)
    $clean=[regex]::Replace($original,'(?i)(session_token|access_token|refresh_token|razorpay_signature|client_secret|code)=([^&\s"<>]+)','$1=[REDACTED]')
    $clean=[regex]::Replace($clean,'(?i)(session_token|access_token|refresh_token|razorpay_signature|client_secret)("\s*:\s*")[^"]*','$1$2[REDACTED]')
    if($original -ne $clean){[IO.File]::WriteAllText($file.FullName,$clean)}
}
Write-Output 'Generated payment artifacts sanitized. Values were not printed.'
