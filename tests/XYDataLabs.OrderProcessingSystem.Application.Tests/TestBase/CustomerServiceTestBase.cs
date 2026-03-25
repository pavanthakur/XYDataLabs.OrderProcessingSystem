using AutoMapper;
using Bogus;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.Extensions.Logging;
using Moq;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase
{
    public class CustomerServiceTestBase : OrderProcessingSystemTestBase<CreateCustomerCommandHandler>
    {
        public CustomerServiceTestBase()
        {
        }

        /// <summary>
        ///  Setup common test data for Customer handlers
        /// </summary>
        public override void SetupTestBase()
        {
        }

        protected List<Customer> GenerateCustomers(int count)
        {
            return new Faker<Customer>()
                .RuleFor(c => c.CustomerId, f => f.IndexFaker + 1)
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email())
                .Generate(count);
        }

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
                    .Generate(f.Random.Int(1, orderCount))));

            return customerFaker.Generate(customerCount);
        }
    }
}
