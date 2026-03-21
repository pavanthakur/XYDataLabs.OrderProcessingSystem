using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using Microsoft.AspNetCore.Mvc;
using Moq;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.UnitTest.ControllersTest
{
    public class CustomersControllerTest
    {
        private readonly Mock<IDispatcher> _mockDispatcher;
        private readonly CustomerController _controller;

        public CustomersControllerTest()
        {
            _mockDispatcher = new Mock<IDispatcher>();
            _controller = new CustomerController(_mockDispatcher.Object);
        }

        [Fact]
        public async Task GetAllCustomers_ReturnsOkResult_WithListOfCustomers()
        {
            // Arrange
            var customers = new List<CustomerDto> { new() { CustomerId = 1, Name = "John Doe", Email = "test@test1.com" } };
            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetAllCustomersQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<CustomerDto>>.Success(customers));

            // Act
            var result = await _controller.GetAllCustomers();

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            var apiResponse = Assert.IsType<ApiResponse<IEnumerable<CustomerDto>>>(okResult.Value);
            Assert.True(apiResponse.Success);
            Assert.Single(apiResponse.Data!);
        }

        [Fact]
        public async Task GetCustomerById_ReturnsOkResult_WithCustomer()
        {
            // Arrange
            var customer = new CustomerDto { CustomerId = 1, Name = "John Doe", Email = "test@test1.com" };
            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetCustomerWithOrdersQuery>(), default))
                .ReturnsAsync(Result<CustomerDto>.Success(customer));

            // Act
            var result = await _controller.GetCustomerById(1);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            var apiResponse = Assert.IsType<ApiResponse<CustomerDto>>(okResult.Value);
            Assert.True(apiResponse.Success);
            Assert.Equal(1, apiResponse.Data!.CustomerId);
        }

        [Fact]
        public async Task GetCustomerById_ReturnsNotFound_WhenCustomerNotFound()
        {
            // Arrange
            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetCustomerWithOrdersQuery>(), default))
                .ReturnsAsync(Result<CustomerDto>.Failure(Error.NotFound));

            // Act
            var result = await _controller.GetCustomerById(1);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
        }

        [Fact]
        public async Task CreateCustomer_ReturnsCreatedAtActionResult()
        {
            // Arrange
            var createCustomerRequest = new CreateCustomerRequestDto { Name = "John Doe", Email = "test@test1.com" };
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateCustomerCommand>(), default))
                .ReturnsAsync(Result<int>.Success(1));

            // Act
            var result = await _controller.CreateCustomer(createCustomerRequest);

            // Assert
            var createdAtActionResult = Assert.IsType<CreatedAtActionResult>(result);
            Assert.Equal(nameof(CustomerController.CreateCustomer), createdAtActionResult.ActionName);
        }

        [Fact]
        public async Task CreateCustomer_ReturnsBadRequest_WhenValidationFails()
        {
            // Arrange
            var createCustomerRequest = new CreateCustomerRequestDto { Name = "", Email = "invalid" };
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<CreateCustomerCommand>(), default))
                .ReturnsAsync(Result<int>.Failure(Error.Validation));

            // Act
            var result = await _controller.CreateCustomer(createCustomerRequest);

            // Assert
            Assert.IsType<BadRequestObjectResult>(result);
        }

        [Fact]
        public async Task GetAllCustomersByName_ReturnsOkResult_WithListOfCustomers()
        {
            // Arrange
            var customers = new List<CustomerDto> { new() { CustomerId = 1, Name = "John Doe", Email = "test@test1.com" } };
            _mockDispatcher.Setup(d => d.QueryAsync(It.IsAny<GetCustomersByNameQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<CustomerDto>>.Success(customers));

            // Act
            var result = await _controller.GetAllCustomersByName("John");

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            var apiResponse = Assert.IsType<ApiResponse<IEnumerable<CustomerDto>>>(okResult.Value);
            Assert.True(apiResponse.Success);
            Assert.Single(apiResponse.Data!);
        }

        [Fact]
        public async Task UpdateCustomer_ReturnsOkResult()
        {
            // Arrange
            var updateCustomerRequest = new UpdateCustomerRequestDto { Name = "John Doe", Email = "test@test1.com" };
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<UpdateCustomerCommand>(), default))
                .ReturnsAsync(Result<int>.Success(1));

            // Act
            var result = await _controller.UpdateCustomer(1, updateCustomerRequest);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            Assert.Equal(200, okResult.StatusCode);
        }

        [Fact]
        public async Task UpdateCustomer_ReturnsNotFound_WhenCustomerNotFound()
        {
            // Arrange
            var updateCustomerRequest = new UpdateCustomerRequestDto { Name = "John Doe", Email = "test@test1.com" };
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<UpdateCustomerCommand>(), default))
                .ReturnsAsync(Result<int>.Failure(Error.NotFound));

            // Act
            var result = await _controller.UpdateCustomer(1, updateCustomerRequest);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
        }

        [Fact]
        public async Task DeleteCustomer_ReturnsOkResult()
        {
            // Arrange
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<DeleteCustomerCommand>(), default))
                .ReturnsAsync(Result<bool>.Success(true));

            // Act
            var result = await _controller.DeleteCustomer(1);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            Assert.Equal(200, okResult.StatusCode);
        }

        [Fact]
        public async Task DeleteCustomer_ReturnsNotFound_WhenCustomerNotFound()
        {
            // Arrange
            _mockDispatcher.Setup(d => d.SendAsync(It.IsAny<DeleteCustomerCommand>(), default))
                .ReturnsAsync(Result<bool>.Failure(Error.NotFound));

            // Act
            var result = await _controller.DeleteCustomer(1);

            // Assert
            Assert.IsType<NotFoundObjectResult>(result);
        }
    }
}