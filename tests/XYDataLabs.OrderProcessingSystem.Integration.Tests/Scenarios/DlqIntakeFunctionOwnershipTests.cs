using Azure.Messaging.ServiceBus;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
public sealed class DlqIntakeFunctionOwnershipTests(SqlServerFixture fixture)
{
    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_When_Message_Is_First_Seen_Persists_Quarantine_And_Completes()
    {
        await using var context = CreateContext();
        var function = new DlqIntakeFunction(context, TimeProvider.System, NullLogger<DlqIntakeFunction>.Instance);
        var messageActions = new FakeIntakeMessageActions();
        var messageId = Guid.NewGuid().ToString("D");
        var message = CreateDeadLetterMessage(messageId, tenantId: 42, attemptCount: 3, failureCategory: "transient-dependency");

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Completed.Should().BeTrue();

        await using var verifyContext = CreateContext();
        var persisted = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.SourceMessageId == messageId);
        persisted.TenantId.Should().Be(42);
        persisted.EventType.Should().Be("OrderCreatedV1");
        persisted.State.Should().Be(DlqQuarantineStates.Quarantined);
        persisted.ReplayAttemptCount.Should().Be(3);
        persisted.FailureReason.Should().Be("quarantined-transient-dependency");
        persisted.FailureDescription.Should().BeNull();
        persisted.Subject.Should().Be("OrderCreatedV1");
        persisted.CorrelationId.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_When_Message_Has_Already_Been_Quarantined_Does_Not_Create_A_Duplicate()
    {
        var messageId = Guid.NewGuid().ToString("D");

        await using (var seedContext = CreateContext())
        {
            seedContext.DlqQuarantineRecords.Add(new DlqQuarantineRecord
            {
                Id = Guid.NewGuid(),
                SourceMessageId = messageId,
                TenantId = 7,
                EventType = "OrderCreatedV1",
                ContentType = "application/json",
                Body = "{}",
                ApplicationPropertiesJson = "{}",
                CorrelationId = Guid.NewGuid().ToString("D"),
                Subject = "OrderCreatedV1",
                FailureReason = "deadlettered",
                FailureDescription = "existing quarantine",
                ReplayAttemptCount = 2,
                State = DlqQuarantineStates.Quarantined,
                CreatedUtc = DateTime.UtcNow
            });
            await seedContext.SaveChangesAsync();
        }

        await using (var context = CreateContext())
        {
            var function = new DlqIntakeFunction(context, TimeProvider.System, NullLogger<DlqIntakeFunction>.Instance);
            var messageActions = new FakeIntakeMessageActions();
            var message = CreateDeadLetterMessage(messageId, tenantId: 7, attemptCount: 4, failureCategory: "transient-dependency");

            await function.RunCoreAsync(message, messageActions, CancellationToken.None);

            messageActions.Completed.Should().BeTrue();
        }

        await using var verifyContext = CreateContext();
        var records = await verifyContext.DlqQuarantineRecords
            .Where(item => item.SourceMessageId == messageId)
            .ToListAsync();
        records.Should().ContainSingle();
        records.Single().ReplayAttemptCount.Should().Be(2);
        records.Single().FailureDescription.Should().Be("existing quarantine");
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(fixture.ConnectionString)
            .Options;
        return new OrderProcessingSystemDbContext(options);
    }

    private static ServiceBusReceivedMessage CreateDeadLetterMessage(
        string messageId,
        int tenantId,
        int attemptCount,
        string failureCategory)
    {
        return ServiceBusModelFactory.ServiceBusReceivedMessage(
            body: BinaryData.FromString("{\"event\":\"order-created\"}"),
            messageId: messageId,
            correlationId: Guid.NewGuid().ToString("D"),
            subject: "OrderCreatedV1",
            contentType: "application/json",
            deliveryCount: attemptCount,
            properties: new Dictionary<string, object>
            {
                ["TenantId"] = tenantId,
                ["EventType"] = "OrderCreatedV1",
                ["AttemptCount"] = attemptCount,
                ["FailureCategory"] = failureCategory
            });
    }

    private sealed class FakeIntakeMessageActions : IDlqIntakeMessageActions
    {
        public bool Completed { get; private set; }

        public Task CompleteAsync(CancellationToken cancellationToken)
        {
            Completed = true;
            return Task.CompletedTask;
        }
    }
}
