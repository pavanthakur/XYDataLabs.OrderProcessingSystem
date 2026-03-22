using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Bogus;
using Microsoft.EntityFrameworkCore;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData
{
    public static class DbInitializer
    {
        private static readonly string[] StartupSeedTenantCodes = { "TenantA", "TenantB" };
        private const int SeededCustomerCountPerTenant = 120;

        public static void Initialize(OrderProcessingSystemDbContext context, bool applyMigrations = true)
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

            var startupSeedTenants = GetStartupSeedTenants(context);

            SeedOpenpayProviders(context, startupSeedTenants);

            foreach (var seedTenant in startupSeedTenants)
            {
                SeedTenantSampleData(context, seedTenant);
            }

            UpdateOrderTotalPrices(context, startupSeedTenants.Select(seedTenant => seedTenant.TenantId).ToArray());
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

        private sealed record StartupSeedTenant(int TenantId, string TenantCode, string TenantName);
    }
}