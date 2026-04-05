using Microsoft.AspNetCore.Mvc;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers
{
    public class AuditControllerTests
    {
        private readonly Mock<IDispatcher> _mockDispatcher;
        private readonly AuditController _controller;

        public AuditControllerTests()
        {
            _mockDispatcher = new Mock<IDispatcher>();
            _controller = new AuditController(_mockDispatcher.Object);
        }

        [Fact]
        public async Task GetAuditHistory_ReturnsOkResult_WithAuditEntries()
        {
            var auditEntries = new[]
            {
                new AuditLogDto { EntityName = "Customer", EntityId = "CustomerId=7", Operation = "Created" }
            };

            _mockDispatcher.Setup(dispatcher => dispatcher.QueryAsync(It.IsAny<GetAuditHistoryQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<AuditLogDto>>.Success(auditEntries));

            var result = await _controller.GetAuditHistory("Customer", "CustomerId=7", CancellationToken.None);

            var okResult = Assert.IsType<OkObjectResult>(result);
            var apiResponse = Assert.IsType<ApiResponse<IEnumerable<AuditLogDto>>>(okResult.Value);
            Assert.True(apiResponse.Success);
            Assert.Single(apiResponse.Data!);
        }

        [Fact]
        public async Task GetAuditHistory_ReturnsBadRequest_WhenQueryValidationFails()
        {
            _mockDispatcher.Setup(dispatcher => dispatcher.QueryAsync(It.IsAny<GetAuditHistoryQuery>(), default))
                .ReturnsAsync(Result<IEnumerable<AuditLogDto>>.Failure(Error.Validation));

            var result = await _controller.GetAuditHistory(string.Empty, string.Empty, CancellationToken.None);

            Assert.IsType<BadRequestObjectResult>(result);
        }
    }
}