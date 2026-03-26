# App Service Plan SKU Upgrade & Slot Testing Guide

## Overview

Upgrade from F1 (Free) to B1 (Basic) to test deployment slots and blue-green patterns, then downgrade back to F1.

**Use Case**: Validate enterprise deployment patterns without long-term cost.

---

## Cost Comparison (Central India)

| SKU | vCPU | RAM | Price/Month | Notes |
|-----|------|-----|-------------|-------|
| F1 (Free) | Shared | 1 GB | ₹0 ($0) | 60 CPU min/day, no slots |
| B1 (Basic) | 1 | 1.75 GB | ~₹1,050 ($13) | Always-on, **deployment slots** |
| B2 (Basic) | 2 | 3.5 GB | ~₹2,100 ($26) | More capacity |
| S1 (Standard) | 1 | 1.75 GB | ~₹5,600 ($70) | Auto-scale, 5 slots |

**Testing cost**: ~₹2-5 for 1-2 hours (prorated).

---

## Upgrade to B1

```powershell
# Upgrade dev plan
az appservice plan update --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku B1

# Verify
az appservice plan show --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --query "{Name:name, Sku:sku.name, Tier:sku.tier}" -o table
```

## Slot Testing Workflow

```powershell
# 1. Create staging slot
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action create -SlotName staging

# 2. Deploy to slot
dotnet publish XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj --configuration Release --output ./publish-api
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action deploy -SlotName staging -PackagePath ./publish-api

# 3. Warmup & verify
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action warmup -SlotName staging -HealthUrl "https://orderprocessing-api-xyapp-staging.azurewebsites.net/health" -WarmupTimeoutSeconds 120

# 4. Swap to production
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action swap -SlotName staging

# 5. Rollback if needed
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action rollback
```

## Downgrade Back to F1

**Pre-downgrade** — must remove slot features first:

```powershell
# Delete all slots
./Resources/Azure-Deployment/manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-dev -WebAppName orderprocessing-api-xyapp -Action delete -SlotName staging -Force

# Disable always-on
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-api-xyapp --always-on false
az webapp config set -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp --always-on false

# Downgrade
az appservice plan update --name asp-orderprocessing-dev --resource-group rg-orderprocessing-dev --sku F1

# Verify apps still running
az webapp list --resource-group rg-orderprocessing-dev --query "[].{Name:name, State:state}" -o table
```

### Downgrade Constraints

| Constraint | Downgradable? |
|------------|--------------|
| B1 → F1 (no slots) | ✅ Yes |
| B1 → F1 (slots exist) | ❌ Delete slots first |
| B1 → F1 (always-on enabled) | ❌ Disable always-on first |

> **Data is safe** — apps remain intact; only the plan tier changes.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Cannot transition from B1 to F1" | Delete all slots + disable always-on first |
| App Insights data lost after downgrade | Not affected — App Insights is independent of App Service Plan SKU |
