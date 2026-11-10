#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'phase10-dotnet-inventory.ps1')
$root=Split-Path -Parent $PSScriptRoot
$artifact=[IO.Path]::GetFullPath($ArtifactDirectory)
if(-not $artifact.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Test artifacts must remain under project TestResults.'}
[void][IO.Directory]::CreateDirectory($artifact)
$settings=Get-Phase10LocalSettings -Path (Join-Path $root 'Resources/Docker/.env.local')
Initialize-Phase10LogRedaction -Settings $settings
$results=@()
$runnerCompleted=$false
function Run-Test([string]$name,[string]$command,[string[]]$arguments){
    $started=[DateTime]::UtcNow
    & $command @arguments 2>&1|Protect-Phase10Log|Tee-Object -FilePath (Join-Path $artifact "$name.log")|Out-Null
    $code=$LASTEXITCODE
    $script:results+=@{name=$name;exitCode=$code;status=$(if($code-eq 0){'passed'}else{'failed'});startedUtc=$started.ToString('o');finishedUtc=[DateTime]::UtcNow.ToString('o')}
    Write-Host "$name exit=$code"
}
function Write-AutomationTestResults([string]$suiteId,[string]$logPath,[int]$runnerExitCode){
    $inventoryPath=Join-Path $root 'automation/config/phase10-automation-test-inventory.json'
    $inventory=Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    if($inventory.schema -cne 'phase10-automation-test-inventory-v1'){throw 'Automation test inventory schema is unsupported.'}
    $suite=@($inventory.suites|Where-Object id -CEQ $suiteId)
    if($suite.Count -ne 1){throw "Automation test inventory suite is missing or duplicated: $suiteId"}
    $expected=@($suite[0].tests)
    if($expected.Count -eq 0 -or @($expected|Select-Object -Unique).Count -ne $expected.Count){throw "Automation test inventory is empty or duplicated: $suiteId"}
    $log=Get-Content -LiteralPath $logPath -Raw
    $tapIndex=$log.IndexOf("TAP version ",[StringComparison]::Ordinal)
    if($tapIndex -lt 0){throw "Structured TAP output is missing: $suiteId"}
    $tap=$log.Substring($tapIndex)
    $observed=@()
    foreach($line in ($tap -split "`r?`n")){
        $match=[regex]::Match($line,'^\s*(not )?ok\s+\d+\s+-\s+(.+?)(?:\s+#\s+(SKIP|TODO)\b.*)?\s*$')
        if($match.Success){$observed+=@{name=$match.Groups[2].Value;status=$(if($match.Groups[1].Success){'failed'}elseif($match.Groups[3].Success){'skipped'}else{'passed'})}}
    }
    $duplicates=@($observed|Group-Object name|Where-Object Count -gt 1)
    $missing=@($expected|Where-Object {$_ -notin @($observed|ForEach-Object name)})
    $unexpected=@($observed|Where-Object {$_.name -notin $expected})
    $complete=$runnerExitCode -eq 0 -and $observed.Count -eq $expected.Count -and
        $duplicates.Count -eq 0 -and $missing.Count -eq 0 -and $unexpected.Count -eq 0 -and
        @($observed|Where-Object status -ne 'passed').Count -eq 0
    $testResults=@(foreach($testName in $expected){
        $match=@($observed|Where-Object name -CEQ $testName)
        $identity=('{0}::{1}' -f $suiteId,$testName)
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))).ToLowerInvariant()
        @{id="${suiteId}:$($hash.Substring(0,16))";status=$(if($match.Count -eq 1){$match[0].status}else{'unavailable'})}
    })
    $inventoryHash=(Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $resultRoot=Join-Path $artifact 'automation-tests'
    [void][IO.Directory]::CreateDirectory($resultRoot)
    $resultPath=Join-Path $resultRoot "$suiteId.json"
    @{schema='phase10-automation-test-results-v1';suiteId=$suiteId;inventorySha256=$inventoryHash;runnerExitCode=$runnerExitCode;complete=$complete;
      expectedCount=$expected.Count;observedCount=$observed.Count;missingCount=$missing.Count;unexpectedCount=$unexpected.Count;
      duplicateCount=$duplicates.Count;tests=$testResults}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $resultPath
    if(-not $complete){throw "Automation test outcomes do not reconcile with the versioned inventory: $suiteId"}
}
function Write-DotnetTestResults([string]$project,[string[]]$discoveredNames,[string]$assemblyPath,[string]$assemblyHashBefore,[string]$trxPath,[int]$runnerExitCode,[string]$startedUtc,[string]$finishedUtc){
    $settings=New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $reader=[System.Xml.XmlReader]::Create($trxPath,$settings)
    $actual=@()
    try{
        $document=[System.Xml.XmlDocument]::new();$document.XmlResolver=$null;$document.Load($reader)
        $ns=[System.Xml.XmlNamespaceManager]::new($document.NameTable)
        $ns.AddNamespace('t','http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
        foreach($item in $document.SelectNodes('//t:UnitTestResult',$ns)){
            $name=$item.GetAttribute('testName');$outcome=$item.GetAttribute('outcome')
            $state=switch -Regex ($outcome){'^Passed$' {'passed';break} '^Failed$|^Error$|^Timeout$|^Aborted$' {'failed';break} '^NotExecuted$|^Skipped$' {'skipped';break} default {'unavailable'}}
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($name))).ToLowerInvariant()
            $actual+=@{id="${project}:$hash";status=$state}
        }
    }finally{$reader.Dispose()}
    $expectedIds=@($discoveredNames|ForEach-Object {
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_))).ToLowerInvariant()
        "${project}:$hash"
    })
    $inventoryHashInput=[string]::Join("`n",@($expectedIds|Sort-Object -CaseSensitive))
    $inventoryHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($inventoryHashInput))).ToLowerInvariant()
    $actualIds=@($actual|ForEach-Object id)
    $duplicateIds=@($actualIds|Group-Object|Where-Object Count -gt 1)
    $missing=@($expectedIds|Where-Object {$_ -notin $actualIds})
    $unexpected=@($actualIds|Where-Object {$_ -notin $expectedIds})
    $assemblyHashAfter=(Get-FileHash -LiteralPath $assemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $allPassed=@($actual|Where-Object status -ne 'passed').Count -eq 0
    $complete=$runnerExitCode -eq 0 -and $assemblyHashBefore -ceq $assemblyHashAfter -and
        $expectedIds.Count -gt 0 -and @($expectedIds|Select-Object -Unique).Count -eq $expectedIds.Count -and
        $actual.Count -eq $expectedIds.Count -and $duplicateIds.Count -eq 0 -and
        $missing.Count -eq 0 -and $unexpected.Count -eq 0 -and $allPassed
    $resultRoot=Join-Path $artifact 'dotnet-tests';[void][IO.Directory]::CreateDirectory($resultRoot)
    $resultPath=Join-Path $resultRoot "$project.json"
    @{schema='phase10-dotnet-test-results-v1';project=$project;runnerExitCode=$runnerExitCode;complete=$complete;
      startedUtc=$startedUtc;finishedUtc=$finishedUtc;assemblySha256=$assemblyHashAfter;inventorySha256=$inventoryHash;
      expectedIds=$expectedIds;expectedCount=$expectedIds.Count;observedCount=$actual.Count;
      missingCount=$missing.Count;unexpectedCount=$unexpected.Count;duplicateCount=$duplicateIds.Count;tests=$actual}|
        ConvertTo-Json -Depth 5|Set-Content -LiteralPath $resultPath
    if(-not $complete){throw "Discovered .NET tests did not reconcile with TRX outcomes: $project"}
}
function Write-BackendCoverageHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CoveragePath,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$LogPath
    )
    $coverage = Get-Item -LiteralPath $CoveragePath -Force
    if ($coverage.PSIsContainer -or ($coverage.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $coverage.Length -gt 2MB) {
        throw 'Coverage input must be a bounded regular file.'
    }
    if (Test-Path -LiteralPath $TargetDirectory) { throw 'Backend coverage HTML output already exists.' }
    $readerSettings = [Xml.XmlReaderSettings]::new()
    $readerSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($CoveragePath, $readerSettings)
    $expectedCounts = @{}
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        $coverageRoot = $document.DocumentElement
        if (-not $coverageRoot -or $coverageRoot.Name -cne 'coverage') {
            throw 'Coverage XML has an invalid root.'
        }
        foreach ($metric in @(@('lines-covered', 'lines-valid'), @('branches-covered', 'branches-valid'))) {
            $coveredText = $coverageRoot.GetAttribute($metric[0])
            $totalText = $coverageRoot.GetAttribute($metric[1])
            $covered = 0L
            $total = 0L
            if ($coveredText -cnotmatch '^\d+$' -or $totalText -cnotmatch '^\d+$' -or
                -not [long]::TryParse($coveredText, [ref]$covered) -or
                -not [long]::TryParse($totalText, [ref]$total) -or
                $total -le 0 -or $covered -gt $total -or $total -gt 9007199254740991) {
                throw 'Coverage XML has invalid metric counts.'
            }
            $expectedCounts[$metric[0]] = $covered
            $expectedCounts[$metric[1]] = $total
        }
    } finally { $reader.Dispose() }
    $representedCovered = 0L
    $representedTotal = 0L
    $lineCovered = 0L
    $classLines = @($coverageRoot.SelectNodes('packages/package/classes/class/lines/line'))
    if ($classLines.Count -ne $expectedCounts['lines-valid']) {
        throw 'Coverage XML class lines do not match the root line count.'
    }
    foreach ($line in $classLines) {
        $hitsText = $line.GetAttribute('hits')
        $hits = 0L
        if ($hitsText -cnotmatch '^\d+$' -or -not [long]::TryParse($hitsText, [ref]$hits)) {
            throw 'Coverage XML has an invalid line hit count.'
        }
        if ($hits -gt 0) { $lineCovered++ }
        $branch = $line.GetAttribute('branch')
        if ($branch -ieq 'false') { continue }
        if ($branch -ine 'true') { throw 'Coverage XML has an invalid branch marker.' }
        $condition = [regex]::Match($line.GetAttribute('condition-coverage'), '^\d+(?:\.\d+)?% \((\d+)/(\d+)\)$')
        $covered = 0L
        $total = 0L
        if (-not $condition.Success -or
            -not [long]::TryParse($condition.Groups[1].Value, [ref]$covered) -or
            -not [long]::TryParse($condition.Groups[2].Value, [ref]$total) -or
            $covered -gt $total -or $total -le 0 -or
            $total -gt ($expectedCounts['branches-valid'] - $representedTotal) -or
            $covered -gt ($expectedCounts['branches-covered'] - $representedCovered)) {
            throw 'Coverage XML has invalid line-attached branch counts.'
        }
        $representedCovered += $covered
        $representedTotal += $total
    }
    if ($lineCovered -ne $expectedCounts['lines-covered']) { throw 'Coverage XML class lines do not match the root covered count.' }
    if ($representedTotal -le 0) { throw 'Coverage XML has no line-attached branches.' }
    & dotnet tool run reportgenerator "-reports:$CoveragePath" "-targetdir:$TargetDirectory" '-reporttypes:Html' 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath $LogPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $TargetDirectory 'index.html') -PathType Leaf)) {
        throw 'Backend coverage HTML generation failed; inspect the sanitized log.'
    }
    $index = Get-Item -LiteralPath (Join-Path $TargetDirectory 'index.html') -Force
    if ($index.PSIsContainer -or ($index.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $index.Length -gt 20MB) {
        throw 'Backend coverage HTML must be a bounded regular file.'
    }
    $html = [IO.File]::ReadAllText($index.FullName)
    foreach ($metric in @(
        @('Covered lines', 'lines-covered'),
        @('Coverable lines', 'lines-valid'),
        @('Covered branches', $representedCovered),
        @('Total branches', $representedTotal)
    )) {
        $pattern = '<th>' + [regex]::Escape($metric[0]) + ':</th>\s*<td\b[^>]*>\s*(\d+)\s*</td>'
        $matches = [regex]::Matches($html, $pattern)
        $actual = 0L
        $expected = if ($metric[1] -is [string]) { $expectedCounts[$metric[1]] } else { $metric[1] }
        if ($matches.Count -ne 1 -or -not [long]::TryParse($matches[0].Groups[1].Value, [ref]$actual) -or
            $actual -ne $expected) {
            throw "Backend coverage HTML totals do not match the Cobertura XML for $($metric[0]); report is not reliable."
        }
    }
    if ($representedCovered -ne $expectedCounts['branches-covered'] -or $representedTotal -ne $expectedCounts['branches-valid']) {
        Write-Warning 'Backend coverage HTML excludes branches not attached to Cobertura source lines; its branch totals differ from the XML root.'
    }
}
Push-Location $root
try{
    Run-Test 'docker-safety' 'pwsh' @('-NoProfile','-File','scripts/test-phase10-docker-safety.ps1')
    Run-Test 'fixture-regression' 'pwsh' @('-NoProfile','-File','scripts/test-phase10-payment-fixture.ps1')
    Run-Test 'dotnet-inventory-regression' 'pwsh' @('-NoProfile','-File','scripts/tests/test-phase10-dotnet-inventory.ps1')
    foreach($name in @('Domain','Application','API','Gateway','Architecture')){
        $testCoverageRoot = Join-Path (Join-Path $artifact 'backend-coverage') $name
        if (Test-Path -LiteralPath $testCoverageRoot) { throw "Backend coverage output already exists for $name; refusing to overwrite evidence." }
        $projectPath=Join-Path $root "tests/XYDataLabs.OrderProcessingSystem.$name.Tests/XYDataLabs.OrderProcessingSystem.$name.Tests.csproj"
        $discoveryStarted=[DateTime]::UtcNow
        $discoveryOutput=@(Invoke-Phase10Utf8Native { & dotnet test $projectPath --list-tests --verbosity quiet 2>&1 })
        $discoveryExit=$LASTEXITCODE
        $discoveryLines=@($discoveryOutput|ForEach-Object {[string]$_})
        $discoveryMarker=-1
        for($lineIndex=0;$lineIndex-lt$discoveryLines.Count;$lineIndex++){if($discoveryLines[$lineIndex]-match '^\s*The following Tests are available:'){ $discoveryMarker=$lineIndex;break }}
        $discoveredNames=@()
        if($discoveryMarker-ge 0){$discoveredNames=@($discoveryLines|Select-Object -Skip ($discoveryMarker+1)|Where-Object {$_ -match '^\s{4}\S'}|ForEach-Object {$_.Trim()})}
        if($discoveryExit-ne 0-or$discoveredNames.Count-eq 0){throw "Current-candidate .NET test discovery failed: $name"}
        $assemblyPath=Join-Path $root "tests/XYDataLabs.OrderProcessingSystem.$name.Tests/bin/Debug/net8.0/XYDataLabs.OrderProcessingSystem.$name.Tests.dll"
        if(-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)){throw "Discovered test assembly is missing: $name"}
        $assemblyHashBefore=(Get-FileHash -LiteralPath $assemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Run-Test "$name-tests" 'dotnet' @('test',$projectPath,'--no-build','--blame-hang-timeout','90s','--logger','console;verbosity=minimal','--logger',"trx;LogFileName=$name.trx",'--results-directory',$testCoverageRoot,'--settings','scripts/phase10-foundation-coverage.runsettings','--collect','XPlat Code Coverage')
        $trxPath = Join-Path $testCoverageRoot "$name.trx"
        $coverageFiles = @(if (Test-Path -LiteralPath $testCoverageRoot) {
            Get-ChildItem -LiteralPath $testCoverageRoot -Directory | Where-Object {
                $_.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and
                -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
            } | ForEach-Object {
                $candidate = Join-Path $_.FullName 'coverage.cobertura.xml'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
            }
        })
        if ($results[-1].status -eq 'passed' -and (-not (Test-Path -LiteralPath $trxPath -PathType Leaf) -or $coverageFiles.Count -ne 1)) {
            $results[-1].status = 'failed'
            $results[-1].exitCode = 1
            throw "Backend TRX or coverage evidence was missing or duplicated for $name."
        }
        if (Test-Path -LiteralPath $trxPath -PathType Leaf) {
            $finishedUtc=[DateTime]::UtcNow.ToString('o')
            $results[-1].startedUtc=$discoveryStarted.ToString('o')
            # Include inventory reconciliation in the same check window: its
            # evidence timestamp is written after TRX/coverage validation.
            $results[-1].finishedUtc=$finishedUtc
            $results[-1].expectedTests=$discoveredNames.Count
            Write-DotnetTestResults $name $discoveredNames $assemblyPath $assemblyHashBefore $trxPath $results[-1].exitCode $discoveryStarted.ToString('o') $finishedUtc
            $destinationTrx = Join-Path $artifact "$name.trx"
            [IO.File]::Move($trxPath, $destinationTrx)
        }
        if ($results[-1].status -eq 'passed') {
            try {
                Write-BackendCoverageHtml -CoveragePath $coverageFiles[0].FullName `
                    -TargetDirectory (Join-Path $testCoverageRoot 'html') `
                    -LogPath (Join-Path $artifact "$name-coverage-html.log")
            } catch {
                $results[-1].status = 'failed'
                $results[-1].exitCode = 1
                throw
            }
        }
    }
    $previousFrontendReport = $env:PHASE10_FRONTEND_REPORT
    try {
        $env:PHASE10_FRONTEND_REPORT = Join-Path $artifact 'frontend-vitest.json'
        $reporter = Join-Path $root 'frontend/apps/web/scripts/phase10-sanitized-reporter.mjs'
        $coverageDirectory = Join-Path $artifact 'frontend-coverage'
        if (Test-Path -LiteralPath $coverageDirectory) { throw 'Frontend coverage output already exists; refusing to overwrite evidence.' }
        Run-Test 'frontend-tests' 'npm' @('--prefix','frontend','run','test','--workspace','@xydatalabs/orderprocessing-web','--','--reporter=default',"--reporter=$reporter",'--coverage.enabled',"--coverage.reportsDirectory=$coverageDirectory")
        if (-not (Test-Path -LiteralPath $env:PHASE10_FRONTEND_REPORT -PathType Leaf)) {
            $results[-1].status = 'failed'
            $results[-1].exitCode = 1
            throw 'Frontend structured results were not produced.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $coverageDirectory 'coverage-summary.json') -PathType Leaf)) {
            $results[-1].status = 'failed'
            $results[-1].exitCode = 1
            throw 'Frontend coverage summary was not produced.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $coverageDirectory 'index.html') -PathType Leaf)) {
            $results[-1].status = 'failed'
            $results[-1].exitCode = 1
            throw 'Frontend coverage HTML was not produced.'
        }
    } finally {
        if ($null -eq $previousFrontendReport) { Remove-Item Env:PHASE10_FRONTEND_REPORT -ErrorAction SilentlyContinue }
        else { $env:PHASE10_FRONTEND_REPORT = $previousFrontendReport }
    }
    Run-Test 'frontend-typecheck' 'npm' @('--prefix','frontend','run','typecheck')
    Push-Location (Join-Path $root 'automation')
    try{Run-Test 'automation-typecheck' 'npx' @('tsc','--noEmit','-p','tsconfig.json')}finally{Pop-Location}
    foreach($suite in @('test:payment-evidence','test:acceptance-coverage','test:verification-polling','test:callbacks','test:callbacks:browser','test:provider-challenges:browser')){
        $suiteId=$suite.Replace(':','-')
        Run-Test $suiteId 'npm' @('--prefix','automation','run',$suite)
        Write-AutomationTestResults $suiteId (Join-Path $artifact "$suiteId.log") $results[-1].exitCode
    }
    Run-Test 'messaging-probe-build' 'dotnet' @('build','tools/Phase10.NfrProbe','--verbosity','quiet')
    $runnerCompleted=$true
}finally{
    Pop-Location
    @{results=$results;status=$(if(-not $runnerCompleted -or @($results|Where-Object status -eq 'failed').Count){'failed'}else{'passed'})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $artifact 'summary.json')
}
if(@($results|Where-Object status -eq 'failed').Count){exit 1}
