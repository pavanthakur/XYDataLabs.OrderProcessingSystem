param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('9.1','9.2','9.3','9.4','9.5','9.6','9.7','9.8','9.9','9.10','9.11','9.12','9.13','9.14','9.15','9.16','9.17','9.18','9.19','9.20','9.21','9.22','9.23','9.24','9.25','9.26','9.27','9.28','9.29','9.30','9.31','9.32','9.33','9.34','9.35','9.36','9.37','9.38','9.39','9.40','9.41')]
    [string]$Slice,

    [Parameter(Mandatory = $true)]
    [ValidateSet('architect','developer','review','automation')]
    [string]$Step
)

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$aider = 'C:\Users\Pavan\AppData\Local\Programs\Python\Python311\Scripts\aider.exe'
$tempDir = Join-Path $PSScriptRoot '_temp'
$logFile = Join-Path $tempDir 'phase9-e2e.log'

$env:AIDER_CHECK_UPDATE = 'false'
$env:AIDER_JUST_CHECK_UPDATE = 'false'
$env:AIDER_ANALYTICS_DISABLE = 'true'

if (-not (Test-Path $aider)) {
    throw "Aider executable not found at $aider"
}

$null = New-Item -ItemType Directory -Path $tempDir -Force

$sliceDir = Join-Path $PSScriptRoot $Slice
if (-not (Test-Path $sliceDir)) {
    throw "Phase slice folder not found: $sliceDir"
}

function Write-PhaseLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString('s')
    $line = "[$timestamp] $Message"
    $directory = Split-Path -Parent $logFile
    if (-not (Test-Path $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $stream = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.UTF8Encoding]::new($false))
        try {
            $writer.WriteLine($line)
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$mapTokens = switch ($Step) {
    'architect' { '1024' }
    default { '2048' }
}

$maxChatHistoryTokens = switch ($Step) {
    'architect' { '1024' }
    default { '2048' }
}

$artifact = switch ($Step) {
    'architect' { Join-Path $tempDir "$Slice-architect.md" }
    'developer' { Join-Path $tempDir "$Slice-developer.md" }
    'review' { Join-Path $tempDir "$Slice-review.md" }
    'automation' { Join-Path $tempDir "$Slice-automation.md" }
}

$contextBuilder = Join-Path $PSScriptRoot 'build-slice-context.ps1'
if (-not (Test-Path $contextBuilder)) {
    throw "Context builder not found: $contextBuilder"
}

$sharedContextBuilder = Join-Path $root 'local models\ai-guidelines\build-slice-context.ps1'
if (-not (Test-Path $sharedContextBuilder)) {
    throw "Shared context builder not found: $sharedContextBuilder"
}

$contextFile = & $sharedContextBuilder -PhasePackRoot $PSScriptRoot -Slice $Slice -Step $Step
if (-not (Test-Path $contextFile)) {
    throw "Generated context file not found: $contextFile"
}

$contextHeader = Get-Content -TotalCount 2 $contextFile
if ($contextHeader.Count -ge 2) {
    Write-Host "Context: $($contextHeader[1])"
    Write-PhaseLog "Slice=$Slice Step=$Step Context=$($contextHeader[1])"
}

$runArgs = @(
    '--model', 'ollama/qwen2.5-coder:7b',
    '--yes-always',
    '--no-restore-chat-history',
    '--no-git',
    '--no-auto-commits',
    '--no-dirty-commits',
    '--subtree-only',
    '--map-tokens', $mapTokens,
    '--max-chat-history-tokens', $maxChatHistoryTokens,
    '--encoding', 'utf-8',
    '--chat-history-file', (Join-Path $tempDir "$Slice-$Step.chat.history.md"),
    '--input-history-file', (Join-Path $tempDir "$Slice-$Step.input.history"),
    '--llm-history-file', (Join-Path $tempDir "$Slice-$Step.llm.history.md"),
    '--message-file', $contextFile,
    '--exit'
) 

if ($Step -eq 'developer') {
    if ($Slice -eq '9.3') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-orders-9.3.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.4') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ProcessPaymentCommand.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-payments-9.4.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.5') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Domain\Entities\Tenant.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-tenant-9.5.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.6') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Gateway\Program.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-gateway-9.6.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.7') {
        $targetFile = Join-Path $root 'local models\zoocode\phase9\README.md'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-closeout-9.7.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.8') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Inventory\Queries\GetInventoryStatusQuery.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-inventory-9.8.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.9') {
        $targetFile = Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Notifications\Events\NotificationRequestedV1.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-notifications-9.9.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.10') {
        $targetFile = Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\Phase9CloseoutTests.cs'
        $directWriter = Join-Path $PSScriptRoot 'direct-write-closeout-9.10.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -TargetFile $targetFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for $targetFile" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.11') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-contracts-9.11.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.11 contracts" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.12') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-inventory-9.12.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.12 Inventory files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.13') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-notifications-9.13.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.13 Notifications files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.15') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-compose-9.15.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.15 compose files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.16') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-aspire-9.16.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.16 Aspire-Lite files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.17') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-identity-9.17.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.17 identity portability files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.18') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-publicapi-9.18.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.18 API files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.19') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-registration-9.19.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.19 service registration files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.21') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-topology-9.21.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.21 topology files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.22') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-identity-9.22.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.22 identity files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    if ($Slice -eq '9.23') {
        $directWriter = Join-Path $PSScriptRoot 'direct-write-closeout-9.23.ps1'
        if (-not (Test-Path $directWriter)) {
            throw "Direct writer not found: $directWriter"
        }

        & $directWriter -RepoRoot $root
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
            exit $exitCode
        }

        $artifact = Join-Path $tempDir "$Slice-$Step.md"
        "Direct writer completed for Phase 9.23 closeout files" | Set-Content -LiteralPath $artifact
        Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=0 Artifact=$artifact"
        Write-Host ""
        Write-Host "Next step: Review `"$artifact`", then run review."
        Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=Review `"$artifact`", then run review."
        exit 0
    }

    $developerFiles = @(
        (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\ArchitectureTests.cs')
    )

    switch ($Slice) {
        '9.3' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommand.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Commands\CreateOrderCommandValidator.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Queries\GetOrderDetailsQuery.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Queries\GetOrderDetailsQueryHandler.cs')
            )
        }
        '9.4' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ProcessPaymentCommand.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ProcessPaymentCommandHandler.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ConfirmPaymentStatusCommand.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Commands\ConfirmPaymentStatusCommandHandler.cs')
            )
        }
        '9.5' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Domain\Entities\Tenant.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Infrastructure\Payments\TenantPaymentProviderConfigurationResolver.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\TenantPaymentProviderResolver.cs')
            )
        }
        '9.6' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Gateway\Program.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Gateway\appsettings.json')
            )
        }
        '9.7' {
            $developerFiles += @(
                (Join-Path $root 'local models\zoocode\phase9\README.md'),
                (Join-Path $root 'local models\zoocode\phase9\phase9-roadmap.md')
            )
        }
        '9.8' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.API\Controllers\ProductController.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Orders\Queries\GetOrderDetailsQuery.cs')
            )
        }
        '9.9' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.API\Controllers\InfoController.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Payments\Events\PaymentAttemptSucceededV1.cs')
            )
        }
        '9.10' {
            $developerFiles += @(
                (Join-Path $root 'local models\zoocode\phase9\README.md'),
                (Join-Path $root 'local models\zoocode\phase9\phase9-roadmap.md')
            )
        }
        '9.13' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Notifications\NotificationsModuleRegistration.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Application\Features\Notifications\API\NotificationContracts.cs'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\NotificationsBoundaryTests.cs')
            )
        }
        '9.14' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Domain\Events\OrderCreatedDomainEvent.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Domain\Events\InventoryReservedDomainEvent.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Domain\Events\NotificationRequestedDomainEvent.cs'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\Scenarios\ParallelEventDispatchIntegrationTests.cs')
            )
        }
        '9.15' {
            $developerFiles += @(
                (Join-Path $root 'compose\docker-compose.phase9.yml'),
                (Join-Path $root 'compose\docker-compose.override.phase9.yml'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\Scenarios\OrderProcessingScenarioTests.cs')
            )
        }
        '9.16' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.AppHost\Program.cs'),
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.AppHost\XYDataLabs.OrderProcessingSystem.AppHost.csproj'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\Infrastructure\IntegrationTestWebAppFactory.cs')
            )
        }
        '9.17' {
            $developerFiles += @(
                (Join-Path $root 'XYDataLabs.OrderProcessingSystem.Gateway\appsettings.json'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\Scenarios\TenantMiddlewareTests.cs'),
                (Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\Scenarios\TenantIsolationTests.cs')
            )
        }
    }

    foreach ($file in $developerFiles) {
        $runArgs += @('--file', $file)
    }
}

if (Test-Path $artifact) {
    Remove-Item -LiteralPath $artifact -Force
}

$output = & $aider @runArgs 2>&1
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($artifact, $output, $utf8NoBom)
Write-PhaseLog "Slice=$Slice Step=$Step ExitCode=$LASTEXITCODE Artifact=$artifact"
if ($LASTEXITCODE -ne 0) {
    Write-PhaseLog "Slice=$Slice Step=$Step Status=Failed"
    exit $LASTEXITCODE
}

$nextArtifact = switch ($Step) {
    'architect' { Join-Path $tempDir "$Slice-architect.md" }
    'developer' { Join-Path $tempDir "$Slice-developer.md" }
    'review' { Join-Path $tempDir "$Slice-review.md" }
    'automation' { $null }
}

$nextStep = switch ($Step) {
    'architect' { "Review `"$nextArtifact`", then run developer." }
    'developer' { "Review `"$nextArtifact`", then run review." }
    'review' { "If accepted, run automation." }
    'automation' { "Slice complete. Move to the next slice only if the output is stable." }
}

$achievementSummary = switch ($Step) {
    'architect' { "Architect handoff produced for $Slice; next step is developer." }
    'developer' { "Developer handoff produced for $Slice; next step is review." }
    'review' { "Review decision produced for $Slice; next step is automation if accepted." }
    'automation' { "Automation verdict produced for $Slice; slice closure is now recorded." }
}

$summaryArtifact = Join-Path $tempDir "$Slice-$Step.summary.md"
$summaryLines = @(
    "# Phase $Slice $Step Summary"
    ""
    "Status: Succeeded"
    "Achievement: $achievementSummary"
    "Next Step: $nextStep"
    "Artifact: $artifact"
)
[System.IO.File]::WriteAllLines($summaryArtifact, $summaryLines, $utf8NoBom)

Write-Host ""
Write-Host "Next step: $nextStep"
Write-Host "Achievement: $achievementSummary"
Write-Host "Summary artifact: $summaryArtifact"
Write-PhaseLog "Slice=$Slice Step=$Step Achievement=$achievementSummary"
Write-PhaseLog "Slice=$Slice Step=$Step SummaryArtifact=$summaryArtifact"
Write-PhaseLog "Slice=$Slice Step=$Step Status=Succeeded NextStep=$nextStep"

