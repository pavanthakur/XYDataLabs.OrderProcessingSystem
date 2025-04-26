using Bogus;
using Castle.Core.Resource;
using FluentValidation;
using FluentValidation.Results;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.UnitTest.TestBase;
using Microsoft.EntityFrameworkCore;
using Moq;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Xunit;
using ValidationResult = FluentValidation.Results.ValidationResult;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.ServicesTest
{
    public class OrderServiceUnitTest : OrderServiceTestBase
    {

        [Fact]
        public async Task CreateOrderAsync_CustomerNotFound_ThrowsKeyNotFoundException()
        {
            // Arrange
            var customers = GenerateCustomersWithOrders(1, 1).AsQueryable();
            var mockDbSet = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            // Act & Assert
            await Assert.ThrowsAsync<KeyNotFoundException>(() => _orderService.CreateOrderAsync(2, new List<int> { 1, 2 }));
        }

        [Fact]
        public async Task CreateOrderAsync_UnfulfilledOrderExists_ThrowsValidationException()
        {
            // Arrange
            var customers = GenerateCustomersWithOrders(1, 1).AsQueryable();
            var mockDbSet = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            // Act & Assert
            await Assert.ThrowsAsync<FluentValidation.ValidationException>(() => _orderService.CreateOrderAsync(1, new List<int> { 1, 2 }));
        }

        [Fact]
        public async Task CreateOrderAsync_ProductNotFound_ThrowsKeyNotFoundException()
        {
            // Arrange
            var customers = GenerateCustomersWithFulFilledOrders(1, 1).AsQueryable();
            var mockDbSetCustomers = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSetCustomers.Object);

            var products = GenerateProducts(1).AsQueryable();
            var mockDbSetProducts = GetMockDbSet(products);
            MockDbContext.Setup(db => db.Products).Returns(mockDbSetProducts.Object);

            // Act & Assert
            await Assert.ThrowsAsync<KeyNotFoundException>(() => _orderService.CreateOrderAsync(1, new List<int> { 1, 2 }));
        }

        [Fact]
        public async Task CreateOrderAsync_InvalidOrder_ThrowsValidationException()
        {
            // Arrange
            const string OrderValidationErrorMessage = "Customer cannot place a new order until their previous order is fulfilled.";
            var customers = GenerateCustomersWithFulFilledOrders(1, 1).AsQueryable();
            var mockDbSetCustomers = GetMockDbSet(customers);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSetCustomers.Object);

            var products = GenerateProducts(1).AsQueryable();
            var mockDbSetProducts = GetMockDbSet(products);
            MockDbContext.Setup(db => db.Products).Returns(mockDbSetProducts.Object);

            MockOrderValidator.Setup(v => v.ValidateAsync(It.IsAny<Order>(), default))
                .ReturnsAsync(new ValidationResult(new List<ValidationFailure> { new ValidationFailure("Order", OrderValidationErrorMessage) }));

            // Act & Assert
            var exception = await Assert.ThrowsAsync<FluentValidation.ValidationException>(() => _orderService.CreateOrderAsync(1, new List<int> { 1 }));
            Assert.NotNull(exception);
            Assert.IsType<FluentValidation.ValidationException>(exception);
            Assert.NotNull(exception.Errors);
            Assert.Single(exception.Errors);
            Assert.Equal(OrderValidationErrorMessage, exception.Errors.First().ErrorMessage);
        }

        [Fact]
        public async Task CreateOrderAsync_ValidOrder_ReturnsOrderDto()
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

            var orderDto = new OrderDto
            {
                OrderId = orders.First().OrderId,
                OrderDate = orders.First().OrderDate,
                CustomerId = CustomerId,
                TotalPrice = orders.First().TotalPrice,
                OrderProductDtos = orders.First().OrderProducts.Select(op => new OrderProductDto
                {
                    ProductId = op.Product?.ProductId ?? 0, 
                    Quantity = op.Quantity,
                    Price = op.Price,
                    ProductDto = op.Product != null ? new ProductDto
                    {
                        ProductId = op.Product.ProductId,
                        Name = op.Product.Name,
                        Description = op.Product.Description,
                        Price = op.Product.Price
                    } : null
                }).ToList()
            };

            MockMapper.Setup(m => m.Map<OrderDto>(It.IsAny<Order>())).Returns(orderDto);
            MockOrderValidator.Setup(v => v.ValidateAsync(It.IsAny<Order>(), default))
                .ReturnsAsync(new ValidationResult());

            // Act
            var result = await _orderService.CreateOrderAsync(1, new List<int> { 1 });

            // Assert
            Assert.NotNull(result);
            Assert.Equal(orderDto.CustomerId, result.CustomerId);
            Assert.NotNull(result.OrderProductDtos);
            Assert.Equal(orderDto.OrderProductDtos?.Count ?? 0, result.OrderProductDtos?.Count ?? 0);
            Assert.NotNull(result.OrderProductDtos?.First().ProductDto);
            Assert.Equal(orderDto.OrderProductDtos?.First().ProductDto, result.OrderProductDtos?.First().ProductDto);
        }

        [Fact]
        public async Task GetOrderDetailsAsync_ReturnsOrderDto()
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

            var orderDto = new OrderDto
            {
                OrderId = orderId,
                CustomerId = CustomerId,
                TotalPrice = 100,
                OrderProductDtos = order.OrderProducts.Select(op => new OrderProductDto
                {
                    ProductId = op.ProductId,
                    Price = op.Price,
                    Quantity = op.Quantity
                }).ToList()
            };

            MockMapper.Setup(m => m.Map<OrderDto>(It.IsAny<Order>())).Returns(orderDto);

            // Act
            var result = await _orderService.GetOrderDetailsAsync(orderId);

            // Assert
            Assert.NotNull(result);
            Assert.Equal(orderDto.OrderId, result.OrderId);
            Assert.Equal(orderDto.TotalPrice, result.TotalPrice);
        }
    }
}