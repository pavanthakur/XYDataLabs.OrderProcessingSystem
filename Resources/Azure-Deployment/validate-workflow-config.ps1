# Workflow Configuration Validator
# Run this before committing workflow changes to catch configuration errors

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkflowFile = ".github/workflows/azure-bootstrap.yml"
)

$ErrorCount = 0

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Workflow Configuration Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $WorkflowFile)) {
    Write-Host "ERROR: Workflow file not found: $WorkflowFile" -ForegroundColor Red
    exit 1
}

$content = Get-Content $WorkflowFile -Raw

Write-Host "Validating: $WorkflowFile" -ForegroundColor Yellow
Write-Host ""

# Test 1: Verify bootstrap-dev has correct environment
Write-Host "Test 1: Bootstrap-dev configuration" -ForegroundColor Cyan
if ($content -match '(?s)bootstrap-dev:.*?name: Bootstrap Dev Infrastructure.*?-Environment dev') {
    Write-Host "  PASS: Script call: -Environment dev" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG script call in bootstrap-dev job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-dev:.*?Write-Host "  Branch: dev"') {
    Write-Host "  PASS: Logging: Branch: dev" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG branch logging in bootstrap-dev job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-dev:.*?Write-Host "  Environment: dev"') {
    Write-Host "  PASS: Logging: Environment: dev" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG environment logging in bootstrap-dev job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-dev:.*?infra/parameters/dev\.json') {
    Write-Host "  PASS: Logging: dev.json" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG parameter file in bootstrap-dev job" -ForegroundColor Red
    $ErrorCount++
}

Write-Host ""

# Test 2: Verify bootstrap-staging has correct environment
Write-Host "Test 2: Bootstrap-staging configuration" -ForegroundColor Cyan
if ($content -match '(?s)bootstrap-staging:.*?name: Bootstrap Staging Infrastructure.*?-Environment staging') {
    Write-Host "  PASS: Script call: -Environment staging" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG script call in bootstrap-staging job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-staging:.*?Write-Host "  Branch: staging"') {
    Write-Host "  PASS: Logging: Branch: staging" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG branch logging in bootstrap-staging job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-staging:.*?Write-Host "  Environment: staging"') {
    Write-Host "  PASS: Logging: Environment: staging" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG environment logging in bootstrap-staging job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-staging:.*?infra/parameters/staging\.json') {
    Write-Host "  PASS: Logging: staging.json" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG parameter file in bootstrap-staging job" -ForegroundColor Red
    $ErrorCount++
}

Write-Host ""

# Test 3: Verify bootstrap-prod has correct environment
Write-Host "Test 3: Bootstrap-prod configuration" -ForegroundColor Cyan
if ($content -match '(?s)bootstrap-prod:.*?name: Bootstrap Prod Infrastructure.*?-Environment prod') {
    Write-Host "  PASS: Script call: -Environment prod" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG script call in bootstrap-prod job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-prod:.*?Write-Host "  Branch: main"') {
    Write-Host "  PASS: Logging: Branch: main" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG branch logging in bootstrap-prod job (should be 'main' not 'prod')" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-prod:.*?Write-Host "  Environment: prod"') {
    Write-Host "  PASS: Logging: Environment: prod" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG environment logging in bootstrap-prod job" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)bootstrap-prod:.*?infra/parameters/prod\.json') {
    Write-Host "  PASS: Logging: prod.json" -ForegroundColor Green
} else {
    Write-Host "  FAIL: WRONG parameter file in bootstrap-prod job" -ForegroundColor Red
    $ErrorCount++
}

Write-Host ""

# Test 4: Verify OIDC setup uses inputs.environment
Write-Host "Test 4: OIDC setup dynamic configuration" -ForegroundColor Cyan
if ($content -match '\$selectedEnv = "\$\{\{ inputs\.environment \}\}"') {
    Write-Host "  PASS: OIDC setup uses inputs.environment" -ForegroundColor Green
} else {
    Write-Host "  FAIL: OIDC setup not using inputs.environment" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match 'if \(\$selectedEnv -eq "all"\) \{') {
    Write-Host "  PASS: OIDC has conditional logic for 'all' environment" -ForegroundColor Green
} else {
    Write-Host "  FAIL: OIDC missing conditional for 'all' environment" -ForegroundColor Red
    $ErrorCount++
}

Write-Host ""

# Test 5: Verify configure-secrets uses inputs.environment
Write-Host "Test 5: Configure-secrets dynamic configuration" -ForegroundColor Cyan
if ($content -match '(?s)configure-secrets:.*?\$selectedEnv = "\$\{\{ inputs\.environment \}\}"') {
    Write-Host "  PASS: Configure-secrets uses inputs.environment" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Configure-secrets not using inputs.environment" -ForegroundColor Red
    $ErrorCount++
}

if ($content -match '(?s)configure-secrets:.*?\$envList = if \(\$selectedEnv -eq "all"\)') {
    Write-Host "  PASS: Configure-secrets handles 'all' environment" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Configure-secrets missing 'all' environment handling" -ForegroundColor Red
    $ErrorCount++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($ErrorCount -eq 0) {
    Write-Host "SUCCESS: All configuration checks passed" -ForegroundColor Green
    Write-Host "Safe to commit workflow changes" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILED: Found $ErrorCount configuration error(s)" -ForegroundColor Red
    Write-Host "DO NOT COMMIT - Fix errors before committing" -ForegroundColor Red
    exit 1
}
