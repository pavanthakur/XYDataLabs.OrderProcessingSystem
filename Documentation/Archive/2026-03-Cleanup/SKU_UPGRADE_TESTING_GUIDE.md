# App Service Plan SKU Upgrade & Testing Guide

## Overview
This guide covers upgrading from F1 (Free) to B1 (Basic) tier to test advanced features like deployment slots, then safely downgrading back to F1 after validation.

**Use Case**: Test enterprise deployment patterns (slots, staging, blue-green) without long-term cost commitment.

---

## Cost Impact

### Pricing Comparison (Monthly Estimates - Central India region)
| SKU | vCPU | RAM | Price/Month | Notes |
|-----|------|-----|-------------|-------|
| F1 (Free) | Shared | 1 GB | ₹0 ($0) | 60 CPU min/day limit, no slots |
| B1 (Basic) | 1 | 1.75 GB | ~₹1,050 ($13) | Always-on, custom domains, **deployment slots** |
| B2 (Basic) | 2 | 3.5 GB | ~₹2,100 ($26) | More capacity |
| S1 (Standard) | 1 | 1.75 GB | ~₹5,600 ($70) | Auto-scale, 5 slots, staging |

**Testing Cost**: Upgrading for 1-2 hours costs ~₹2-5 (prorated hourly billing).

### Downgrade Constraints
- **Can downgrade**: B1 → F1 ✅
- **Cannot downgrade if**: Using slots, custom domains, always-on features (must remove first).
- **Data safe**: Apps remain intact; only plan tier changes.

---

## Pre-Upgrade Checklist

### 1. Verify Current State
```powershell
# List current plans and their SKUs
az appservice plan list --query "[?starts_with(name, 'asp-orderprocessing')].[name, sku.name, sku.tier, resourceGroup]" -o table

# Expected output (before upgrade):
# Name                    SkuName  SkuTier  ResourceGroup
# asp-orderprocessing-dev F1       Free     rg-orderprocessing-dev
```

### 2. Backup Configuration (Optional)
```powershell
# Export current app settings (optional safety)
az webapp config appsettings list -g rg-orderprocessing-dev -n orderprocessing-api-xyapp > backup-api-settings.json
az webapp config appsettings list -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp > backup-ui-settings.json
```

### 3. Confirm Apps Are Running
```powershell
az webapp list --resource-group rg-orderprocessing-dev --query "[].{Name:name, State:state}" -o table

# Expected: both apps "Running"
```

---

## Upgrade to B1 (Enable Slot Testing)

### Option 1: CLI Upgrade (Recommended)
```powershell
# Upgrade dev environment plan to B1
az appservice plan update `
  --name asp-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --sku B1

# Verify upgrade
az appservice plan show `
  --name asp-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --query "{Name:name, Sku:sku.name, Tier:sku.tier}" -o table
```

**Expected Output**:
```
Name                    Sku  Tier
asp-orderprocessing-dev B1   Basic
```

### Option 2: Azure Portal Upgrade
1. Navigate to: https://portal.azure.com
2. Search for `asp-orderprocessing-dev`
3. **Settings** → **Scale up (App Service plan)**
4. Select **B1 Basic** → Click **Apply**
5. Wait 30-60 seconds for upgrade to complete

---

## End-to-End Slot Testing Workflow

### Phase 1: Commit & Push Changes
```powershell
# Stage all new scripts + docs
git add .
git commit -m "feat(devops): enterprise tooling - multi-RG OIDC, App Insights, slot mgmt"
git push origin main

# Verify workflows triggered (if auto-deploy enabled)
# https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions
```

### Phase 2: Create Staging Slot
```powershell
# Create staging slot for API app
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action create `
  -SlotName staging

# Verify slot created
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action list
```

**Expected Output**:
```
Name     ResourceGroup           DefaultHostName
staging  rg-orderprocessing-dev  orderprocessing-api-xyapp-staging.azurewebsites.net
```

### Phase 3: Deploy to Slot (Manual)
```powershell
# Build and publish locally (or use CI artifact)
dotnet publish XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj `
  --configuration Release `
  --output ./publish-api

# Deploy to staging slot
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action deploy `
  -SlotName staging `
  -PackagePath ./publish-api
```

### Phase 4: Warmup & Health Check
```powershell
# Wait for deployment to settle
Start-Sleep -Seconds 30

# Test staging slot endpoint
$stagingUrl = "https://orderprocessing-api-xyapp-staging.azurewebsites.net"
Invoke-WebRequest -Uri "$stagingUrl/swagger" -Method Get

# Automated warmup (if health endpoint exists)
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action warmup `
  -SlotName staging `
  -HealthUrl "$stagingUrl/health" `
  -WarmupTimeoutSeconds 120
```

### Phase 5: Swap Staging → Production
```powershell
# Perform blue-green swap
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action swap `
  -SlotName staging

# Verify production now serves new version
$prodUrl = "https://orderprocessing-api-xyapp.azurewebsites.net"
Invoke-WebRequest -Uri "$prodUrl/swagger" -Method Get
```

### Phase 6: Validate & Rollback Test
```powershell
# If issues detected, rollback immediately
./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -WebAppName orderprocessing-api-xyapp `
  -Action rollback

# Re-verify production reverted to previous version
Invoke-WebRequest -Uri "$prodUrl/swagger" -Method Get
```

### Phase 7: Test Application Insights Integration
```powershell
# Configure workspace-based App Insights for dev environment (API + UI)
./Resources/Azure-Deployment/setup-appinsights-dev.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -Location centralindia `
  -WorkspaceName logs-orderprocessing-dev `
  -ApiAppName orderprocessing-api-xyapp `
  -UiAppName orderprocessing-ui-xyapp `
  -ApiAppInsights ai-orderprocessing-api-dev `
  -UiAppInsights ai-orderprocessing-ui-dev

# Verify connection string set on API app
az webapp config appsettings list `
  -g rg-orderprocessing-dev `
  -n orderprocessing-api-xyapp `
  --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" -o tsv

# Generate traffic and check telemetry in portal/workspace
# https://portal.azure.com → Application Insights → ai-orderprocessing-api-dev
for ($i=1; $i -le 10; $i++) {
  Invoke-WebRequest -Uri "$prodUrl/swagger" -Method Get | Out-Null
  Start-Sleep -Seconds 2
}
```

---

## Downgrade Back to F1

### Prerequisites for Downgrade
1. **Delete all deployment slots**:
   ```powershell
   ./Resources/Azure-Deployment/manage-appservice-slots.ps1 `
     -ResourceGroup rg-orderprocessing-dev `
     -WebAppName orderprocessing-api-xyapp `
     -Action delete `
     -SlotName staging `
     -Force
   ```

2. **Disable always-on** (B1+ feature):
   ```powershell
   az webapp config set `
     -g rg-orderprocessing-dev `
     -n orderprocessing-api-xyapp `
     --always-on false

   az webapp config set `
     -g rg-orderprocessing-dev `
     -n orderprocessing-ui-xyapp `
     --always-on false
   ```

3. **Verify no custom domains** (not applicable for .azurewebsites.net):
   ```powershell
   az webapp config hostname list `
     -g rg-orderprocessing-dev `
     -n orderprocessing-api-xyapp `
     --query "[?!contains(name, 'azurewebsites.net')].name" -o tsv
   ```

### Execute Downgrade
```powershell
# Downgrade plan to F1
az appservice plan update `
  --name asp-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --sku F1

# Verify downgrade
az appservice plan show `
  --name asp-orderprocessing-dev `
  --resource-group rg-orderprocessing-dev `
  --query "{Name:name, Sku:sku.name, Tier:sku.tier}" -o table
```

**Expected Output**:
```
Name                    Sku  Tier
asp-orderprocessing-dev F1   Free
```

### Post-Downgrade Validation
```powershell
# Verify apps still running
az webapp list --resource-group rg-orderprocessing-dev --query "[].{Name:name, State:state}" -o table

# Test endpoints
Invoke-WebRequest -Uri https://orderprocessing-api-xyapp.azurewebsites.net/swagger -Method Get
Invoke-WebRequest -Uri https://orderprocessing-ui-xyapp.azurewebsites.net -Method Get
```

---

## Troubleshooting

### Issue 1: Downgrade Fails - "Cannot transition from B1 to F1"
**Cause**: Slots or always-on still enabled.

**Solution**:
```powershell
# List and delete all slots
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action list
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action delete -SlotName staging -Force

# Disable always-on
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-api-xyapp --always-on false
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp --always-on false

# Retry downgrade
az appservice plan update --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku F1
```

### Issue 2: App Insights Data Lost After Downgrade
**Impact**: None - Application Insights is independent of App Service Plan SKU.

**Verification**:
```powershell
az monitor app-insights component show -a ai-orderprocessing-dev -g rg-orderprocessing-dev --query "{Name:name, State:provisioningState}" -o table
```

### Issue 3: Slot URL Returns 404 After Creation
**Cause**: Slot created but no code deployed yet.

**Solution**: Deploy to slot (see Phase 3 above) or wait for next CI/CD run if workflow configured.

---

## Testing Checklist

### Before Upgrade
- [ ] Current plan is F1
- [ ] Apps running and accessible
- [ ] Optional: settings backed up

### During B1 Testing
- [ ] Plan upgraded to B1
- [ ] Staging slot created successfully
- [ ] Code deployed to slot
- [ ] Slot URL accessible (staging.azurewebsites.net)
- [ ] Warmup script completes without errors
- [ ] Swap staging → production succeeds
- [ ] Production serves new version
- [ ] Rollback tested and works
- [ ] App Insights provisioned and receiving data

### After Downgrade
- [ ] All slots deleted
- [ ] Always-on disabled
- [ ] Plan downgraded to F1
- [ ] Apps still running
- [ ] Endpoints accessible
- [ ] App Insights still functional (if kept)

---

## Cost Optimization Tips

### Minimize B1 Duration
- **Test during business hours** to avoid overnight charges.
- **Downgrade immediately** after testing (hourly billing).
- **Use dev environment only** (keep stg/prod on F1 unless needed).

### Alternative: Use Azure Free Credits
- **Students**: Azure for Students ($100/year free credit).
- **New users**: Azure Free Trial ($200 for 30 days).
- **MSDN/Visual Studio**: Monthly credits ($50-$150/month).

### Keep App Insights on Free Tier
- App Insights has 5 GB/month free ingestion.
- For dev/test, this is sufficient.
- Delete AI resource after testing to avoid minimal retention costs.

---

## Summary Commands (Quick Reference)

### Upgrade → Test → Downgrade (Fast Path)
```powershell
# 1. Upgrade
az appservice plan update --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku B1

# 2. Create slot & test
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action create -SlotName staging
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action list

# 3. Cleanup & downgrade
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action delete -SlotName staging -Force
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-api-xyapp --always-on false
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp --always-on false
az appservice plan update --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku F1
```

---

**Document Version**: 1.0  
**Last Updated**: November 17, 2025  
**Author**: DevOps Team  
**Status**: Testing Ready
