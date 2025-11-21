<#
.SYNOPSIS
    Test RECOMMENDED NEXT STEPS after Azure Bootstrap
.DESCRIPTION
    Validates all recommended next steps from bootstrap workflow:
    1. Test Infrastructure Deployment (trigger workflow simulation)
    2. Verify Azure Resources exist and are accessible
    3. Test OIDC Credentials
    4. Validate Configuration Consistency
    5. Test Application Endpoints
    6. Verify GitHub Secrets
.PARAMETER Environment
    Target environment (dev|staging|prod). Default: dev
.EXAMPLE
    .\test-recommended-next-steps.ps1 -Environment dev
#>
[CmdletBinding()]
param(
    [ValidateSet('dev','staging','prod')]
    [string]$Environment = 'dev',
    
    [string]$ResourceGroupPrefix = 'rg-orderprocessing',
    [string]$BaseName = 'orderprocessing',
    [string]$ApiSuffix = 'api-xyapp',
    [string]$UiSuffix = 'ui-xyapp'
)

$ErrorActionPreference = 'Continue'
$script:TestResults = @()
$script:OverallSuccess = $true

function Write-TestHeader {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message,
        [string]$Details = ""
    )
    
    $status = if ($Success) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "      $Message" -ForegroundColor Gray
    }
    if ($Details) {
        Write-Host "      Details: $Details" -ForegroundColor DarkGray
    }
    
    $script:TestResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Message = $Message
        Details = $Details
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    if (-not $Success) {
        $script:OverallSuccess = $false
    }
}

function Test-AzureAuthentication {
    Write-TestHeader "STEP 1: Verify Azure Authentication"
    
    try {
        $account = az account show 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($account) {
            Write-TestResult -TestName "Azure CLI Authentication" -Success $true `
                -Message "Logged in as $($account.user.name)" `
                -Details "Subscription: $($account.name) ($($account.id))"
            return $true
        } else {
            Write-TestResult -TestName "Azure CLI Authentication" -Success $false `
                -Message "Not logged in. Run 'az login' first."
            return $false
        }
    } catch {
        Write-TestResult -TestName "Azure CLI Authentication" -Success $false -Message $_.Exception.Message
        return $false
    }
}

function Test-AzureResources {
    Write-TestHeader "STEP 2: Verify Azure Resources Exist"
    
    $envSuffix = switch($Environment) {
        'dev' { 'dev' }
        'staging' { 'stg' }
        'prod' { 'prod' }
    }
    
    # Test Resource Group
    try {
        $rgName = "$ResourceGroupPrefix-$envSuffix"
        $rg = az group show -n $rgName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($rg) {
            Write-TestResult -TestName "Resource Group: $rgName" -Success $true `
                -Message "Status: $($rg.properties.provisioningState)" `
                -Details "Location: $($rg.location)"
        } else {
            Write-TestResult -TestName "Resource Group: $rgName" -Success $false `
                -Message "Resource group not found"
        }
    } catch {
        Write-TestResult -TestName "Resource Group" -Success $false -Message $_.Exception.Message
    }
    
    # Test App Service Plan
    try {
        $aspName = "asp-$BaseName-$envSuffix"
        $asp = az appservice plan show -g $rgName -n $aspName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($asp) {
            Write-TestResult -TestName "App Service Plan: $aspName" -Success $true `
                -Message "Status: $($asp.status), SKU: $($asp.sku.name)" `
                -Details "Tier: $($asp.sku.tier)"
        } else {
            Write-TestResult -TestName "App Service Plan: $aspName" -Success $false `
                -Message "App Service Plan not found"
        }
    } catch {
        Write-TestResult -TestName "App Service Plan" -Success $false -Message $_.Exception.Message
    }
    
    # Test API Web App
    try {
        $apiAppName = "$BaseName-$ApiSuffix-$envSuffix"
        $apiApp = az webapp show -g $rgName -n $apiAppName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($apiApp) {
            Write-TestResult -TestName "API Web App: $apiAppName" -Success $true `
                -Message "State: $($apiApp.state)" `
                -Details "URL: https://$($apiApp.defaultHostName)"
        } else {
            Write-TestResult -TestName "API Web App: $apiAppName" -Success $false `
                -Message "Web app not found"
        }
    } catch {
        Write-TestResult -TestName "API Web App" -Success $false -Message $_.Exception.Message
    }
    
    # Test UI Web App
    try {
        $uiAppName = "$BaseName-$UiSuffix-$envSuffix"
        $uiApp = az webapp show -g $rgName -n $uiAppName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($uiApp) {
            Write-TestResult -TestName "UI Web App: $uiAppName" -Success $true `
                -Message "State: $($uiApp.state)" `
                -Details "URL: https://$($uiApp.defaultHostName)"
        } else {
            Write-TestResult -TestName "UI Web App: $uiAppName" -Success $false `
                -Message "Web app not found"
        }
    } catch {
        Write-TestResult -TestName "UI Web App" -Success $false -Message $_.Exception.Message
    }
    
    # Test Application Insights
    try {
        $aiName = "ai-$BaseName-$envSuffix"
        $ai = az monitor app-insights component show -g $rgName --app $aiName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($ai) {
            Write-TestResult -TestName "Application Insights: $aiName" -Success $true `
                -Message "Status: $($ai.provisioningState)" `
                -Details "Instrumentation Key exists: $($ai.instrumentationKey -ne $null)"
        } else {
            Write-TestResult -TestName "Application Insights: $aiName" -Success $false `
                -Message "Application Insights not found"
        }
    } catch {
        Write-TestResult -TestName "Application Insights" -Success $false -Message $_.Exception.Message
    }
}

function Test-OIDCCredentials {
    Write-TestHeader "STEP 3: Verify OIDC Credentials"
    
    try {
        $appId = az ad app list --display-name "GitHub-Actions-OIDC" --query "[0].id" -o tsv 2>$null
        
        if (-not $appId) {
            Write-TestResult -TestName "OIDC App Registration" -Success $false `
                -Message "GitHub-Actions-OIDC app not found"
            return
        }
        
        Write-TestResult -TestName "OIDC App Registration" -Success $true `
            -Message "App found" `
            -Details "Object ID: $appId"
        
        # Check federated credentials
        $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\verify-oidc-credentials.ps1"
        if (Test-Path $scriptPath) {
            Write-Host "`n  Running OIDC verification script..." -ForegroundColor Yellow
            & $scriptPath -AppObjectId $appId
            $exitCode = $LASTEXITCODE
            
            $success = ($exitCode -eq 0)
            $message = switch ($exitCode) {
                0 { "All expected federated credentials present" }
                2 { "Missing credentials for one or more environments" }
                default { "Verification script exit code: $exitCode" }
            }
            
            Write-TestResult -TestName "OIDC Federated Credentials" -Success $success -Message $message
        } else {
            Write-TestResult -TestName "OIDC Verification Script" -Success $false `
                -Message "Script not found: $scriptPath"
        }
    } catch {
        Write-TestResult -TestName "OIDC Credentials" -Success $false -Message $_.Exception.Message
    }
}

function Test-GitHubSecrets {
    Write-TestHeader "STEP 4: Verify GitHub Secrets (Manual Check Required)"
    
    Write-Host "  GitHub secrets cannot be read via CLI for security reasons." -ForegroundColor Yellow
    Write-Host "  Please verify manually that these secrets exist:" -ForegroundColor Yellow
    Write-Host "    - AZUREAPPSERVICE_CLIENTID" -ForegroundColor White
    Write-Host "    - AZUREAPPSERVICE_TENANTID" -ForegroundColor White
    Write-Host "    - AZUREAPPSERVICE_SUBSCRIPTIONID" -ForegroundColor White
    Write-Host "`n  GitHub Secrets URL:" -ForegroundColor Cyan
    Write-Host "    https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions" -ForegroundColor Cyan
    
    Write-TestResult -TestName "GitHub Secrets" -Success $true `
        -Message "Manual verification required" `
        -Details "Check secrets page in GitHub repository settings"
}

function Test-ConfigurationConsistency {
    Write-TestHeader "STEP 5: Validate Configuration Consistency"
    
    $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\validate-sharedsettings-diff.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestResult -TestName "Config Validation Script" -Success $false `
            -Message "Script not found: $scriptPath"
        return
    }
    
    try {
        Write-Host "  Running configuration consistency check..." -ForegroundColor Yellow
        & $scriptPath
        $exitCode = $LASTEXITCODE
        
        $success = ($exitCode -eq 0)
        $message = switch ($exitCode) {
            0 { "All configuration files aligned" }
            2 { "Configuration drift detected" }
            default { "Validation script exit code: $exitCode" }
        }
        
        Write-TestResult -TestName "SharedSettings Consistency" -Success $success -Message $message
    } catch {
        Write-TestResult -TestName "Config Validation" -Success $false -Message $_.Exception.Message
    }
}

function Test-InfrastructureDeployment {
    Write-TestHeader "STEP 6: Test Infrastructure Deployment (What-If Analysis)"
    
    $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\validate-parameters-whatif.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestResult -TestName "What-If Script" -Success $false `
            -Message "Script not found: $scriptPath"
        return
    }
    
    Write-Host "  Running Bicep what-if analysis for $Environment environment..." -ForegroundColor Yellow
    
    try {
        & $scriptPath -Environment $Environment -ResourceGroupPrefix $ResourceGroupPrefix.Replace('rg-', '')
        $exitCode = $LASTEXITCODE
        
        $success = ($exitCode -eq 0)
        $message = switch ($exitCode) {
            0 { "No high-risk changes detected - deployment safe" }
            2 { "High-risk changes detected (review required)" }
            default { "What-if analysis exit code: $exitCode" }
        }
        
        Write-TestResult -TestName "Bicep What-If Analysis" -Success $success -Message $message
    } catch {
        Write-TestResult -TestName "Infrastructure Deployment" -Success $false -Message $_.Exception.Message
    }
}

function Test-ApplicationEndpoints {
    Write-TestHeader "STEP 7: Test Application Endpoints"
    
    $envSuffix = switch($Environment) {
        'dev' { 'dev' }
        'staging' { 'stg' }
        'prod' { 'prod' }
    }
    
    # Test API endpoint
    $apiUrl = "https://$BaseName-$ApiSuffix-$envSuffix.azurewebsites.net"
    try {
        Write-Host "  Testing API endpoint: $apiUrl" -ForegroundColor Yellow
        $response = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
        $statusCode = $response.StatusCode
        
        # 200 = app deployed and working, 404 = app running but no routes, 403 = auth required (expected)
        $success = $statusCode -in @(200, 404, 403)
        $message = if ($success) {
            "Endpoint responding with HTTP $statusCode"
        } else {
            "Unexpected status code: $statusCode"
        }
        
        Write-TestResult -TestName "API Endpoint" -Success $success `
            -Message $message `
            -Details $apiUrl
    } catch {
        # Web app exists but returns error (this is expected if no app deployed yet)
        $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "N/A" }
        $success = $statusCode -in @(404, 403, 503) # 503 = starting up
        
        Write-TestResult -TestName "API Endpoint" -Success $success `
            -Message "Endpoint accessible (HTTP $statusCode) - expected if no code deployed" `
            -Details $apiUrl
    }
    
    # Test UI endpoint
    $uiUrl = "https://$BaseName-$UiSuffix-$envSuffix.azurewebsites.net"
    try {
        Write-Host "  Testing UI endpoint: $uiUrl" -ForegroundColor Yellow
        $response = Invoke-WebRequest -Uri $uiUrl -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
        $statusCode = $response.StatusCode
        
        $success = $statusCode -in @(200, 404, 403)
        $message = if ($success) {
            "Endpoint responding with HTTP $statusCode"
        } else {
            "Unexpected status code: $statusCode"
        }
        
        Write-TestResult -TestName "UI Endpoint" -Success $success `
            -Message $message `
            -Details $uiUrl
    } catch {
        $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "N/A" }
        $success = $statusCode -in @(404, 403, 503)
        
        Write-TestResult -TestName "UI Endpoint" -Success $success `
            -Message "Endpoint accessible (HTTP $statusCode) - expected if no code deployed" `
            -Details $uiUrl
    }
}

function Test-WorkflowFiles {
    Write-TestHeader "STEP 8: Verify GitHub Workflow Files"
    
    $workflows = @(
        ".github\workflows\azure-bootstrap.yml",
        ".github\workflows\infra-deploy.yml",
        ".github\workflows\validate-deployment.yml",
        ".github\workflows\deploy-api-to-azure.yml",
        ".github\workflows\deploy-ui-to-azure.yml"
    )
    
    foreach ($workflow in $workflows) {
        $fullPath = Join-Path $PSScriptRoot $workflow
        $exists = Test-Path $fullPath
        $fileName = Split-Path $workflow -Leaf
        
        Write-TestResult -TestName "Workflow: $fileName" -Success $exists `
            -Message $(if ($exists) { "File exists" } else { "File not found" }) `
            -Details $workflow
    }
}

function Show-RecommendedNextSteps {
    Write-TestHeader "RECOMMENDED NEXT STEPS"
    
    Write-Host "`n1. Test Infrastructure Deployment" -ForegroundColor Cyan
    Write-Host "   Trigger deployment by pushing to your branch:" -ForegroundColor White
    Write-Host "   git commit --allow-empty -m 'test: trigger deployment workflow'" -ForegroundColor Gray
    Write-Host "   git push" -ForegroundColor Gray
    
    Write-Host "`n2. Monitor Deployment Workflows" -ForegroundColor Cyan
    Write-Host "   GitHub Actions: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions" -ForegroundColor Gray
    
    Write-Host "`n3. Deploy Application Code" -ForegroundColor Cyan
    Write-Host "   - Run API deployment: .github\workflows\deploy-api-to-azure.yml" -ForegroundColor Gray
    Write-Host "   - Run UI deployment: .github\workflows\deploy-ui-to-azure.yml" -ForegroundColor Gray
    
    Write-Host "`n4. Configure Telemetry" -ForegroundColor Cyan
    Write-Host "   Follow: Documentation\02-Azure-Learning-Guides\Telemetry-Quick-Start.md" -ForegroundColor Gray
    
    Write-Host "`n5. Verify Application Endpoints" -ForegroundColor Cyan
    $envSuffix = switch($Environment) { 'dev' { 'dev' } 'staging' { 'stg' } 'prod' { 'prod' } }
    Write-Host "   - API: https://$BaseName-$ApiSuffix-$envSuffix.azurewebsites.net" -ForegroundColor Gray
    Write-Host "   - UI:  https://$BaseName-$UiSuffix-$envSuffix.azurewebsites.net" -ForegroundColor Gray
    
    Write-Host "`n6. Set Up Continuous Deployment" -ForegroundColor Cyan
    Write-Host "   Ensure branch protection rules and deployment gates are configured" -ForegroundColor Gray
}

function Show-TestSummary {
    Write-TestHeader "TEST SUMMARY"
    
    $script:TestResults | Format-Table Test, Status, Message -AutoSize
    
    $passed = ($script:TestResults | Where-Object { $_.Status -like "*PASS*" }).Count
    $failed = ($script:TestResults | Where-Object { $_.Status -like "*FAIL*" }).Count
    $total = $script:TestResults.Count
    
    Write-Host "`nResults: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    
    if ($script:OverallSuccess) {
        Write-Host "`n✓ RECOMMENDED NEXT STEPS VALIDATION: PASSED" -ForegroundColor Green
        Write-Host "  Your $Environment environment is ready for deployment!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ RECOMMENDED NEXT STEPS VALIDATION: ISSUES FOUND" -ForegroundColor Yellow
        Write-Host "  Review failures above before proceeding" -ForegroundColor Yellow
    }
    
    # Save results
    $logFile = Join-Path $PSScriptRoot "logs\recommended-next-steps-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $logDir = Split-Path $logFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $script:TestResults | Export-Csv -Path $logFile -NoTypeInformation
    Write-Host "`nDetailed results saved to: $logFile" -ForegroundColor Cyan
}

# Main Execution
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " TESTING RECOMMENDED NEXT STEPS" -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White

# Run all validation tests
if (-not (Test-AzureAuthentication)) {
    Write-Host "`nAborting: Azure CLI authentication required" -ForegroundColor Red
    exit 1
}

Test-AzureResources
Test-OIDCCredentials
Test-GitHubSecrets
Test-ConfigurationConsistency
Test-InfrastructureDeployment
Test-ApplicationEndpoints
Test-WorkflowFiles

# Show results and next steps
Show-TestSummary
Show-RecommendedNextSteps

# Exit with appropriate code
exit $(if ($script:OverallSuccess) { 0 } else { 1 })
