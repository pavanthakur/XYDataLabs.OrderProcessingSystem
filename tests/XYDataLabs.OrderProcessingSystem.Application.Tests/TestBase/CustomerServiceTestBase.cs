using Bogus;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

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
                .RuleFor(c => c.CustomerId, (f, _) => new CustomerId(f.IndexFaker + 1))
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
            var customers = new List<Customer>();
            var nextOrderId = 1;

            for (var customerIndex = 0; customerIndex < customerCount; customerIndex++)
            {
                var resolvedCustomerId = customerId ?? customerIndex + 1;
                var orders = new List<Order>();

                for (var orderIndex = 0; orderIndex < orderCount; orderIndex++)
                {
                    var product = new Product
                    {
                        ProductId = orderIndex + 1,
                        Name = $"Product {orderIndex + 1}",
                        Description = $"Description {orderIndex + 1}",
                        Price = 25m + orderIndex
                    };

                    var orderResult = Order.Create(resolvedCustomerId, new[] { product }, DateTime.UtcNow.AddDays(-1));
                    if (orderResult.IsFailure || orderResult.Value is null)
                    {
                        throw new InvalidOperationException(orderResult.Error.Description);
                    }

                    var order = orderResult.Value;
                    order.OrderId = nextOrderId++;
                    orders.Add(order);
                }

                customers.Add(new Customer
                {
                    CustomerId = resolvedCustomerId,
                    Name = $"Customer {resolvedCustomerId}",
                    Email = $"customer{resolvedCustomerId}@test.com",
                    Orders = orders
                });
            }

            return customers;
        }
    }
}
