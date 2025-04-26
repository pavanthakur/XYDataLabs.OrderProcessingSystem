using AutoMapper;
using Bogus;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Application.Services;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Moq;
using Serilog.Core;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.TestBase
{
    public class CustomerServiceTestBase : OrderProcessingSystemTestBase<CustomerService>
    {
        protected readonly ICustomerService _customerService;

        public CustomerServiceTestBase()
        {
            _customerService = new CustomerService(MockDbContext.Object, MockLogger.Object, MockMapper.Object);
        }

        /// <summary>
        ///  Setup common test data for CustomerService
        /// </summary>
        public override void SetupTestBase()
        {
            //SetupCustomerData();
        }
        protected List<Customer> GenerateCustomers(int count)
        {
            return new Faker<Customer>()
                .RuleFor(c => c.CustomerId, f => f.IndexFaker + 1)
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email())
                .Generate(count);
        }

        // Fake Data Generation
        protected List<CreateCustomerRequestDto> GenerateNewCustomerRequestDto(int count)
        {
            var faker = new Faker<CreateCustomerRequestDto>()
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email());

            return faker.Generate(count);
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
                    //.RuleFor(o => o.OrderProducts, (f, o) => new List<OrderProduct>(new Faker<OrderProduct>()
                    //    .RuleFor(op => op.OrderId, _ => o.OrderId)
                    //    .RuleFor(op => op.ProductId, f => f.Random.Int(1, 100))
                    //    .RuleFor(op => op.Quantity, f => f.Random.Int(1, 10))
                    //    .Generate(f.Random.Int(1, 5)))) // Generate List<OrderProduct> and assign to List<OrderProduct>
                    .Generate(f.Random.Int(1, orderCount)))); // Generate List<Order> and assign to List<Order>

            return customerFaker.Generate(customerCount);
        }
    }
}
