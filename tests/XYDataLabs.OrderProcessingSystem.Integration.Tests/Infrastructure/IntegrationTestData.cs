using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

internal sealed record TestTenantContext(
    int TenantId,
    string TenantCode,
    string TenantExternalId,
    string TenantName,
    string TenantStatus,
    string? ConnectionString = null,
    bool IsSharedPool = true)
{
    public TenantContext ToTenantContext() => new(
        TenantId, TenantCode, TenantExternalId, TenantName, TenantStatus,
        ConnectionString, IsSharedPool);
}

internal sealed record OrderScenarioSeed(int CustomerId, int ProductId);

internal sealed record TenantIsolationSeed(
    int CustomerId,
    int ProductId,
    int OrderId,
    int PaymentProviderId,
    int PaymentMethodId,
    string CustomerEmail,
    string ProductName,
    string PaymentProviderName,
    string PaymentMethodToken);

internal static class IntegrationTestData
{
    public static Task<TestTenantContext> CreateTenantAsync(
        IntegrationTestWebAppFactory factory,
        string status = "Active") =>
        factory.ExecuteDbContextAsync(async dbContext =>
        {
            var uniqueSuffix = Guid.NewGuid().ToString("N")[..10];
            var tenant = new Tenant
            {
                Code = $"IT{uniqueSuffix}"[..Math.Min(12, 2 + uniqueSuffix.Length)],
                ExternalId = $"tnt_ext_it_{uniqueSuffix}",
                Name = $"Integration Tenant {uniqueSuffix}",
                Status = status,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            };

            dbContext.Tenants.Add(tenant);
            await dbContext.SaveChangesAsync();

            return new TestTenantContext(tenant.Id, tenant.Code, tenant.ExternalId, tenant.Name, tenant.Status);
        });

    /// <summary>
    /// Creates a Dedicated-tier tenant in the shared (registry) database.
    /// Pass a non-null <paramref name="connectionString"/> to make it resolvable
    /// (routes to that DB); pass null to test the fail-loud unprovisioned path.
    /// </summary>
    public static Task<TestTenantContext> CreateDedicatedTenantAsync(
        IntegrationTestWebAppFactory factory,
        string? connectionString = null,
        string status = "Active") =>
        factory.ExecuteDbContextAsync(async dbContext =>
        {
            var uniqueSuffix = Guid.NewGuid().ToString("N")[..10];
            var tenant = new Tenant
            {
                Code = $"DT{uniqueSuffix}"[..Math.Min(12, 2 + uniqueSuffix.Length)],
                ExternalId = $"tnt_ext_ded_{uniqueSuffix}",
                Name = $"Dedicated Tenant {uniqueSuffix}",
                Status = status,
                TenantTier = TenantTierConstants.Dedicated,
                ConnectionString = connectionString,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            };

            dbContext.Tenants.Add(tenant);
            await dbContext.SaveChangesAsync();

            return new TestTenantContext(
                tenant.Id, tenant.Code, tenant.ExternalId, tenant.Name, tenant.Status,
                tenant.ConnectionString, IsSharedPool: false);
        });

    public static Task<OrderScenarioSeed> SeedOrderScenarioAsync(
        IntegrationTestWebAppFactory factory,
        int tenantId) =>
        factory.ExecuteDbContextAsync(async dbContext =>
        {
            var uniqueSuffix = Guid.NewGuid().ToString("N")[..8];

            var customer = new Customer
            {
                Name = $"Scenario Customer {uniqueSuffix}",
                Email = $"scenario-{uniqueSuffix}@test.com",
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            };

            var product = new Product
            {
                Name = $"Scenario Product {uniqueSuffix}",
                Description = "Integration test product",
                Price = 42.50m,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            };

            dbContext.Customers.Add(customer);
            dbContext.Products.Add(product);
            await dbContext.SaveChangesAsync();

            return new OrderScenarioSeed(customer.CustomerId, product.ProductId);
        });

    public static Task<TenantIsolationSeed> SeedTenantIsolationAsync(
        IntegrationTestWebAppFactory factory,
        int tenantId,
        string marker) =>
        factory.ExecuteDbContextAsync(async dbContext =>
        {
            var createdAt = DateTime.UtcNow;
            var customer = new Customer
            {
                Name = $"Customer {marker}",
                Email = $"customer-{marker}@test.com",
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            var product = new Product
            {
                Name = $"Product {marker}",
                Description = $"Seeded product {marker}",
                Price = 50.00m,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            var paymentProvider = new PaymentProvider
            {
                Name = $"Provider-{marker}",
                APIUrl = $"https://payments-{marker}.example.test",
                IsProduction = false,
                IsActive = true,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            dbContext.Customers.Add(customer);
            dbContext.Products.Add(product);
            dbContext.PaymentProviders.Add(paymentProvider);
            await dbContext.SaveChangesAsync();

            var order = new Order
            {
                CustomerId = customer.CustomerId,
                OrderDate = createdAt,
                TotalPrice = product.Price,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            dbContext.Orders.Add(order);
            await dbContext.SaveChangesAsync();

            var orderProduct = new OrderProduct
            {
                OrderId = order.OrderId,
                ProductId = product.ProductId,
                Quantity = 1,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            var paymentMethod = new PaymentMethod
            {
                PaymentProviderId = paymentProvider.Id,
                Token = $"token-{marker}-{Guid.NewGuid():N}"[..24],
                Status = true,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            dbContext.OrderProducts.Add(orderProduct);
            dbContext.PaymentMethods.Add(paymentMethod);
            await dbContext.SaveChangesAsync();

            return new TenantIsolationSeed(
                customer.CustomerId,
                product.ProductId,
                order.OrderId,
                paymentProvider.Id,
                paymentMethod.Id,
                customer.Email,
                product.Name,
                paymentProvider.Name,
                paymentMethod.Token);
        });
}