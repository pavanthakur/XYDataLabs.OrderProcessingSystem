using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Bogus;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData
{
    public static class DbInitializer
    {
        private static readonly string[] StartupSeedTenantCodes = { "TenantA", "TenantB" };
        private const int SeededCustomerCountPerTenant = 120;

        public static void Initialize(OrderProcessingSystemDbContext context, IConfiguration? configuration = null, bool applyMigrations = true)
        {
            if (context is null)
            {
                throw new ArgumentNullException(nameof(context));
            }

            // Azure deployments run schema migrations in workflow steps before app startup.
            if (applyMigrations)
            {
                context.Database.Migrate();
            }

            // Apply dedicated tenant connection strings from configuration before Phase 2.
            // Migrations always seed TenantC.ConnectionString = NULL. This step re-applies
            // environment-specific values from DedicatedTenantConnectionStrings config so
            // Phase 2 can run without a manual UPDATE on every fresh database creation.
            if (configuration is not null)
            {
                ApplyDedicatedConnectionStrings(context, configuration);
            }

            // Phase 1: seed shared-pool tenants (TenantA, TenantB) into the main DB.
            var startupSeedTenants = GetStartupSeedTenants(context);

            SeedOpenpayProviders(context, startupSeedTenants);

            foreach (var seedTenant in startupSeedTenants)
            {
                SeedTenantSampleData(context, seedTenant);
            }

            UpdateOrderTotalPrices(context, startupSeedTenants.Select(seedTenant => seedTenant.TenantId).ToArray());

            // Phase 2: seed dedicated-tier tenants into their own DB connection.
            // Works for both Option A (ConnectionString points to same physical DB) and
            // Option B (ConnectionString points to a separate dedicated DB).
            // Skipped when ConnectionString is null — no DB to connect to yet.
            SeedDedicatedTenants(context, applyMigrations);
        }

        /// <summary>
        /// Reads DedicatedTenantConnectionStrings from IConfiguration and stamps any matching
        /// Dedicated-tier tenant rows whose ConnectionString is currently NULL.
        /// This fixes the "two-restart" problem: migrations always seed ConnectionString = NULL,
        /// so without this step Phase 2 would find nothing on every fresh DB creation.
        /// </summary>
        private static void ApplyDedicatedConnectionStrings(OrderProcessingSystemDbContext context, IConfiguration configuration)
        {
            var section = configuration.GetSection("DedicatedTenantConnectionStrings");
            if (!section.Exists())
                return;

            var configuredStrings = section.GetChildren()
                .ToDictionary(c => c.Key, c => c.Value, StringComparer.OrdinalIgnoreCase);

            if (configuredStrings.Count == 0)
                return;

            var dedicatedCodes = configuredStrings.Keys.ToArray();
            var tenantsToUpdate = context.Tenants
                .Where(t => t.TenantTier == "Dedicated" && t.ConnectionString == null && dedicatedCodes.Contains(t.Code))
                .ToList();

            foreach (var tenant in tenantsToUpdate)
            {
                if (configuredStrings.TryGetValue(tenant.Code, out var cs) && !string.IsNullOrWhiteSpace(cs))
                    tenant.ConnectionString = cs;
            }

            if (tenantsToUpdate.Any(t => t.ConnectionString != null))
                context.SaveChanges();
        }

        private static IReadOnlyList<StartupSeedTenant> GetStartupSeedTenants(OrderProcessingSystemDbContext context)
        {
            var tenants = context.Tenants
                .AsNoTracking()
                .Where(tenant => StartupSeedTenantCodes.Contains(tenant.Code))
                .Select(tenant => new StartupSeedTenant(tenant.Id, tenant.Code, tenant.Name))
                .ToList();

            var missingTenantCodes = StartupSeedTenantCodes
                .Except(tenants.Select(tenant => tenant.TenantCode), StringComparer.Ordinal)
                .ToArray();

            if (missingTenantCodes.Length > 0)
            {
                throw new InvalidOperationException($"Startup seed tenants were not found in Tenants table: {string.Join(", ", missingTenantCodes)}");
            }

            return tenants;
        }

        private static void SeedTenantSampleData(OrderProcessingSystemDbContext context, StartupSeedTenant seedTenant)
        {
            if (!context.Customers.Any(customer => customer.TenantId == seedTenant.TenantId))
            {
                SeedCustomers(context, seedTenant);
            }

            if (!context.Products.Any(product => product.TenantId == seedTenant.TenantId))
            {
                SeedProducts(context, seedTenant);
            }

            if (!context.Orders.Any(order => order.TenantId == seedTenant.TenantId))
            {
                SeedOrders(context, seedTenant);
            }

            if (!context.OrderProducts.Any(orderProduct => orderProduct.TenantId == seedTenant.TenantId))
            {
                SeedOrderProducts(context, seedTenant);
            }
        }

        private static void SeedCustomers(OrderProcessingSystemDbContext context, StartupSeedTenant seedTenant)
        {
            var faker = new Faker<Customer>()
                .RuleFor(c => c.Name, f => $"{seedTenant.TenantCode} {f.Name.FullName()}")
                .RuleFor(c => c.Email, (f, _) => $"{seedTenant.TenantCode}.{f.UniqueIndex}@example.test")
                .RuleFor(c => c.TenantId, _ => seedTenant.TenantId);

            var customers = faker.Generate(SeededCustomerCountPerTenant);
            context.Customers.AddRange(customers);
            context.SaveChanges();
        }

        private static void SeedProducts(OrderProcessingSystemDbContext context, StartupSeedTenant seedTenant)
        {
            var products = new List<Product>
                {
                    new Product { Name = $"{seedTenant.TenantCode} Laptop", Description = $"Sample laptop for {seedTenant.TenantName}", Price = 500.00m, TenantId = seedTenant.TenantId },
                    new Product { Name = $"{seedTenant.TenantCode} Phone", Description = $"Sample phone for {seedTenant.TenantName}", Price = 300.00m, TenantId = seedTenant.TenantId },
                    new Product { Name = $"{seedTenant.TenantCode} Headphones", Description = $"Sample headphones for {seedTenant.TenantName}", Price = 200.00m, TenantId = seedTenant.TenantId }
                };
            context.Products.AddRange(products);
            context.SaveChanges();
        }

        private static void SeedOrders(OrderProcessingSystemDbContext context, StartupSeedTenant seedTenant)
        {
            var customers = context.Customers
                .Where(customer => customer.TenantId == seedTenant.TenantId)
                .OrderBy(customer => customer.CustomerId)
                .ToList();

            var products = context.Products
                .Where(product => product.TenantId == seedTenant.TenantId)
                .OrderBy(product => product.ProductId)
                .ToList();

            var orders = new List<Order>
                {
                    new Order { OrderDate = DateTime.UtcNow, CustomerId = customers[0].CustomerId, TotalPrice = products.Sum(product => product.Price), TenantId = seedTenant.TenantId },
                    new Order { OrderDate = DateTime.UtcNow, CustomerId = customers[1].CustomerId, TenantId = seedTenant.TenantId }
                };
            context.Orders.AddRange(orders);
            context.SaveChanges();
        }

        private static void SeedOrderProducts(OrderProcessingSystemDbContext context, StartupSeedTenant seedTenant)
        {
            var orders = context.Orders
                .Where(order => order.TenantId == seedTenant.TenantId)
                .OrderBy(order => order.OrderId)
                .ToList();

            var products = context.Products
                .Where(product => product.TenantId == seedTenant.TenantId)
                .OrderBy(product => product.ProductId)
                .ToList();

            var orderProducts = new List<OrderProduct>
                {
                    new OrderProduct { OrderId = orders[0].OrderId, ProductId = products[0].ProductId, Quantity = 1, TenantId = seedTenant.TenantId },
                    new OrderProduct { OrderId = orders[0].OrderId, ProductId = products[1].ProductId, Quantity = 2, TenantId = seedTenant.TenantId },
                    new OrderProduct { OrderId = orders[1].OrderId, ProductId = products[2].ProductId, Quantity = 1, TenantId = seedTenant.TenantId }
                };
            context.OrderProducts.AddRange(orderProducts);
            context.SaveChanges();
        }

        private static void SeedOpenpayProviders(OrderProcessingSystemDbContext context, IReadOnlyList<StartupSeedTenant> seedTenants)
        {
            foreach (var seedTenant in seedTenants)
            {
                var providerExists = context.PaymentProviders.Any(provider =>
                    provider.TenantId == seedTenant.TenantId &&
                    provider.Name == "OpenPay");

                if (providerExists)
                {
                    continue;
                }

                var openPayProvider = new PaymentProvider
                {
                    Name = "OpenPay",
                    APIUrl = "https://sandbox-api.openpay.mx/v1",
                    IsActive = true,
                    IsProduction = false,
                    Use3DSecure = true,
                    TenantId = seedTenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                };

                context.PaymentProviders.Add(openPayProvider);
            }

            context.SaveChanges();
        }

        private static void UpdateOrderTotalPrices(OrderProcessingSystemDbContext context, params int[] tenantIds)
        {
            // Perform the LINQ query to calculate the total price for each order
            var orderTotalPrices = context.Orders
                .Where(order => tenantIds.Contains(order.TenantId))
                .Join(context.OrderProducts,
                    o => o.OrderId,
                    op => op.OrderId,
                    (o, op) => new { o, op })
                .Join(context.Products,
                    o_op => o_op.op.ProductId,
                    p => p.ProductId,
                    (o_op, p) => new { o_op.o, TotalPrice = p.Price * o_op.op.Quantity })
                .GroupBy(o_p => o_p.o.OrderId)
                .Select(g => new
                {
                    OrderId = g.Key,
                    TotalPrice = g.Sum(x => x.TotalPrice) // Sum the prices of the matched products
                })
                .ToList();

            // Update each order with the calculated total price
            foreach (var orderTotal in orderTotalPrices)
            {
                var order = context.Orders.Find(orderTotal.OrderId);
                if (order != null)
                {
                    order.TotalPrice = orderTotal.TotalPrice;
                }
            }
            // Save the changes to the database
            context.SaveChanges();
        }

        /// <summary>
        /// Seeds sample data for every Dedicated-tier tenant whose ConnectionString is provisioned.
        /// Creates a separate DbContext per dedicated tenant so data lands in the correct database,
        /// whether that is the same physical DB (Option A) or a separate DB (Option B).
        /// A NullTenantProvider is injected so EF Core query filters evaluate safely (HasTenantContext=false →
        /// filter short-circuits to true, making all rows visible — correct for cross-tenant seeding).
        /// </summary>
        private static void SeedDedicatedTenants(OrderProcessingSystemDbContext mainContext, bool applyMigrations)
        {
            var dedicatedTenants = mainContext.Tenants
                .AsNoTracking()
                .Where(t => t.TenantTier == "Dedicated" && t.ConnectionString != null)
                .ToList();

            foreach (var tenant in dedicatedTenants)
            {
                var dedicatedOptions = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
                    .UseSqlServer(tenant.ConnectionString!)
                    .Options;

                // NullTenantProvider ensures EF Core query filters short-circuit safely
                // (HasTenantContext = false → filter = true → all rows visible).
                // Without this, dedicatedContext._tenantProvider would be null and EF Core's
                // expression tree evaluator can NullReference on _tenantProvider.HasTenantContext.
                using var dedicatedContext = new OrderProcessingSystemDbContext(dedicatedOptions, new NullTenantProvider());

                // For Option B (fresh dedicated DB), apply migrations so the schema exists.
                // For Option A (same DB), this is idempotent — no-op.
                if (applyMigrations)
                    dedicatedContext.Database.Migrate();

                // Look up the tenant row in the dedicated DB's own Tenants table.
                // Migrations seed all tenant rows into every DB, so this row will exist.
                var seedTenant = dedicatedContext.Tenants
                    .AsNoTracking()
                    .Where(t => t.Code == tenant.Code)
                    .Select(t => new StartupSeedTenant(t.Id, t.Code, t.Name))
                    .FirstOrDefault();

                if (seedTenant is null)
                    continue;

                SeedOpenpayProviders(dedicatedContext, new[] { seedTenant });
                SeedTenantSampleData(dedicatedContext, seedTenant);
                UpdateOrderTotalPrices(dedicatedContext, seedTenant.TenantId);
            }
        }

        /// <summary>
        /// Null-object ITenantProvider used when creating a DbContext for dedicated-tenant seeding.
        /// HasTenantContext = false causes EF Core query filters to pass all rows through,
        /// which is correct when seeding a dedicated DB that holds only one tenant's data.
        /// </summary>
        private sealed class NullTenantProvider : ITenantProvider
        {
            public bool HasTenantContext => false;
            public int TenantId => 0;
            public string TenantCode => string.Empty;
            public string TenantExternalId => string.Empty;
            public string? ConnectionString => null;
            public bool IsSharedPool => true;
        }

        private sealed record StartupSeedTenant(int TenantId, string TenantCode, string TenantName);
    }
}