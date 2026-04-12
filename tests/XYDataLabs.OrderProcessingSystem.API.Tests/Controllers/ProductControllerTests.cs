using Microsoft.AspNetCore.Mvc;
using Moq;
using Xunit;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Products.Queries;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers
{
    public class ProductControllerTests
    {
        private readonly Mock<IDispatcher> _mockDispatcher;
        private readonly ProductController _controller;

        public ProductControllerTests()
        {
            _mockDispatcher = new Mock<IDispatcher>();
            _controller = new ProductController(_mockDispatcher.Object);
        }

        [Fact]
        public async Task GetAllProducts_ReturnsOkResult_WithListOfProducts()
        {
            var products = new List<ProductDto>
            {
                new() { ProductId = 1, Name = "Widget", Price = 25.50m }
            };

            _mockDispatcher.Setup(dispatcher => dispatcher.QueryAsync(It.IsAny<GetAllProductsQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<ProductDto>>.Success(products));

            var result = await _controller.GetAllProducts(CancellationToken.None);

            var okResult = Assert.IsType<OkObjectResult>(result);
            var apiResponse = Assert.IsType<ApiResponse<IEnumerable<ProductDto>>>(okResult.Value);
            Assert.True(apiResponse.Success);
            Assert.Single(apiResponse.Data!);
        }

        [Fact]
        public async Task GetAllProducts_ReturnsNotFound_WhenProductsUnavailable()
        {
            _mockDispatcher.Setup(dispatcher => dispatcher.QueryAsync(It.IsAny<GetAllProductsQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<ProductDto>>.Failure(Error.NotFound));

            var result = await _controller.GetAllProducts(CancellationToken.None);

            Assert.IsType<NotFoundObjectResult>(result);
        }
    }
}