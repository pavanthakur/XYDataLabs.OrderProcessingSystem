using System.Text.Json;
using Azure.Messaging.ServiceBus;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
public sealed class DlqReplayFunctionOwnershipTests(SqlServerFixture fixture)
{
    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenReplayDisabled_AbandonsMessage_Without_Mutating_State()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Approved, replayAttemptCount: 1);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: false, publisher);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 1);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Abandoned.Should().BeTrue();
        messageActions.Completed.Should().BeFalse();
        messageActions.DeadLetterReason.Should().BeNull();
        publisher.PublishedMessages.Should().BeEmpty();

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Approved);
        persistedQuarantine.ReplayAttemptCount.Should().Be(1);
        persistedRequest.ProcessedUtc.Should().BeNull();
        persistedRequest.LastError.Should().BeNull();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenMessageIsUnapproved_DeadLetters_Without_Publishing()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Approved, replayAttemptCount: 1);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: true, publisher);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(
            request.Id,
            quarantine.Id,
            attemptCount: 1,
            replayApproved: false);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Abandoned.Should().BeFalse();
        messageActions.Completed.Should().BeFalse();
        messageActions.DeadLetterReason.Should().Be("dlq-replay-not-approved");
        publisher.PublishedMessages.Should().BeEmpty();

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Approved);
        persistedRequest.ProcessedUtc.Should().BeNull();
        persistedRequest.LastError.Should().BeNull();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenAttemptCeilingReached_RejectsReplay_And_DeadLetters()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Approved, replayAttemptCount: 5);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: true, publisher, maxReplayAttempts: 5);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 5);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Completed.Should().BeFalse();
        messageActions.DeadLetterReason.Should().Be("Non-replayable after 5 attempt(s).");
        publisher.PublishedMessages.Should().BeEmpty();

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Rejected);
        persistedRequest.ProcessedUtc.Should().BeNull();
        persistedRequest.LastError.Should().Contain("Non-replayable after 5 attempt(s).");
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenApprovedReplayableMessage_Publishes_MarksProcessed_And_Completes()
    {
        await using var seedContext = CreateContext();
        var sourceMessageId = $"source-message-{Guid.NewGuid():N}";
        var quarantine = await AddQuarantineAsync(
            seedContext,
            DlqQuarantineStates.Approved,
            replayAttemptCount: 1,
            sourceMessageId: sourceMessageId,
            failureReason: "transient-dependency",
            failureDescription: "inventory host timeout");
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: true, publisher, maxReplayAttempts: 5);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 1);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Completed.Should().BeTrue();
        messageActions.Abandoned.Should().BeFalse();
        messageActions.DeadLetterReason.Should().BeNull();
        publisher.PublishedMessages.Should().ContainSingle();
        var replayedMessage = publisher.PublishedMessages.Single();
        replayedMessage.Subject.Should().Be(nameof(OrderCreatedV1));
        replayedMessage.ApplicationProperties["ReplayAttempt"].Should().Be(2);
        replayedMessage.ApplicationProperties["AttemptCount"].Should().Be(2);
        replayedMessage.ApplicationProperties["FailureCategory"].Should().Be("replayed");
        replayedMessage.ApplicationProperties["QuarantineId"].Should().Be(quarantine.Id.ToString("D"));
        replayedMessage.ApplicationProperties["ReplaySourceMessageId"].Should().Be(sourceMessageId);
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterReason"].Should().Be("transient-dependency");
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterDescription"].Should().Be("inventory host timeout");

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Replayed);
        persistedQuarantine.ReplayAttemptCount.Should().Be(2);
        persistedRequest.ProcessedUtc.Should().NotBeNull();
        persistedRequest.LastError.Should().BeNull();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task LoadReplayStateAsync_When_Request_Record_Is_Missing_Returns_Null()
    {
        using var provider = BuildProvider(replayEnabled: true, new FakeDlqReplayPublisher());
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var quarantineId = Guid.NewGuid();
        var message = CreateReplayRequestMessage(Guid.NewGuid(), quarantineId, attemptCount: 1);

        var replayState = await function.LoadReplayStateAsync(message, quarantineId.ToString("D"), CancellationToken.None);

        replayState.Should().BeNull();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenReplayRequestAlreadyProcessed_Completes_Without_Republishing()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Replayed, replayAttemptCount: 2);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: DateTime.UtcNow);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: true, publisher, maxReplayAttempts: 5);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 2);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Completed.Should().BeTrue();
        messageActions.Abandoned.Should().BeFalse();
        messageActions.DeadLetterReason.Should().BeNull();
        publisher.PublishedMessages.Should().BeEmpty();
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RunCoreAsync_WhenQuarantineStateIsNotApproved_RejectsReplay_And_DeadLetters()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Quarantined, replayAttemptCount: 1);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        var publisher = new FakeDlqReplayPublisher();
        var messageActions = new FakeReplayMessageActions();
        using var provider = BuildProvider(replayEnabled: true, publisher, maxReplayAttempts: 5);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 1);

        await function.RunCoreAsync(message, messageActions, CancellationToken.None);

        messageActions.Completed.Should().BeFalse();
        messageActions.DeadLetterReason.Should().Be("dlq-replay-not-approved-state");
        publisher.PublishedMessages.Should().BeEmpty();

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Rejected);
        persistedRequest.ProcessedUtc.Should().BeNull();
        persistedRequest.LastError.Should().Contain("Approved state");
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task RejectReplayAsync_Should_Move_Quarantine_To_Rejected_And_Record_The_Error()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Approved, replayAttemptCount: 5);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        using var provider = BuildProvider(replayEnabled: true, new FakeDlqReplayPublisher(), maxReplayAttempts: 5);
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 5);
        var replayState = await function.LoadReplayStateAsync(message, quarantine.Id.ToString("D"), CancellationToken.None);

        await function.RejectReplayAsync(replayState!, "Non-replayable after 5 attempt(s).", "attempt ceiling reached", CancellationToken.None);

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Rejected);
        persistedRequest.ProcessedUtc.Should().BeNull();
        persistedRequest.LastError.Should().Contain("Non-replayable after 5 attempt(s).");
    }

    [Fact]
    [Trait("Category", "InfrastructureIntegration")]
    public async Task MarkReplayProcessedAsync_Should_Advance_Quarantine_And_Request_State_Exactly_Once()
    {
        await using var seedContext = CreateContext();
        var quarantine = await AddQuarantineAsync(seedContext, DlqQuarantineStates.Approved, replayAttemptCount: 1);
        var request = await AddReplayRequestAsync(seedContext, quarantine.Id, processedUtc: null);
        using var provider = BuildProvider(replayEnabled: true, new FakeDlqReplayPublisher());
        var function = new DlqReplayFunction(provider, TimeProvider.System, NullLogger<DlqReplayFunction>.Instance);
        var message = CreateReplayRequestMessage(request.Id, quarantine.Id, attemptCount: 1);
        var replayState = await function.LoadReplayStateAsync(message, quarantine.Id.ToString("D"), CancellationToken.None);

        await function.MarkReplayProcessedAsync(replayState!, CancellationToken.None);

        await using var verifyContext = CreateContext();
        var persistedRequest = await verifyContext.DlqReplayRequests.SingleAsync(item => item.Id == request.Id);
        var persistedQuarantine = await verifyContext.DlqQuarantineRecords.SingleAsync(item => item.Id == quarantine.Id);
        persistedQuarantine.State.Should().Be(DlqQuarantineStates.Replayed);
        persistedQuarantine.ReplayAttemptCount.Should().Be(2);
        persistedRequest.ProcessedUtc.Should().NotBeNull();
        persistedRequest.LastError.Should().BeNull();
    }

    private ServiceProvider BuildProvider(
        bool replayEnabled,
        FakeDlqReplayPublisher publisher,
        int maxReplayAttempts = 5)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IIntegrationEventTypeResolver, IntegrationEventTypeResolver>();
        services.AddSingleton<IDlqReplayPublisher>(publisher);
        services.AddDbContext<OrderProcessingSystemDbContext>(options => options.UseSqlServer(fixture.ConnectionString));
        services.AddSingleton<IOptions<ServiceBusOptions>>(Options.Create(new ServiceBusOptions
        {
            Enabled = true,
            ReplayEnabled = replayEnabled,
            MaxReplayAttempts = maxReplayAttempts,
            TopicName = "order-events",
            ReplayRequestQueueName = "dlq-replay-requests"
        }));

        return services.BuildServiceProvider();
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(fixture.ConnectionString)
            .Options;
        return new OrderProcessingSystemDbContext(options);
    }

    private static ServiceBusReceivedMessage CreateReplayRequestMessage(
        Guid requestId,
        Guid quarantineId,
        int attemptCount,
        bool replayApproved = true,
        string? payload = null)
    {
        return ServiceBusModelFactory.ServiceBusReceivedMessage(
            body: BinaryData.FromString(payload ?? BuildOrderCreatedBody()),
            messageId: requestId.ToString("D"),
            correlationId: Guid.NewGuid().ToString("D"),
            subject: nameof(OrderCreatedV1),
            contentType: "application/json",
            deliveryCount: attemptCount,
            properties: new Dictionary<string, object>
            {
                ["ReplayApproved"] = replayApproved,
                ["ReplayRequestId"] = requestId.ToString("D"),
                ["QuarantineId"] = quarantineId.ToString("D"),
                ["AttemptCount"] = attemptCount,
                ["TenantId"] = "1",
                ["EventType"] = nameof(OrderCreatedV1),
                ["EnvelopeMessageId"] = Guid.NewGuid().ToString("D"),
                ["SchemaVersion"] = 1,
                ["OccurredUtc"] = DateTime.UtcNow.ToString("O"),
                ["CorrelationId"] = Guid.NewGuid().ToString("D"),
                ["CausationId"] = Guid.NewGuid().ToString("D"),
                ["TraceParent"] = "00-11111111111111111111111111111111-2222222222222222-01"
            });
    }

    private static string BuildOrderCreatedBody()
    {
        return JsonSerializer.Serialize(new OrderCreatedV1(
            CustomerId: 11,
            OrderDate: DateTime.UtcNow,
            TotalPrice: 25.50m,
            ProductCount: 2));
    }

    private static async Task<DlqQuarantineRecord> AddQuarantineAsync(
        OrderProcessingSystemDbContext context,
        string state,
        int replayAttemptCount = 1,
        string failureReason = "transient-dependency",
        string? failureDescription = null,
        string? sourceMessageId = null)
    {
        var record = new DlqQuarantineRecord
        {
            Id = Guid.NewGuid(),
            SourceMessageId = sourceMessageId ?? Guid.NewGuid().ToString("D"),
            TenantId = 1,
            EventType = nameof(OrderCreatedV1),
            ContentType = "application/json",
            Body = BuildOrderCreatedBody(),
            ApplicationPropertiesJson = "{}",
            FailureReason = failureReason,
            FailureDescription = failureDescription,
            ReplayAttemptCount = replayAttemptCount,
            State = state,
            CreatedUtc = DateTime.UtcNow,
            ApprovedBy = state == DlqQuarantineStates.Approved || state == DlqQuarantineStates.Replayed ? "operator-1" : null,
            ApprovedUtc = state == DlqQuarantineStates.Approved || state == DlqQuarantineStates.Replayed ? DateTime.UtcNow : null,
            ReplayedUtc = state == DlqQuarantineStates.Replayed ? DateTime.UtcNow : null
        };
        context.DlqQuarantineRecords.Add(record);
        await context.SaveChangesAsync();
        return record;
    }

    private static async Task<DlqReplayRequest> AddReplayRequestAsync(
        OrderProcessingSystemDbContext context,
        Guid quarantineId,
        DateTime? processedUtc)
    {
        var request = new DlqReplayRequest
        {
            Id = Guid.NewGuid(),
            QuarantineId = quarantineId,
            ApprovedBy = "operator-1",
            ApprovedUtc = DateTime.UtcNow,
            PublishedUtc = DateTime.UtcNow,
            ProcessedUtc = processedUtc
        };
        context.DlqReplayRequests.Add(request);
        await context.SaveChangesAsync();
        return request;
    }

    private sealed class FakeReplayMessageActions : IDlqReplayMessageActions
    {
        public bool Abandoned { get; private set; }

        public bool Completed { get; private set; }

        public string? DeadLetterReason { get; private set; }

        public string? DeadLetterDescription { get; private set; }

        public Task AbandonAsync(CancellationToken cancellationToken)
        {
            Abandoned = true;
            return Task.CompletedTask;
        }

        public Task DeadLetterAsync(string reason, string description, CancellationToken cancellationToken)
        {
            DeadLetterReason = reason;
            DeadLetterDescription = description;
            return Task.CompletedTask;
        }

        public Task CompleteAsync(CancellationToken cancellationToken)
        {
            Completed = true;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeDlqReplayPublisher : IDlqReplayPublisher
    {
        public List<ServiceBusMessage> PublishedMessages { get; } = [];

        public Task PublishAsync(ServiceBusMessage message, CancellationToken cancellationToken)
        {
            PublishedMessages.Add(message);
            return Task.CompletedTask;
        }
    }
}
