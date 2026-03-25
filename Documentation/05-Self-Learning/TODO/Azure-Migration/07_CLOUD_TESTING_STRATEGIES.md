# 📋 Non-Docker Visual Studio Profile Testing Checklist

**Date**: August 15, 2025  
**Testing Mode**: Non-Docker (Local Development)

---

## ✅ Prerequisites
- [ ] Visual Studio 2022 with .NET 8.0 SDK installed
- [ ] SQL Server running on localhost:1433 ✅ **Verified Available**
- [ ] No Docker containers running ✅ **Verified Clean**
- [ ] Solution XYDataLabs.OrderProcessingSystem.sln opened in Visual Studio

---

## 🧪 Test 1: API HTTP Profile (Non-Docker)

**Profile**: `http` (API project)  
**Target**: http://localhost:5010/swagger

### Steps:
1. [ ] Set `XYDataLabs.OrderProcessingSystem.API` as startup project
2. [ ] Select "http" profile in dropdown (NOT docker-dev-http)
3. [ ] Press F5 to start debugging
4. [ ] Wait for browser to open automatically

### Expected Results:
- [ ] ✅ Application starts without errors
- [ ] ✅ Browser opens to http://localhost:5010/swagger
- [ ] ✅ Swagger UI loads with all API endpoints visible
- [ ] ✅ Database `OrderProcessingSystem_Local` created in local SQL Server
- [ ] ✅ Console shows: "Database initialized and AppMasterData loaded successfully during startup"
- [ ] ✅ Local environment script executes: `set-local-env.ps1` configures ports 5010-5013

### Verification Commands:
```powershell
# Check database creation (Note: Uses OrderProcessingSystem_Local for non-Docker)
sqlcmd -S localhost -U sa -P <LOCAL_SQL_PASSWORD> -Q "SELECT name FROM sys.databases WHERE name = 'OrderProcessingSystem_Local'"

# Test API endpoint
Invoke-RestMethod -Uri "http://localhost:5010/api/Customer/GetAllCustomers?pageNumber=1&pageSize=3" -Method Get
```

### Test Results:
- [ ] ✅ PASS - All expected results achieved
- [ ] ❌ FAIL - Issues found: ________________

---

## 🧪 Test 2: API HTTPS Profile (Non-Docker)

**Profile**: `https` (API project)  
**Target**: https://localhost:5011/swagger

### Steps:
1. [ ] Stop current debugging session (red stop button)
2. [ ] Select "https" profile in dropdown (NOT docker-dev-https)
3. [ ] Press F5 to start debugging
4. [ ] Accept SSL certificate if prompted
5. [ ] Wait for browser to open automatically

### Expected Results:
- [ ] ✅ Application starts without errors
- [ ] ✅ Browser opens to https://localhost:5011/swagger
- [ ] ✅ Swagger UI loads with SSL certificate working
- [ ] ✅ Same database `OrderProcessingSystem` used (shared with HTTP)
- [ ] ✅ SSL/TLS encryption working properly

### Verification Commands:
```powershell
# Test HTTPS API endpoint
Invoke-RestMethod -Uri "https://localhost:5011/api/Customer/GetAllCustomers?pageNumber=1&pageSize=3" -Method Get
```

### Test Results:
- [ ] ✅ PASS - All expected results achieved
- [ ] ❌ FAIL - Issues found: ________________

---

## 🧪 Test 3: UI HTTP Profile (Non-Docker)

**Profile**: `http` (UI project)  
**Target**: http://localhost:5012

### Prerequisites:
- [ ] API running on http://localhost:5010 OR https://localhost:5011

### Steps:
1. [ ] Set `XYDataLabs.OrderProcessingSystem.UI` as startup project
2. [ ] Select "http" profile in dropdown (NOT docker-dev-http)
3. [ ] Press F5 to start debugging
4. [ ] Wait for browser to open automatically

### Expected Results:
- [ ] ✅ UI application starts without errors
- [ ] ✅ Browser opens to http://localhost:5012
- [ ] ✅ UI connects to API successfully
- [ ] ✅ Can browse customers and data
- [ ] ✅ All UI functionality working

### Manual Testing:
- [ ] Navigate to customer list page
- [ ] Search for customers
- [ ] View customer details
- [ ] Check if data loads from API

### Test Results:
- [ ] ✅ PASS - All expected results achieved
- [ ] ❌ FAIL - Issues found: ________________

---

## 🧪 Test 4: UI HTTPS Profile (Non-Docker)

**Profile**: `https` (UI project)  
**Target**: https://localhost:5013

### Prerequisites:
- [ ] API running on https://localhost:5011 (HTTPS recommended for HTTPS UI)

### Steps:
1. [ ] Stop current UI debugging session
2. [ ] Ensure API is running on HTTPS (https://localhost:5011)
3. [ ] Select "https" profile in dropdown (NOT docker-dev-https)
4. [ ] Press F5 to start debugging
5. [ ] Accept SSL certificate if prompted
6. [ ] Wait for browser to open automatically

### Expected Results:
- [ ] ✅ UI application starts without errors
- [ ] ✅ Browser opens to https://localhost:5013
- [ ] ✅ UI connects to API via HTTPS
- [ ] ✅ Full end-to-end HTTPS communication
- [ ] ✅ SSL certificates working for both API and UI

### Manual Testing:
- [ ] Navigate to customer list page over HTTPS
- [ ] Verify secure connection (lock icon in browser)
- [ ] All API calls working over HTTPS
- [ ] No mixed content warnings

### Test Results:
- [ ] ✅ PASS - All expected results achieved
- [ ] ❌ FAIL - Issues found: ________________

---

## 📊 Final Summary

### Port Usage Verification:
- [ ] API HTTP: http://localhost:5010 - Working
- [ ] API HTTPS: https://localhost:5011 - Working
- [ ] UI HTTP: http://localhost:5012 - Working  
- [ ] UI HTTPS: https://localhost:5013 - Working

### Database Verification:
- [ ] Database Name: `OrderProcessingSystem` (without environment suffix)
- [ ] Connection: localhost:1433 (local SQL Server)
- [ ] Seeding: 120 customers created
- [ ] OpenPay Provider: Seeded successfully

### Overall Results:
- [ ] ✅ All non-Docker profiles working perfectly
- [ ] ✅ HTTP and HTTPS profiles both functional
- [ ] ✅ API and UI integration working
- [ ] ✅ Database creation and seeding working
- [ ] ❌ Issues found that need resolution: ________________

---

## 🔧 Troubleshooting

### Common Issues:
1. **Port Already in Use**: 
   - Check if Docker containers are running: `docker ps`
   - Stop any conflicting services
   
2. **SSL Certificate Issues**:
   - Run: `dotnet dev-certs https --clean`
   - Run: `dotnet dev-certs https --trust`
   
3. **Database Connection Issues**:
   - Verify SQL Server running: `Test-NetConnection localhost -Port 1433`
   - Check connection string in sharedsettings.dev.json

4. **API Connection Issues**:
   - Ensure API is running before starting UI
   - Check CORS settings in API configuration
   - Verify ports not conflicting with Docker

---

**Testing Completed By**: ________________  
**Date**: August 15, 2025  
**Overall Status**: ✅ PASS / ❌ FAIL  
**Notes**: ________________
