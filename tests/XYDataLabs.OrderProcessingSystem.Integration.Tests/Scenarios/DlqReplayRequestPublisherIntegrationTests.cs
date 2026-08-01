using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
public sealed class DlqReplayRequestPublisherIntegrationTests(SqlServerFixture fixture)
{
    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task PublishPendingAsync_When_Replay_Is_Disabled_Leaves_Approved_Request_Pending()
    {
        await using var seedContext = CreateContext();
        var quarantine = new DlqQuarantineRecord
        {
            Id = Guid.NewGuid(),
            SourceMessageId = Guid.NewGuid().ToString("D"),
            TenantId = 1,
            EventType = "OrderCreatedV1",
            ContentType = "application/json",
            Body = "{}",
            ApplicationPropertiesJson = "{}",
            CorrelationId = Guid.NewGuid().ToString("D"),
            Subject = "OrderCreatedV1",
            FailureReason = "transient-dependency",
            ReplayAttemptCount = 1,
            State = DlqQuarantineStates.Approved,
            CreatedUtc = DateTime.UtcNow,
            ApprovedBy = "operator-1",
            ApprovedUtc = DateTime.UtcNow
        };
        var replayRequest = new DlqReplayRequest
        {
            Id = Guid.NewGuid(),
            QuarantineId = quarantine.Id,
            ApprovedBy = "operator-1",
            ApprovedUtc = DateTime.UtcNow,
            PublishedUtc = null
        };

        seedContext.DlqQuarantineRecords.Add(quarantine);
        seedContext.DlqReplayRequests.Add(replayRequest);
        await seedContext.SaveChangesAsync();

        var scopeFactory = BuildScopeFactory();
        using var publisher = new DlqReplayRequestPublisher(
            scopeFactory,
            Options.Create(new ServiceBusOptions
            {
                Enabled = true,
                ReplayEnabled = false,
                ReplayRequestQueueName = "dlq-replay-requests"
            }),
            NullLogger<DlqReplayRequestPublisher>.Instance);

        await publisher.PublishPendingAsync(CancellationToken.None);

        await using var verifyContext = CreateContext();
        var persisted = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == replayRequest.Id);
        persisted.PublishedUtc.Should().BeNull();
        persisted.LastError.Should().BeNull();
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(fixture.ConnectionString)
            .Options;
        return new OrderProcessingSystemDbContext(options);
    }

    private IServiceScopeFactory BuildScopeFactory()
    {
        var services = new ServiceCollection();
        services.AddDbContext<OrderProcessingSystemDbContext>(options => options.UseSqlServer(fixture.ConnectionString));
        return services.BuildServiceProvider().GetRequiredService<IServiceScopeFactory>();
    }
}
