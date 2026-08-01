using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Commands;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Queries;
using XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using ModuleOrderDto = XYDataLabs.OrderProcessingSystem.Orders.Contracts.OrderDto;
using ModuleOrderProductDto = XYDataLabs.OrderProcessingSystem.Orders.Contracts.OrderProductDto;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moq;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers
{
    public class OrderControllerTests
    {
        private readonly Mock<IDispatcher> _mockDispatcher;
        private readonly Mock<IOrderModuleApi> _mockOrderModuleApi;
        private readonly OrderController _orderController;

        public OrderControllerTests()
        {
            _mockDispatcher = new Mock<IDispatcher>();
            _mockOrderModuleApi = new Mock<IOrderModuleApi>();
            _orderController = new OrderController(_mockDispatcher.Object, _mockOrderModuleApi.Object);
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

            var orderDto = new ModuleOrderDto
            {
                OrderId = 1,
                OrderReferenceId = Guid.NewGuid(),
                CustomerId = 1,
                TotalPrice = 100,
                CurrencyCode = "MXN",
                OrderDate = DateTime.Now,
                IsFulfilled = false,
                OrderProductDtos = new List<ModuleOrderProductDto>()
            };

            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateOrderCommand>(), default))
                .ReturnsAsync(Result<ModuleOrderDto>.Success(orderDto));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto, CancellationToken.None);

            // Assert
            var createdResult = Assert.IsType<CreatedAtActionResult>(result);
            Assert.Equal(StatusCodes.Status201Created, createdResult.StatusCode);
            Assert.Equal(nameof(OrderController.GetOrderDetailsById), createdResult.ActionName);
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
                .ReturnsAsync(Result<ModuleOrderDto>.Failure(Error.Validation));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto, CancellationToken.None);

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
                .ReturnsAsync(Result<ModuleOrderDto>.Failure(Error.NotFound));

            // Act
            var result = await _orderController.CreateOrder(createOrderRequestDto, CancellationToken.None);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
        }

        [Fact]
        public async Task GetOrderDetailsById_ReturnsOk_WithOrderDto()
        {
            // Arrange
            var orderId = 1;
            var orderDto = new ModuleOrderDto
            {
                OrderId = orderId,
                OrderReferenceId = Guid.NewGuid(),
                CustomerId = 1,
                TotalPrice = 100,
                CurrencyCode = "MXN",
                OrderDate = DateTime.Now,
                IsFulfilled = false,
                OrderProductDtos = new List<ModuleOrderProductDto>()
            };

            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetOrderDetailsQuery>(), default))
                .ReturnsAsync(Result<ModuleOrderDto>.Success(orderDto));

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId, CancellationToken.None);

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
                .ReturnsAsync(Result<ModuleOrderDto>.Failure(Error.NotFound));

            // Act
            var result = await _orderController.GetOrderDetailsById(orderId, CancellationToken.None);

        // Assert
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task GetPaymentContext_ReturnsOk_WhenOrderPaymentContextExists()
    {
        var paymentContext = new OrderPaymentContextDto(
            1,
            "ORDER-1",
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            100m,
            "MXN",
            "Created",
            Convert.ToBase64String([1, 2, 3]));

        _mockOrderModuleApi
            .Setup(service => service.GetPaymentContextAsync("ORDER-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync(paymentContext);

        var result = await _orderController.GetPaymentContext("ORDER-1", CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status200OK, okResult.StatusCode);
        Assert.Same(paymentContext, okResult.Value);
    }

    [Fact]
    public async Task GetPaymentContext_ReturnsNotFound_WhenOrderPaymentContextDoesNotExist()
    {
        _mockOrderModuleApi
            .Setup(service => service.GetPaymentContextAsync("ORDER-404", It.IsAny<CancellationToken>()))
            .ReturnsAsync((OrderPaymentContextDto?)null);

        var result = await _orderController.GetPaymentContext("ORDER-404", CancellationToken.None);

        Assert.IsType<NotFoundResult>(result.Result);
    }

    [Fact]
    public async Task GetPaymentContextByOrderReference_ReturnsOk_WhenOrderPaymentContextExists()
    {
        var orderReferenceId = Guid.Parse("11111111-1111-1111-1111-111111111111");
        var paymentContext = new OrderPaymentContextDto(
            1,
            "ORDER-1",
            orderReferenceId,
            100m,
            "MXN",
            "Created",
            Convert.ToBase64String([1, 2, 3]));

        _mockOrderModuleApi
            .Setup(service => service.GetPaymentContextByOrderReferenceAsync(orderReferenceId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(paymentContext);

        var result = await _orderController.GetPaymentContextByOrderReference(orderReferenceId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status200OK, okResult.StatusCode);
        Assert.Same(paymentContext, okResult.Value);
    }
    }
}

