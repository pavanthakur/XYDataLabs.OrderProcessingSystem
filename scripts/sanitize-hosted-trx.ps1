# Remove free-form test output and failure text before TRX files are published as artifacts.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResultsRoot)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ResultsRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $ResultsRoot -Force | Out-Null
    exit 0
}

$trxFiles = @(Get-ChildItem -LiteralPath $ResultsRoot -Filter '*.trx' -File -Recurse)
foreach ($file in $trxFiles) {
    [xml]$document = Get-Content -LiteralPath $file.FullName -Raw
    $namespace = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
    $namespace.AddNamespace('trx', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')

    foreach ($node in @($document.SelectNodes('//trx:StdOut | //trx:StdErr | //trx:StackTrace | //trx:Attachments', $namespace))) {
        [void]$node.ParentNode.RemoveChild($node)
    }
    foreach ($message in @($document.SelectNodes('//trx:ErrorInfo/trx:Message', $namespace))) {
        $message.InnerText = 'Failure details omitted from artifact; inspect the secured workflow logs.'
    }
    $document.Save($file.FullName)
}

Write-Host "Sanitized $($trxFiles.Count) known TRX result file(s); free-form output, stack traces and attachments were removed."
