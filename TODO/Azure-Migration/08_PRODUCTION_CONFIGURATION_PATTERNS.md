# Production Configuration Notes

## Environment Configuration Summary

### Development Environment
- **Swagger**: ✅ Enabled 
- **Database**: Direct connection to 192.168.1.8
- **OpenPay**: Test credentials (IsProduction: false)
- **Environment Variable**: `ASPNETCORE_ENVIRONMENT=Development`

### UAT/Staging Environment  
- **Swagger**: ✅ Enabled (for testing)
- **Database**: Direct connection to 192.168.1.8
- **OpenPay**: Test credentials (IsProduction: false)
- **Environment Variable**: `ASPNETCORE_ENVIRONMENT=Staging`

### Production Environment
- **Swagger**: ⚠️ TEMPORARILY ENABLED (for testing only)
- **Database**: Direct connection to 192.168.1.8 (temporary)
- **OpenPay**: Test credentials (IsProduction: false, temporary)
- **Environment Variable**: `ASPNETCORE_ENVIRONMENT=Production`

## Production Security Checklist

### ❌ CURRENT STATE (Testing Configuration)
- [ ] Swagger is enabled (SECURITY RISK)
- [ ] Using test database credentials
- [ ] Using test OpenPay credentials  
- [ ] IsProduction set to false

### ✅ PRODUCTION-READY CONFIGURATION
To make production secure, make these changes:

#### 1. API Program.cs
In `Program.cs`, comment out Swagger lines in Production block:
```csharp
// Comment out these lines:
// app.UseSwagger();
// app.UseSwaggerUI(options => { ... });

// Uncomment these lines:
app.UseExceptionHandler("/Home/Error");
app.UseHsts();
```

#### 2. appsettings.Production.json 
Replace with environment variables:
```json
{
  "ConnectionStrings": {
    "OrderProcessingSystemDbConnection": "Server=${PROD_DATABASE_SERVER};Database=OrderProcessingSystem_Production;User Id=${PROD_DATABASE_USER};Password=${PROD_DATABASE_PASSWORD};TrustServerCertificate=True;"
  },
  "OpenPay": {
    "MerchantId": "${OPENPAY_MERCHANT_ID}",
    "PrivateKey": "${OPENPAY_PRIVATE_KEY}",
    "DeviceSessionId": "${OPENPAY_DEVICE_SESSION_ID}",
    "IsProduction": true,
    "RedirectUrl": "${OPENPAY_REDIRECT_URL}"
  }
}
```

#### 3. Environment Variables Required
Set these in production environment:
- `PROD_DATABASE_SERVER`
- `PROD_DATABASE_USER` 
- `PROD_DATABASE_PASSWORD`
- `OPENPAY_MERCHANT_ID`
- `OPENPAY_PRIVATE_KEY`
- `OPENPAY_DEVICE_SESSION_ID`
- `OPENPAY_REDIRECT_URL`

## Current Fix Summary

### Fixed for UAT HTTP/HTTPS:
1. ✅ Swagger enabled for Staging environment
2. ✅ Database connection fixed
3. ✅ OpenPay credentials fixed

### Fixed for Production HTTP/HTTPS:
1. ✅ Swagger temporarily enabled (with security warnings)
2. ✅ Database connection configured (temporary)
3. ✅ OpenPay credentials configured (temporary)
4. ✅ Clear documentation for production hardening

### Commands to Test:
```bash
# UAT HTTP
.\start-docker.ps1 -Environment uat -Profile http

# UAT HTTPS  
.\start-docker.ps1 -Environment uat -Profile https

# Production HTTP
.\start-docker.ps1 -Environment prod -Profile http

# Production HTTPS
.\start-docker.ps1 -Environment prod -Profile https
```
