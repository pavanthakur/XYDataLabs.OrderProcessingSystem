using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
public sealed class DlqReplayApprovalIntegrationTests(SqlServerFixture fixture)
{
    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task ApproveAsync_Persists_Approval_And_One_Replay_Request_Atomically()
    {
        await using var context = CreateContext();
        var quarantine = await AddQuarantineAsync(context);
        var service = new DlqReplayApprovalService(context, TimeProvider.System);

        var result = await service.ApproveAsync(quarantine.Id, "operator-1", CancellationToken.None);

        result.Should().NotBeNull();
        result!.AlreadyApproved.Should().BeFalse();
        var persisted = await context.DlqQuarantineRecords
            .AsNoTracking()
            .SingleAsync(item => item.Id == quarantine.Id);
        persisted.State.Should().Be(DlqQuarantineStates.Approved);
        persisted.ApprovedBy.Should().Be("operator-1");
        (await context.DlqReplayRequests.CountAsync(item => item.QuarantineId == quarantine.Id))
            .Should()
            .Be(1);
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task ApproveAsync_When_Repeated_Returns_Existing_Request_Without_Duplicate()
    {
        await using var context = CreateContext();
        var quarantine = await AddQuarantineAsync(context);
        var service = new DlqReplayApprovalService(context, TimeProvider.System);

        var first = await service.ApproveAsync(quarantine.Id, "operator-1", CancellationToken.None);
        var second = await service.ApproveAsync(quarantine.Id, "operator-2", CancellationToken.None);

        second.Should().NotBeNull();
        second!.AlreadyApproved.Should().BeTrue();
        second.ReplayRequestId.Should().Be(first!.ReplayRequestId);
        (await context.DlqReplayRequests.CountAsync(item => item.QuarantineId == quarantine.Id))
            .Should()
            .Be(1);
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(fixture.ConnectionString)
            .Options;
        return new OrderProcessingSystemDbContext(options);
    }

    private static async Task<DlqQuarantineRecord> AddQuarantineAsync(
        OrderProcessingSystemDbContext context)
    {
        var record = new DlqQuarantineRecord
        {
            Id = Guid.NewGuid(),
            SourceMessageId = Guid.NewGuid().ToString("D"),
            TenantId = 1,
            EventType = "OrderCreatedV1",
            ContentType = "application/json",
            Body = "{}",
            ApplicationPropertiesJson = "{}",
            FailureReason = "transient-dependency",
            ReplayAttemptCount = 1,
            State = DlqQuarantineStates.Quarantined,
            CreatedUtc = DateTime.UtcNow
        };
        context.DlqQuarantineRecords.Add(record);
        await context.SaveChangesAsync();
        return record;
    }
}
