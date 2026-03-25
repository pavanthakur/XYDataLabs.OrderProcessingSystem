using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Queries;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moq;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.ControllersTest
{
    public class OrderControllerTests
    {
        private readonly Mock<IDispatcher> _mockDispatcher;
        private readonly OrderController _orderController;

        public OrderControllerTests()
        {
            _mockDispatcher = new Mock<IDispatcher>();
            _orderController = new OrderController(_mockDispatcher.Object);
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

            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateOrderCommand>(), default))
                .ReturnsAsync(Result<OrderDto>.Success(orderDto));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            var createdAtActionResult = Assert.IsType<CreatedAtActionResult>(result);
            Assert.Equal(StatusCodes.Status201Created, createdAtActionResult.StatusCode);
        }

        [Fact]
        public async Task CreateOrder_ReturnsBadRequest_WhenValidationFails()
        {
            // Arrange
            var createOrderRequestDto = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1, 2, 3 }
            };

            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateOrderCommand>(), default))
                .ReturnsAsync(Result<OrderDto>.Failure(Error.Validation));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            Assert.IsType<BadRequestObjectResult>(result);
        }

        [Fact]
        public async Task CreateOrder_ReturnsNotFound_WhenCustomerNotFound()
        {
            // Arrange
            var createOrderRequestDto = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1, 2, 3 }
            };

            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateOrderCommand>(), default))
                .ReturnsAsync(Result<OrderDto>.Failure(Error.NotFound));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
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

            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetOrderDetailsQuery>(), default))
                .ReturnsAsync(Result<OrderDto>.Success(orderDto));

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            Assert.Equal(StatusCodes.Status200OK, okResult.StatusCode);
        }

        [Fact]
        public async Task GetOrderDetailsById_ReturnsNotFound_WhenOrderNotFound()
        {
            // Arrange
            var orderId = 1;

            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetOrderDetailsQuery>(), default))
                .ReturnsAsync(Result<OrderDto>.Failure(Error.NotFound));

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
        }
    }
}
