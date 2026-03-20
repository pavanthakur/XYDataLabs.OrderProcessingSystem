---
applyTo: "**/Infrastructure/**,**/Migrations/**,**/DataContext/**"
---
# EF Core Conventions — XYDataLabs.OrderProcessingSystem

## DbContext
- Class: `OrderProcessingSystemDbContext`
- Project: `XYDataLabs.OrderProcessingSystem.Infrastructure`
- Startup project for migrations: `XYDataLabs.OrderProcessingSystem.API`

## Connection String
- Key name in config: `OrderProcessingSystemDbConnection`
- Constant: `Constants.Configuration.OrderProcessingSystemDbConnectionString`
- Registered in: `Infrastructure/StartupHelper.cs` → `InjectInfrastructureDependencies()`
- Dev SQL logging: `LogTo(Console.WriteLine)` + `EnableSensitiveDataLogging()` guarded by `IsDevelopment()`

## Azure SQL (Dev)
- Server: `orderprocessing-sql-dev.database.windows.net`
- Database: `OrderProcessingSystem_Dev`
- Admin: `sqladmin` (passwordless via `Authentication=Active Directory Default` — see ADR-006)
- Resource Group: `rg-orderprocessing-dev`

## Migration Commands
```powershell
# Add new migration
dotnet ef migrations add <MigrationName> \
  --project XYDataLabs.OrderProcessingSystem.Infrastructure \
  --startup-project XYDataLabs.OrderProcessingSystem.API

# Apply to Azure SQL (with firewall rule open for current IP)
$ip = (Invoke-RestMethod https://api.ipify.org)
az sql server firewall-rule create --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --name "dev-machine" --start-ip-address $ip --end-ip-address $ip
$azureCs = "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=OrderProcessingSystem_Dev;User ID=sqladmin;Password=Admin100@;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
dotnet ef database update --project XYDataLabs.OrderProcessingSystem.Infrastructure --startup-project XYDataLabs.OrderProcessingSystem.API --connection $azureCs
az sql server firewall-rule delete --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --name "dev-machine"
```

## Applied Migrations (as of March 2026)
1. `20241228010529_InitialCreate`
2. `20241228035910_AddColumnToOrderProduct`
3. `20241228044123_AddColumnToOrder`
4. `20250301223313_CustomerSeedData3For120CustomersToAdd`
5. `20250321181618_AddOpenpayCustomerIdColumnToCustomer`
6. `20250322153217_AddOpenpayPaymentTables`

## Current Table Count
13 tables — Customers (120 rows seeded), Products, Orders, OrderProducts, billing/payment tables
