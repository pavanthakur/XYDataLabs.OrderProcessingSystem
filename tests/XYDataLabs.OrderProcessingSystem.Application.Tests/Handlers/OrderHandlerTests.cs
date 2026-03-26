using Bogus;
using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Queries;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using Microsoft.EntityFrameworkCore;
using Moq;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Handlers
{
    public class OrderHandlerTests : OrderServiceTestBase
    {
        [Fact]
        public async Task CreateOrderCommand_CustomerNotFound_ReturnsNotFound()
        {
            // Arrange
            var customers = GenerateCustomersWithOrders(1, 1).AsQueryable();
            var mockDbSet = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            var handler = new CreateOrderCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new CreateOrderCommand(2, new List<int> { 1, 2 }));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }

        [Fact]
        public async Task CreateOrderCommand_UnfulfilledOrderExists_ReturnsConflict()
        {
            // Arrange
            var customers = GenerateCustomersWithOrders(1, 1).AsQueryable();
            var mockDbSet = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            var handler = new CreateOrderCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new CreateOrderCommand(1, new List<int> { 1, 2 }));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("Validation");
        }

        [Fact]
        public async Task CreateOrderCommand_ProductNotFound_ReturnsNotFound()
        {
            // Arrange
            var customers = GenerateCustomersWithFulFilledOrders(1, 1).AsQueryable();
            var mockDbSetCustomers = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSetCustomers.Object);

            var products = GenerateProducts(1).AsQueryable();
            var mockDbSetProducts = GetMockDbSet(products);
            MockDbContext.Setup(db => db.Products).Returns(mockDbSetProducts.Object);

            var handler = new CreateOrderCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new CreateOrderCommand(1, new List<int> { 1, 2 }));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }

        [Fact]
        public async Task CreateOrderCommand_ValidOrder_ReturnsOrderDto()
        {
            // Arrange
            var customers = GenerateCustomersWithFulFilledOrders(1, 1).AsQueryable();
            var mockDbSetCustomers = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSetCustomers.Object);

            var products = GenerateProducts(1).AsQueryable();
            var mockDbSetProducts = GetMockDbSet(products);
            MockDbContext.Setup(db => db.Products).Returns(mockDbSetProducts.Object);

            var orders = GenerateOrders(1, 1).AsQueryable();
            var mockDbSetOrders = GetMockDbSet(orders);
            MockDbContext.Setup(db => db.Orders).Returns(mockDbSetOrders.Object);

            MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

            var handler = new CreateOrderCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new CreateOrderCommand(1, new List<int> { 1 }));

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value.Should().NotBeNull();
            result.Value!.CustomerId.Should().Be(CustomerId);
        }

        [Fact]
        public async Task GetOrderDetailsQuery_ReturnsOrderDto()
        {
            // Arrange
            var orderId = 1;
            var order = new Order
            {
                OrderId = orderId,
                CustomerId = CustomerId,
                TotalPrice = 100,
                OrderProducts = new List<OrderProduct>
                {
                    new OrderProduct { ProductId = 1, Quantity = 1 },
                    new OrderProduct { ProductId = 2, Quantity = 1 }
                }
            };

            var mockOrderDbSet = GetMockDbSet(new List<Order> { order }.AsQueryable());
            MockDbContext.Setup(c => c.Orders).Returns(mockOrderDbSet.Object);

            var handler = new GetOrderDetailsQueryHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new GetOrderDetailsQuery(orderId));

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value!.OrderId.Should().Be(orderId);
            result.Value.TotalPrice.Should().Be(100);
        }

        [Fact]
        public async Task GetOrderDetailsQuery_ReturnsNotFound_WhenOrderDoesNotExist()
        {
            // Arrange
            var mockOrderDbSet = GetMockDbSet(new List<Order>().AsQueryable());
            MockDbContext.Setup(c => c.Orders).Returns(mockOrderDbSet.Object);

            var handler = new GetOrderDetailsQueryHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new GetOrderDetailsQuery(999));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }
    }
}
