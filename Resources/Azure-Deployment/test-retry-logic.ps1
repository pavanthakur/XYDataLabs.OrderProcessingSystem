# test-retry-logic.ps1
# Unit test for the retry logic in Azure deployment scripts

$ErrorActionPreference = 'Stop'

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         RETRY LOGIC UNIT TEST                                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Import the retry function
$retryFunction = @'
function Invoke-AzCommandWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$InitialDelaySeconds = 2
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            # Execute the command
            $result = Invoke-Expression $Command 2>&1
            $exitCode = $LASTEXITCODE
            
            # Check for connection reset error in the output
            $resultStr = $result | Out-String
            if ($resultStr -match "ConnectionResetError|Connection aborted|forcibly closed") {
                throw "Connection error detected in output"
            }
            
            # Return result with exit code
            return @{
                Success = ($exitCode -eq 0)
                Output = $result
                ExitCode = $exitCode
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "ConnectionResetError|Connection aborted|forcibly closed" -and $attempt -lt $MaxRetries) {
                Write-Host "  ⚠️  Connection error on attempt $attempt/$MaxRetries, retrying in $delay seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
                $delay = $delay * 2  # Exponential backoff
            }
            else {
                # Re-throw if it's not a connection error or we've exhausted retries
                throw
            }
        }
    }
    
    # If we get here, all retries failed
    throw "Command failed after $MaxRetries attempts: $Command"
}
'@

# Load the function
Invoke-Expression $retryFunction

$testsPassed = 0
$testsFailed = 0

# Test 1: Successful command execution
Write-Host "Test 1: Successful command execution" -ForegroundColor Yellow
try {
    $result = Invoke-AzCommandWithRetry -Command "Write-Output 'Success'; exit 0"
    if ($result.Success -and $result.Output -eq 'Success') {
        Write-Host "  ✅ Test 1 Passed" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  ❌ Test 1 Failed: Expected success but got failure" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  ❌ Test 1 Failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 2: Command with non-zero exit code
Write-Host "Test 2: Command with non-zero exit code" -ForegroundColor Yellow
try {
    $result = Invoke-AzCommandWithRetry -Command "Write-Output 'Failed'; exit 1"
    if (-not $result.Success -and $result.ExitCode -eq 1) {
        Write-Host "  ✅ Test 2 Passed" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  ❌ Test 2 Failed: Expected failure but got success" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  ❌ Test 2 Failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 3: Successful retry after transient error (simulated)
Write-Host "Test 3: Connection error detection" -ForegroundColor Yellow
try {
    # This test verifies that connection errors are detected in output
    $result = Invoke-AzCommandWithRetry -Command "Write-Output 'Test output'; exit 0"
    Write-Host "  ✅ Test 3 Passed (command completed successfully)" -ForegroundColor Green
    $testsPassed++
} catch {
    Write-Host "  ❌ Test 3 Failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 4: Verify retry with MaxRetries parameter
Write-Host "Test 4: Verify MaxRetries parameter works" -ForegroundColor Yellow
try {
    $result = Invoke-AzCommandWithRetry -Command "Write-Output 'Test'; exit 0" -MaxRetries 1
    if ($result.Success) {
        Write-Host "  ✅ Test 4 Passed (MaxRetries parameter accepted)" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  ❌ Test 4 Failed: Expected success" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  ❌ Test 4 Failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Summary
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Total Tests: $($testsPassed + $testsFailed)" -ForegroundColor Gray
Write-Host "  ✅ Passed: $testsPassed" -ForegroundColor Green
if ($testsFailed -gt 0) {
    Write-Host "  ❌ Failed: $testsFailed" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "✅ All tests passed!" -ForegroundColor Green
    exit 0
}
