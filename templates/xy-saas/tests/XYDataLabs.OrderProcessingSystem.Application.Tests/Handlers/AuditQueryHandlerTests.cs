using FluentAssertions;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Handlers
{
    public class AuditQueryHandlerTests : OrderProcessingSystemTestBase<GetAuditHistoryQueryHandler>
    {
        [Fact]
        public async Task HandleAsync_ReturnsAuditHistory_ForMatchingEntity()
        {
            var entityId = "CustomerId=42";
            var auditLogs = new List<AuditLog>
            {
                new() { EntityName = "Customer", EntityId = entityId, Operation = "Created", CreatedDate = new DateTime(2026, 4, 4, 9, 0, 0, DateTimeKind.Utc), NewValues = "{\"Name\":\"Before\"}" },
                new() { EntityName = "Customer", EntityId = entityId, Operation = "Updated", CreatedDate = new DateTime(2026, 4, 4, 10, 0, 0, DateTimeKind.Utc), OldValues = "{\"Name\":\"Before\"}", NewValues = "{\"Name\":\"After\"}" },
                new() { EntityName = "Order", EntityId = "OrderId=99", Operation = "Created", CreatedDate = new DateTime(2026, 4, 4, 11, 0, 0, DateTimeKind.Utc) }
            }.AsQueryable();

            var mockDbSet = GetMockDbSet(auditLogs);
            MockDbContext.Setup(db => db.AuditLogs).Returns(mockDbSet.Object);

            var handler = new GetAuditHistoryQueryHandler(MockDbContext.Object);

            var result = await handler.HandleAsync(new GetAuditHistoryQuery("Customer", entityId));

            result.IsSuccess.Should().BeTrue();
            result.Value.Should().HaveCount(2);
            result.Value!.Select(item => item.Operation).Should().ContainInOrder("Updated", "Created");
        }

        [Fact]
        public async Task HandleAsync_ReturnsValidationFailure_WhenSelectorIsMissing()
        {
            var handler = new GetAuditHistoryQueryHandler(MockDbContext.Object);

            var result = await handler.HandleAsync(new GetAuditHistoryQuery(string.Empty, string.Empty));

            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("Validation");
        }
    }
}