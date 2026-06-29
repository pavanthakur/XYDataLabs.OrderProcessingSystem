param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('9.1', '9.2', '9.3', '9.4', '9.5', '9.6', '9.7', '9.8', '9.9', '9.10', '9.11', '9.12', '9.13', '9.14', '9.15', '9.16', '9.17', '9.18', '9.19', '9.20', '9.21', '9.22', '9.23', '9.24', '9.25', '9.26', '9.27', '9.28', '9.29', '9.30', '9.31', '9.32', '9.33', '9.34')]
    [string]$Slice = '9.18',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3)]
    [int]$MaxRetries = 3
)

$steps = @('architect', 'developer', 'review', 'automation')
$runner = Join-Path $PSScriptRoot 'run-phase9.ps1'
if (-not (Test-Path $runner)) {
    throw "Phase runner not found: $runner"
}

function Write-PhaseLog {
    param(
        [string]$Message,
        [string]$Path
    )
    $timestamp = (Get-Date).ToString('s')
    Add-Content -LiteralPath $Path -Value "[$timestamp] $Message"
}

function Test-StepArtifact {
    param(
        [string]$ArtifactPath,
        [string]$StepName
    )

    if (-not (Test-Path $ArtifactPath)) {
        throw "$StepName artifact not found: $ArtifactPath"
    }

    $text = Get-Content -Raw $ArtifactPath
    $badPatterns = @(
        'exceeds the 32,768 token limit',
        'Generated context for',
        'too large',
        'Connection refused',
        'ERR_CONNECTION_REFUSED',
        'Failed to retrieve content from',
        'Unexpected token',
        'Missing expression after unary operator',
        'An empty pipe element is not allowed',
        '\.py',
        'Python',
        'flake8',
        'def handle_',
        'def main(',
        'order_service.py',
        'inventory_service.py',
        'notification_service.py',
        'event_flow.py',
        'events.py'
    )

    foreach ($pattern in $badPatterns) {
        if ($text -match [regex]::Escape($pattern)) {
            throw "$StepName artifact failed guardrail check: $pattern"
        }
    }

    if ($StepName -eq 'developer') {
        $developerBadPatterns = @(
            'using MediatR;',
            'IRequestHandler<',
            'IRepository<',
            'MockRepository<',
            'IOrdersRepository',
            'AddAsync(',
            'UpdateAsync(',
            'GetByIdAsync(',
            'DeleteAsync(',
            'CreateOrderHandler',
            'UpdateOrderHandler',
            'GetOrderByIdHandler',
            'import ',
            'class ',
            'def ',
            'event_flow.py',
            'events.py',
            'order_service.py',
            'inventory_service.py',
            'notification_service.py'
        )

        foreach ($pattern in $developerBadPatterns) {
            if ($text -match [regex]::Escape($pattern)) {
                throw "developer artifact drifted into disallowed implementation pattern: $pattern"
            }
        }
    }
}

function Get-GitChangedFiles {
    param([string]$RepoRoot)

    $tracked = & git -C $RepoRoot diff --name-only --diff-filter=ACMRTUXB
    $untracked = & git -C $RepoRoot ls-files --others --exclude-standard

    @($tracked + $untracked) | Where-Object { $_ } | Sort-Object -Unique
}

function Test-ContainsProductCodeChange {
    param(
        [string[]]$BaselineFiles,
        [string]$RepoRoot
    )

    $currentFiles = Get-GitChangedFiles -RepoRoot $RepoRoot
    $newFiles = $currentFiles | Where-Object { $_ -notin $BaselineFiles }

    $productPatterns = @(
        '^XYDataLabs\.OrderProcessingSystem\..*\.(cs|csproj|json|props|targets|razor|tsx?|jsx?|sql|xml)$',
        '^XYDataLabs\..*\.(cs|csproj|json|props|targets|razor|tsx?|jsx?|sql|xml)$'
    )

    $productFiles = foreach ($file in $newFiles) {
        $isTest = $file -match '(^|[\\/])tests([\\/]|$)' -or $file -match '\.Tests([\\/]|$)'
        $isTooling = $file -match '(^|[\\/])local models([\\/]|$)' -or $file -match '(^|[\\/])\.github([\\/]|$)' -or $file -match '(^|[\\/])docs([\\/]|$)' -or $file -match '(^|[\\/])scripts([\\/]|$)'
        $matchesProduct = $false
        foreach ($pattern in $productPatterns) {
            if ($file -match $pattern) {
                $matchesProduct = $true
                break
            }
        }

        if (-not $isTest -and -not $isTooling -and $matchesProduct) {
            $file
        }
    }

    [pscustomobject]@{
        NewFiles = $newFiles
        ProductFiles = @($productFiles)
    }
}

function Get-FileHashText {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-ExpectedDeveloperTargets {
    param([string]$Slice, [string]$RepoRoot)

    switch ($Slice) {
        '9.3' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs')) }
        '9.4' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ProcessPaymentCommand.cs')) }
        '9.5' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Domain\Entities\Tenant.cs')) }
        '9.6' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Gateway\Program.cs')) }
        '9.7' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\README.md')) }
        '9.8' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Inventory\Queries\GetInventoryStatusQuery.cs')) }
        '9.9' { @((Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Notifications\Events\NotificationRequestedV1.cs')) }
        '9.10' { @((Join-Path $RepoRoot 'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\Phase9CloseoutTests.cs')) }
        '9.11' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.11\architect.md')) }
        '9.12' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.12\architect.md')) }
        '9.13' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.13\architect.md')) }
        '9.14' { @(
            (Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs'),
            (Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Inventory\Queries\GetInventoryStatusQuery.cs'),
            (Join-Path $RepoRoot 'XYDataLabs.OrderProcessingSystem.Application\Features\Notifications\Events\NotificationRequestedV1.cs')
        ) }
        '9.15' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.15\architect.md')) }
        '9.16' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.16\architect.md')) }
        '9.17' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.17\architect.md')) }
        '9.18' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.18\architect.md')) }
        '9.19' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.19\architect.md')) }
        '9.20' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.20\architect.md')) }
        '9.21' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.21\architect.md')) }
        '9.22' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.22\architect.md')) }
        '9.23' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.23\architect.md')) }
        '9.24' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.24\architect.md')) }
        '9.25' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.25\architect.md')) }
        '9.26' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.26\architect.md')) }
        '9.27' { @((Join-Path $RepoRoot 'local models\zoocode\phase9\9.27\architect.md')) }
        default { @() }
    }
}

for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    $logFile = Join-Path $PSScriptRoot "_temp\phase9-e2e-$Slice-attempt-$attempt.log"
    $latestLog = Join-Path $PSScriptRoot "_temp\phase9-e2e.log"
    $null = New-Item -ItemType File -Path $logFile -Force
    $null = Copy-Item -LiteralPath $logFile -Destination $latestLog -Force

    Write-Host ""
    Write-Host "Phase $Slice end-to-end attempt $attempt of $MaxRetries"
    Write-PhaseLog -Path $logFile -Message "Attempt=$attempt of $MaxRetries Slice=$Slice Status=Started"

    $baselineFiles = Get-GitChangedFiles -RepoRoot $PSScriptRoot
    $ordersTarget = Join-Path (Split-Path -Parent $PSScriptRoot) 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs'
    $ordersHashBefore = $null
    if ($Slice -eq '9.3') {
        $ordersHashBefore = Get-FileHashText -Path $ordersTarget
    }

    $failed = $false
    foreach ($step in $steps) {
        Write-Host ""
        Write-Host "Running $step..."
        & $runner -Slice $Slice -Step $step
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Step $step failed with exit code $LASTEXITCODE."
            Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step ExitCode=$LASTEXITCODE Status=Failed"
            $failed = $true
            break
        }

        if ($step -eq 'developer' -and $Slice -eq '9.3') {
            $ordersHashAfter = Get-FileHashText -Path $ordersTarget
            if ($ordersHashBefore -and $ordersHashAfter -and $ordersHashBefore -eq $ordersHashAfter) {
                $message = "developer step did not change the Orders target file."
                Write-Host $message
                Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step Status=GuardrailFailed Message=$message"
                $failed = $true
                break
            }
        }

        if ($step -eq 'developer' -and $Slice -in @('9.4', '9.5', '9.6', '9.7', '9.8', '9.9', '9.10')) {
            $changeCheck = Test-ContainsProductCodeChange -BaselineFiles $baselineFiles -RepoRoot $PSScriptRoot
            $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
            $expectedTargets = Get-ExpectedDeveloperTargets -Slice $Slice -RepoRoot $repoRoot
            $expectedTargetsChanged = $false

            foreach ($target in $expectedTargets) {
                if (Test-Path $target) {
                    $text = Get-Content -Raw -LiteralPath $target
                    if (-not [string]::IsNullOrWhiteSpace($text)) {
                        $expectedTargetsChanged = $true
                        break
                    }
                }
            }

            if (-not $expectedTargetsChanged) {
                $message = "developer step did not produce the expected slice target file. New files: $($changeCheck.NewFiles -join ', ')"
                Write-Host $message
                Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step Status=GuardrailFailed Message=$message"
                $failed = $true
                break
            }
        }

        if ($step -eq 'developer' -and $Slice -eq '9.14') {
            $changeCheck = Test-ContainsProductCodeChange -BaselineFiles $baselineFiles -RepoRoot $PSScriptRoot
            $pythonLeak = $changeCheck.NewFiles | Where-Object {
                $_ -match '(^|[\\/])(.*\.py|event_flow\.py|events\.py|order_service\.py|inventory_service\.py|notification_service\.py)$'
            }

            if ($pythonLeak) {
                $message = "developer step generated disallowed Python files: $($pythonLeak -join ', ')"
                Write-Host $message
                Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step Status=GuardrailFailed Message=$message"
                $failed = $true
                break
            }

            $expectedTargets = Get-ExpectedDeveloperTargets -Slice $Slice -RepoRoot (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
            $expectedTargetsChanged = $false
            foreach ($target in $expectedTargets) {
                if (Test-Path $target) {
                    $text = Get-Content -Raw -LiteralPath $target
                    if (-not [string]::IsNullOrWhiteSpace($text)) {
                        $expectedTargetsChanged = $true
                        break
                    }
                }
            }

            if (-not $expectedTargetsChanged) {
                $message = "developer step did not produce the expected C# event-flow target file."
                Write-Host $message
                Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step Status=GuardrailFailed Message=$message"
                $failed = $true
                break
            }
        }

        $artifact = Join-Path $PSScriptRoot "_temp\$Slice-$step.md"
        try {
            Test-StepArtifact -ArtifactPath $artifact -StepName $step
        }
        catch {
            Write-Host $_.Exception.Message
            Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Step=$step Status=GuardrailFailed Message=$($_.Exception.Message)"
            $failed = $true
            break
        }
    }

    if (-not $failed) {
        Write-Host ""
        Write-Host "Phase $Slice end-to-end completed successfully."
        Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Slice=$Slice Status=Succeeded"
        exit 0
    }

    if ($attempt -lt $MaxRetries) {
        Write-Host ""
        Write-Host "Retrying the full $Slice chain after guardrail failure."
        Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Slice=$Slice Status=Retrying"
        continue
    }

    Write-PhaseLog -Path $logFile -Message "Attempt=$attempt Slice=$Slice Status=FailedAfterRetries"
    throw "Phase $Slice end-to-end failed after $MaxRetries attempts."
}
