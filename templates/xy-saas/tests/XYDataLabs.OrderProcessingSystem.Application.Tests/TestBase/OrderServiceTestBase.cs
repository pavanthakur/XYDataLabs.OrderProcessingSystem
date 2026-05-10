using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase
{
    public abstract class OrderServiceTestBase : OrderProcessingSystemTestBase<CreateOrderCommandHandler>
    {
        protected readonly int CustomerId = 1;
        protected readonly List<int> ProductIds;
        protected readonly Customer Customer;
        protected readonly List<Product> Products;

        protected OrderServiceTestBase()
        {
            Customer = GenerateCustomer();
            Products = GenerateProducts(3);
            ProductIds = Products.Select(p => p.ProductId.Value).ToList();
        }

        protected Customer GenerateCustomer()
        {
            return new Customer
            {
                CustomerId = CustomerId,
                Name = "Test Customer",
                Email = "customer@test.com",
                Orders = new List<Order>()
            };
        }

        protected List<Product> GenerateProducts(int count)
        {
            var products = new List<Product>();

            for (var index = 1; index <= count; index++)
            {
                products.Add(new Product
                {
                    ProductId = index,
                    Name = $"Product {index}",
                    Description = $"Description {index}",
                    Price = 10m * index
                });
            }

            return products;
        }

        protected List<Order> GenerateOrders(int customerId, int count)
        {
            var orders = new List<Order>();

            for (var index = 1; index <= count; index++)
            {
                var order = CreateOrder(customerId, GenerateProducts(1), index % 2 == 0 ? OrderStatus.Delivered : OrderStatus.Created, index);
                orders.Add(order);
            }

            return orders;
        }

        protected Order CreateTestOrder(int orderId)
        {
            return CreateOrder(CustomerId, GenerateProducts(1), OrderStatus.Created, orderId);
        }

        protected List<Customer> GenerateCustomersWithOrders(int customerCount, int orderCount, int? customerId = 1)
        {
            return GenerateCustomers(customerCount, orderCount, customerId, OrderStatus.Created);
        }

        protected List<Customer> GenerateCustomersWithFulFilledOrders(int customerCount, int orderCount, int? customerId = 1)
        {
            return GenerateCustomers(customerCount, orderCount, customerId, OrderStatus.Delivered);
        }

        private List<Customer> GenerateCustomers(int customerCount, int orderCount, int? customerId, OrderStatus orderStatus)
        {
            var customers = new List<Customer>();
            var nextOrderId = 1;

            for (var customerIndex = 0; customerIndex < customerCount; customerIndex++)
            {
                var resolvedCustomerId = customerId ?? customerIndex + 1;
                var orders = new List<Order>();

                for (var orderIndex = 0; orderIndex < orderCount; orderIndex++)
                {
                    orders.Add(CreateOrder(resolvedCustomerId, GenerateProducts(1), orderStatus, nextOrderId++));
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

        private static Order CreateOrder(int customerId, IReadOnlyCollection<Product> products, OrderStatus status, int orderId)
        {
            var orderResult = Order.Create(customerId, products, DateTime.UtcNow.AddDays(-1));
            if (orderResult.IsFailure || orderResult.Value is null)
            {
                throw new InvalidOperationException(orderResult.Error.Description);
            }

            var order = orderResult.Value;
            order.OrderId = orderId;

            ApplyStatus(order, status);
            return order;
        }

        private static void ApplyStatus(Order order, OrderStatus status)
        {
            switch (status)
            {
                case OrderStatus.Created:
                    return;
                case OrderStatus.Paid:
                    order.Pay();
                    return;
                case OrderStatus.Shipped:
                    order.Pay();
                    order.Ship();
                    return;
                case OrderStatus.Delivered:
                    order.Pay();
                    order.Ship();
                    order.Deliver();
                    return;
                case OrderStatus.Cancelled:
                    order.Cancel();
                    return;
                default:
                    throw new ArgumentOutOfRangeException(nameof(status), status, null);
            }
        }
    }
}
