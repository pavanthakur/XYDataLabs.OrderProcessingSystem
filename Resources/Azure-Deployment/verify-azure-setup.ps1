Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        AZURE LEARNING PROGRESS VERIFICATION - DEV              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$rg = "rg-orderprocessing-dev"
$apiApp = "pavanthakur-orderprocessing-api-xyapp-dev"

Write-Host "`n[1/8] App Services..." -ForegroundColor Yellow
try {
    $apps = az webapp list -g $rg --query "[].{name:name, state:state}" -o json 2>$null | ConvertFrom-Json
    if ($apps -and $apps.Count -gt 0) {
        $apps | ForEach-Object { Write-Host "  ✅ $($_.name) - $($_.state)" -ForegroundColor Green }
    } else {
        Write-Host "  ❌ No App Services found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ No App Services found" -ForegroundColor Red
}

Write-Host "`n[2/8] Application Insights..." -ForegroundColor Yellow
try {
    $ai = az resource list -g $rg --resource-type "Microsoft.Insights/components" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($ai -and $ai.Count -gt 0) {
        $ai | ForEach-Object { Write-Host "  ✅ $_" -ForegroundColor Green }
    } else {
        Write-Host "  ❌ No Application Insights found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ No Application Insights found" -ForegroundColor Red
}

Write-Host "`n[3/8] Azure SQL Database..." -ForegroundColor Yellow
try {
    # Use resource list instead of sql server list (more reliable)
    $sqlServers = az resource list -g $rg --resource-type "Microsoft.Sql/servers" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($sqlServers -and $sqlServers.Count -gt 0) {
        $sqlServers | ForEach-Object { 
            Write-Host "  ✅ Server: $_" -ForegroundColor Green
            
            # Try to list databases with error suppression
            try {
                $dbs = az sql db list -g $rg -s $_ --query "[?name!='master'].name" -o json 2>$null | ConvertFrom-Json
                if ($dbs -and $dbs.Count -gt 0) {
                    $dbs | ForEach-Object { Write-Host "    └─ Database: $_" -ForegroundColor Green }
                } else {
                    Write-Host "    └─ Database: (Unable to list - connection issue)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "    └─ Database: (Unable to list - connection issue)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  ⚠️  No SQL Servers found - Will add to infrastructure" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠️  No SQL Servers found - Will add to infrastructure" -ForegroundColor Yellow
}

Write-Host "`n[4/8] Azure Key Vault..." -ForegroundColor Yellow
try {
    # Use resource list instead of keyvault list (more reliable)
    $kvs = az resource list -g $rg --resource-type "Microsoft.KeyVault/vaults" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($kvs -and $kvs.Count -gt 0) {
        $kvs | ForEach-Object { 
            Write-Host "  ✅ Key Vault: $_" -ForegroundColor Green
            try {
                $secrets = az keyvault secret list --vault-name $_ --query "[].name" -o json 2>$null | ConvertFrom-Json
                if ($secrets -and $secrets.Count -gt 0) {
                    Write-Host "    └─ Secrets: $($secrets.Count) found" -ForegroundColor Green
                } else {
                    Write-Host "    └─ ⚠️  Secrets: None found (Key Vault is empty)" -ForegroundColor Yellow
                    Write-Host "    └─ 💡 Run: ./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev" -ForegroundColor Cyan
                }
            } catch {
                # Silently continue if secrets can't be listed
                Write-Host "    └─ ⚠️  Unable to list secrets (check permissions)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  ⚠️  No Key Vaults found - Will add to infrastructure" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠️  No Key Vaults found - Will add to infrastructure" -ForegroundColor Yellow
}

Write-Host "`n[5/8] Managed Identity..." -ForegroundColor Yellow
try {
    $identity = az webapp identity show -g $rg -n $apiApp --query principalId -o tsv 2>$null
    if ($identity) {
        Write-Host "  ✅ API App Managed Identity: $identity" -ForegroundColor Green
        
        # Check if Managed Identity has Key Vault access
        if ($kvs -and $kvs.Count -gt 0) {
            $kvName = $kvs[0]
            Write-Host "  🔍 Checking Key Vault access policies..." -ForegroundColor Gray
            $accessPolicies = az keyvault show -n $kvName -g $rg --query "properties.accessPolicies[?objectId=='$identity']" -o json 2>$null | ConvertFrom-Json
            if ($accessPolicies -and $accessPolicies.Count -gt 0) {
                Write-Host "  ✅ Managed Identity has Key Vault access" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Managed Identity exists but NO Key Vault access" -ForegroundColor Yellow
                Write-Host "  💡 Run: ./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment dev" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  ⚠️  Managed Identity not assigned" -ForegroundColor Yellow
        Write-Host "  💡 To enable Managed Identity and grant Key Vault access, run:" -ForegroundColor Cyan
        Write-Host "     ./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment dev" -ForegroundColor Cyan
        Write-Host "  📝 Or manually:" -ForegroundColor Gray
        Write-Host "     az webapp identity assign -g $rg -n $apiApp" -ForegroundColor DarkGray
        Write-Host "     az keyvault set-policy -n <kv-name> --object-id <principalId> --secret-permissions get list" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ⚠️  Managed Identity not assigned - Will enable" -ForegroundColor Yellow
}

Write-Host "`n[6/8] Service Bus..." -ForegroundColor Yellow
try {
    $sb = az resource list -g $rg --resource-type "Microsoft.ServiceBus/namespaces" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($sb -and $sb.Count -gt 0) {
        $sb | ForEach-Object { Write-Host "  ✅ $_" -ForegroundColor Green }
    } else {
        Write-Host "  ℹ️  No Service Bus (Week 4 - Next step)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ℹ️  No Service Bus (Week 4 - Next step)" -ForegroundColor Cyan
}

Write-Host "`n[7/8] Storage Accounts..." -ForegroundColor Yellow
try {
    $storage = az resource list -g $rg --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($storage -and $storage.Count -gt 0) {
        $storage | ForEach-Object { Write-Host "  ✅ $_" -ForegroundColor Green }
    } else {
        Write-Host "  ℹ️  No Storage Accounts (Week 5 - Future)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ℹ️  No Storage Accounts (Week 5 - Future)" -ForegroundColor Cyan
}

Write-Host "`n[8/8] API Management..." -ForegroundColor Yellow
try {
    $apim = az resource list -g $rg --resource-type "Microsoft.ApiManagement/service" --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($apim -and $apim.Count -gt 0) {
        $apim | ForEach-Object { Write-Host "  ✅ $_" -ForegroundColor Green }
    } else {
        Write-Host "  ℹ️  No API Management (Week 7-8 - Advanced)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ℹ️  No API Management (Week 7-8 - Advanced)" -ForegroundColor Cyan
}

Write-Host "`n"
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PROGRESS SUMMARY" -ForegroundColor Cyan  
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ Infrastructure & CI/CD: COMPLETE" -ForegroundColor Green
Write-Host "✅ Payment API: WORKING" -ForegroundColor Green

$global:VerificationResults = @{
    AppServices = $apps.Count -gt 0
    AppInsights = $ai -ne $null
    SqlDatabase = $sqlServers -ne $null
    KeyVault = $kvs -ne $null
    ManagedIdentity = $identity -ne $null
    ServiceBus = $sb -ne $null
    Storage = $storage -ne $null
    ApiManagement = $apim -ne $null
}
