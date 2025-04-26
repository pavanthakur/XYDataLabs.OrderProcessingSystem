using AutoMapper;
using Bogus;
using FluentValidation;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Application.Services;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Moq;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.TestBase
{
    public abstract class OrderServiceTestBase : OrderProcessingSystemTestBase<OrderService>
    {
        protected readonly IOrderService _orderService;

        protected readonly int CustomerId = 1;
        protected readonly List<int> ProductIds;
        protected readonly Customer Customer;
        protected readonly List<Product> Products;
        protected readonly OrderDto OrderDto;


        protected OrderServiceTestBase()
        {
            _orderService = new OrderService(MockDbContext.Object, MockOrderValidator.Object, MockMapper.Object);

            Customer = GenerateCustomer();
            Products = GenerateProducts(3);
            ProductIds = Products.Select(p => p.ProductId).ToList();
        }

        protected Customer GenerateCustomer()
        {
            return new Faker<Customer>()
                .RuleFor(c => c.CustomerId, f => f.IndexFaker + 1)
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email())
                .RuleFor(c => c.Orders, f => new List<Order>())
                .Generate();
        }

        protected List<Product> GenerateProducts(int count)
        {
            return new Faker<Product>()
                .RuleFor(p => p.ProductId, f => f.IndexFaker + 1)
                .RuleFor(p => p.Name, f => f.Commerce.ProductName())
                .RuleFor(p => p.Description, f => f.Commerce.ProductDescription())
                .RuleFor(p => p.Price, f => f.Finance.Amount(10, 100))
                .Generate(count);
        }

        protected List<Order> GenerateOrders(int customerId, int count)
        {
            var orderId = 1;
            return new Faker<Order>()
                .RuleFor(o => o.OrderId, _ => orderId++)
                .RuleFor(o => o.CustomerId, customerId)
                .RuleFor(o => o.OrderDate, f => f.Date.Past())
                .RuleFor(o => o.TotalPrice, f => f.Finance.Amount(50, 500))
                .RuleFor(o => o.IsFulfilled, f => f.Random.Bool())
                .RuleFor(o => o.OrderProducts, f => new List<OrderProduct>(new Faker<OrderProduct>()
                    .RuleFor(op => op.OrderId, _ => orderId)
                    .RuleFor(op => op.ProductId, f => f.Random.Int(1, 100))
                    .RuleFor(op => op.Quantity, f => f.Random.Int(1, 10))
                    .RuleFor(op => op.Price, f => f.Finance.Amount(10, 100))
                    .RuleFor(op => op.Product, f => new Product
                    {
                        ProductId = f.Random.Int(1, 100),
                        Name = f.Commerce.ProductName(),
                        Description = f.Commerce.ProductDescription(),
                        Price = f.Finance.Amount(10, 100)
                    })
                    .Generate(f.Random.Int(1, 5))))
                .Generate(count);
        }
        protected Order CreateTestOrder(int orderId)
        {
            return new Faker<Order>()
                .RuleFor(c => c.OrderId, orderId)
                .RuleFor(c => c.CustomerId, CustomerId)
                .RuleFor(p => p.TotalPrice, f => f.Finance.Amount(10, 100))
                .RuleFor(c => c.OrderProducts, f => new List<OrderProduct>())
                .Generate();
        }

        protected List<Customer> GenerateCustomersWithOrders(int customerCount, int orderCount, int? customerId = 1)
        {
            var orderId = 1;
            var customerFaker = new Faker<Customer>()
                .RuleFor(c => c.CustomerId, f => customerId ?? f.IndexFaker + 1)
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email())
                .RuleFor(c => c.Orders, f => new List<Order>(new Faker<Order>()
                    .RuleFor(o => o.OrderId, _ => orderId++)
                    .RuleFor(o => o.CustomerId, (f, c) => c.CustomerId)
                    .RuleFor(o => o.TotalPrice, f => f.Finance.Amount(50, 500))
                    .RuleFor(o => o.OrderProducts, (f, o) => new List<OrderProduct>(new Faker<OrderProduct>()
                        .RuleFor(op => op.OrderId, _ => o.OrderId)
                        .RuleFor(op => op.ProductId, f => f.Random.Int(1, 100))
                        .RuleFor(op => op.Quantity, f => f.Random.Int(1, 10))
                        .Generate(f.Random.Int(1, 5)))) // Generate List<OrderProduct> and assign to List<OrderProduct>
                    .Generate(f.Random.Int(1, orderCount)))); // Generate List<Order> and assign to List<Order>

            return customerFaker.Generate(customerCount);
        }

        protected List<Customer> GenerateCustomersWithFulFilledOrders(int customerCount, int orderCount, int? customerId = 1)
        {
            var orderId = 1;
            var customerFaker = new Faker<Customer>()
                .RuleFor(c => c.CustomerId, f => customerId ?? f.IndexFaker + 1)
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email())
                .RuleFor(c => c.Orders, f => new List<Order>(new Faker<Order>()
                    .RuleFor(o => o.OrderId, _ => orderId++)
                    .RuleFor(o => o.CustomerId, (f, c) => c.CustomerId)
                    .RuleFor(o => o.TotalPrice, f => f.Finance.Amount(50, 500))
                    .RuleFor(o => o.IsFulfilled, true)
                    .RuleFor(o => o.OrderProducts, (f, o) => new List<OrderProduct>(new Faker<OrderProduct>()
                        .RuleFor(op => op.OrderId, _ => o.OrderId)
                        .RuleFor(op => op.ProductId, f => f.Random.Int(1, 100))
                        .RuleFor(op => op.Quantity, f => f.Random.Int(1, 10))
                        .Generate(f.Random.Int(1, 5)))) // Generate List<OrderProduct> and assign to List<OrderProduct>
                    .Generate(f.Random.Int(1, orderCount)))); // Generate List<Order> and assign to List<Order>

            return customerFaker.Generate(customerCount);
        }
    }
}
