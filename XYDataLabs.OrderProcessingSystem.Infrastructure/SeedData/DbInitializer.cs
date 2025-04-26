using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Bogus;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData
{
    public static class DbInitializer
    {
        public static void Initialize(OrderProcessingSystemDbContext context)
        {
            context.Database.EnsureCreated();  // Ensure the DB is created

            SeedOpenpayProvider(context);

            // Check if the data already exists
            if (context.Customers.Any() || context.Products.Any() || context.Orders.Any() || context.OrderProducts.Any())
            {
                return; // DB has been seeded
            }

            SeedCustomers(context);
            SeedProducts(context);
            SeedOrders(context);
            SeedOrderProducts(context);

            UpdateOrderTotalPrices(context);
        }

        private static void SeedCustomers(OrderProcessingSystemDbContext context)
        {
            var faker = new Faker<Customer>()
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email());

            var customers = faker.Generate(120);
            context.Customers.AddRange(customers);
            context.SaveChanges();
        }

        private static void SeedProducts(OrderProcessingSystemDbContext context)
        {
            var products = new List<Product>
                {
                    new Product { Name = "Laptop", Price = 500.00m },
                    new Product { Name = "Phone", Price = 300.00m },
                    new Product { Name = "Headphones", Price = 200.00m }
                };
            context.Products.AddRange(products);
            context.SaveChanges();
        }

        private static void SeedOrders(OrderProcessingSystemDbContext context)
        {
            var customers = context.Customers.ToList();
            var products = context.Products.ToList();

            var orders = new List<Order>
                {
                    new Order { OrderDate = DateTime.Now, CustomerId = customers[0].CustomerId, TotalPrice = products.Sum(product => product.Price) },
                    new Order { OrderDate = DateTime.Now, CustomerId = customers[1].CustomerId }
                };
            context.Orders.AddRange(orders);
            context.SaveChanges();
        }

        private static void SeedOrderProducts(OrderProcessingSystemDbContext context)
        {
            var orders = context.Orders.ToList();
            var products = context.Products.ToList();

            var orderProducts = new List<OrderProduct>
                {
                    new OrderProduct { OrderId = orders[0].OrderId, ProductId = products[0].ProductId, Quantity = 1 },
                    new OrderProduct { OrderId = orders[0].OrderId, ProductId = products[1].ProductId, Quantity = 2 },
                    new OrderProduct { OrderId = orders[1].OrderId, ProductId = products[2].ProductId, Quantity = 1 }
                };
            context.OrderProducts.AddRange(orderProducts);
            context.SaveChanges();
        }

        private static void SeedOpenpayProvider(OrderProcessingSystemDbContext context)
        {
            // Check if providers already exist
            if (context.PaymentProviders.Any())
            {
                return;
            }

            // Add OpenPay Provider
            var openPayProvider = new PaymentProvider
            {
                Name = "OpenPay",
                APIUrl = "https://sandbox-api.openpay.mx/v1",
                IsActive = true,
                IsProduction = false,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            };
            context.PaymentProviders.Add(openPayProvider);
            context.SaveChanges();
        }

        private static void UpdateOrderTotalPrices(OrderProcessingSystemDbContext context)
        {
            // Perform the LINQ query to calculate the total price for each order
            var orderTotalPrices = context.Orders
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
    }
}