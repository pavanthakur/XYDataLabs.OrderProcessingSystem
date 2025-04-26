using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moq;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.ControllersTest
{
    public class OrderControllerTests
    {
        private readonly Mock<IOrderService> _mockOrderService;
        private readonly OrderController _orderController;

        public OrderControllerTests()
        {
            _mockOrderService = new Mock<IOrderService>();
            _orderController = new OrderController(_mockOrderService.Object);
        }

        [Fact]
        public async Task CreateOrder_ReturnsCreatedAtActionResult_WithOrderDto()
        {
            // Arrange
            var createOrderRequestDto = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1, 2, 3 }
            };

            var orderDto = new OrderDto
            {
                OrderId = 1,
                CustomerId = 1,
                TotalPrice = 100,
                OrderDate = DateTime.Now,
                IsFulfilled = false,
                OrderProductDtos = new List<OrderProductDto>()
            };

            _mockOrderService.Setup(s => s.CreateOrderAsync(createOrderRequestDto.CustomerId, createOrderRequestDto.ProductIds))
                .ReturnsAsync(orderDto);

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            var createdAtActionResult = Assert.IsType<CreatedAtActionResult>(result.Result);
            Assert.Equal(StatusCodes.Status201Created, createdAtActionResult.StatusCode);
            Assert.Equal(orderDto, createdAtActionResult.Value);
        }

        [Fact]
        public async Task CreateOrder_ReturnsBadRequest_WhenValidationExceptionIsThrown()
        {
            // Arrange
            var createOrderRequestDto = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1, 2, 3 }
            };

            _mockOrderService.Setup(s => s.CreateOrderAsync(createOrderRequestDto.CustomerId, createOrderRequestDto.ProductIds))
                .ThrowsAsync(new FluentValidation.ValidationException("Validation error"));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            var badRequestResult = Assert.IsType<BadRequestObjectResult>(result.Result);
            Assert.Equal(StatusCodes.Status400BadRequest, badRequestResult.StatusCode);
            Assert.Equal("Validation error", badRequestResult.Value);
        }

        [Fact]
        public async Task CreateOrder_ReturnsNotFound_WhenKeyNotFoundExceptionIsThrown()
        {
            // Arrange
            var createOrderRequestDto = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1, 2, 3 }
            };

            _mockOrderService.Setup(s => s.CreateOrderAsync(createOrderRequestDto.CustomerId, createOrderRequestDto.ProductIds))
                .ThrowsAsync(new KeyNotFoundException("Customer not found"));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            var notFoundResult = Assert.IsType<NotFoundObjectResult>(result.Result);
            Assert.Equal(StatusCodes.Status404NotFound, notFoundResult.StatusCode);
            Assert.Equal("Customer not found", notFoundResult.Value);
        }

        [Fact]
        public async Task GetOrderDetailsById_ReturnsOk_WithOrderDto()
        {
            // Arrange
            var orderId = 1;
            var orderDto = new OrderDto
            {
                OrderId = orderId,
                CustomerId = 1,
                TotalPrice = 100,
                OrderDate = DateTime.Now,
                IsFulfilled = false,
                OrderProductDtos = new List<OrderProductDto>()
            };

            _mockOrderService.Setup(s => s.GetOrderDetailsAsync(orderId))
                .ReturnsAsync(orderDto);

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result.Result);
            Assert.Equal(StatusCodes.Status200OK, okResult.StatusCode);
            Assert.Equal(orderDto, okResult.Value);
        }

        [Fact]
        public async Task GetOrderDetailsById_ReturnsNotFound_WhenKeyNotFoundExceptionIsThrown()
        {
            // Arrange
            var orderId = 1;

            _mockOrderService.Setup(s => s.GetOrderDetailsAsync(orderId))
                .ThrowsAsync(new KeyNotFoundException("Order not found"));

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId);

            // Assert
            var notFoundResult = Assert.IsType<NotFoundObjectResult>(result.Result);
            Assert.Equal(StatusCodes.Status404NotFound, notFoundResult.StatusCode);
            Assert.Equal("Order not found", notFoundResult.Value);
        }
    }
}
