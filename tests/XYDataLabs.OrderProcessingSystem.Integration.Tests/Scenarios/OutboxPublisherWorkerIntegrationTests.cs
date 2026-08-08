using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class OutboxPublisherWorkerIntegrationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public OutboxPublisherWorkerIntegrationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(
            _fixture.ConnectionString,
            _fixture.DedicatedDbConnectionString,
            enableBackgroundWorkers: false);
        _ = _factory.CreateClient(); // Force host initialization
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task Worker_Should_Process_Tenant_Scoped_Outbox_Message_And_Set_ProcessedAt()
    {
        // Arrange
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);
        var orderReferenceId = Guid.NewGuid();

        var payload = JsonSerializer.Serialize(new OrderCreatedV1(
            1,
            DateTime.UtcNow,
            100m,
            2,
            orderReferenceId,
            "MXN"));

        var messageId = Guid.NewGuid();

        await _factory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext => {
            dbContext.OutboxMessages.Add(new OutboxMessage
            {
                Id = 0,
                MessageId = messageId,
                EventType = "OrderCreatedV1",
                SchemaVersion = 1,
                OccurredUtc = DateTime.UtcNow,
                Payload = payload,
                ProcessedAt = null,
                PublishAttempts = 0,
                LastError = null,
                TenantId = tenant.TenantId
            });
            await dbContext.SaveChangesAsync();
                return true;
        });

        // Act
        // Background polling is intentionally exercised by the restart/replay test below.
        // This assertion is made deterministic by invoking one explicit worker pass here,
        // so suite-level scheduling jitter does not create a flaky proof gate.
        await InvokeOutboxWorkerAsync(_factory.Services);

        // Assert
        var processedMessage = await _factory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
        {
            return await dbContext.OutboxMessages.FirstOrDefaultAsync(m => m.MessageId == messageId);
        });

        processedMessage.Should().NotBeNull();
        processedMessage!.ProcessedAt.Should().NotBeNull(
            "the outbox worker should pick up the tenant-scoped message and set ProcessedAt. " +
            "PublishAttempts={0}, LastError={1}",
            processedMessage.PublishAttempts,
            processedMessage.LastError ?? "<null>");
    }

    [Fact]
    public async Task Worker_Restart_Should_Replay_Previously_Unprocessed_Outbox_Message()
    {
        var firstFactory = new ServiceOverrideIntegrationTestFactory(
            _fixture.ConnectionString,
            services => services.AddScoped<IEventPublisher, ThrowingEventPublisher>(),
            enableBackgroundWorkers: false,
            dedicatedConnectionString: _fixture.DedicatedDbConnectionString);
        _ = firstFactory.CreateClient();

        try
        {
            var tenant = await IntegrationTestData.CreateTenantAsync(firstFactory);
            var messageId = Guid.NewGuid();
            var orderReferenceId = Guid.NewGuid();

            await firstFactory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), async dbContext =>
            {
                dbContext.OutboxMessages.Add(new OutboxMessage
                {
                    MessageId = messageId,
                    EventType = nameof(OrderCreatedV1),
                    SchemaVersion = 1,
                    OccurredUtc = DateTime.UtcNow,
                    Payload = JsonSerializer.Serialize(new OrderCreatedV1(
                        1,
                        DateTime.UtcNow,
                        10m,
                        1,
                        orderReferenceId,
                        "MXN")),
                    PublishAttempts = 0,
                    TenantId = tenant.TenantId
                });

                await dbContext.SaveChangesAsync();
                return true;
            });

            await InvokeOutboxWorkerAsync(firstFactory.Services);

            var failedAttemptMessage = await firstFactory.ExecuteTenantDbContextAsync(tenant.ToTenantContext(), dbContext =>
                dbContext.OutboxMessages.SingleAsync(message => message.MessageId == messageId));

            failedAttemptMessage.ProcessedAt.Should().BeNull();
            failedAttemptMessage.PublishAttempts.Should().Be(1);
            failedAttemptMessage.LastError.Should().NotBeNullOrWhiteSpace();

            await firstFactory.DisposeAsync();

            await using var restartedFactory = new IntegrationTestWebAppFactory(
                _fixture.ConnectionString,
                _fixture.DedicatedDbConnectionString,
                enableBackgroundWorkers: true);
            _ = restartedFactory.CreateClient();

            var replayedMessage = await WaitForProcessedMessageAsync(restartedFactory, tenant.ToTenantContext(), messageId);

            replayedMessage.ProcessedAt.Should().NotBeNull();
            replayedMessage.PublishAttempts.Should().BeGreaterThanOrEqualTo(2);
            replayedMessage.LastError.Should().BeNull();
        }
        finally
        {
            await firstFactory.DisposeAsync();
        }
    }

    private static async Task<OutboxMessage> WaitForProcessedMessageAsync(
        IntegrationTestWebAppFactory factory,
        XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy.TenantContext tenantContext,
        Guid messageId)
    {
        OutboxMessage? lastObservedMessage = null;
        var timeoutAt = DateTime.UtcNow.AddSeconds(15);

        while (DateTime.UtcNow < timeoutAt)
        {
            var message = await factory.ExecuteTenantDbContextAsync(tenantContext, dbContext =>
                dbContext.OutboxMessages.SingleAsync(item => item.MessageId == messageId));
            lastObservedMessage = message;

            if (message.ProcessedAt is not null)
            {
                return message;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500));
        }

        throw new TimeoutException(
            $"The restarted outbox worker did not replay the pending message within the expected window. " +
            $"Last observed PublishAttempts={lastObservedMessage?.PublishAttempts}, " +
            $"LastError={lastObservedMessage?.LastError ?? "<null>"}.");
    }

    private static async Task InvokeOutboxWorkerAsync(IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var worker = scope.ServiceProvider.GetService<XYDataLabs.OrderProcessingSystem.Infrastructure.Events.OutboxPublisherWorker>();

        worker.Should().NotBeNull("OutboxPublisherWorker should be registered as a concrete service.");

        var methodInfo = worker!.GetType().GetMethod(
            "ProcessOutboxMessagesAsync",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);

        methodInfo.Should().NotBeNull();

        var task = (Task)methodInfo!.Invoke(worker, [CancellationToken.None])!;
        await task;
    }

    private sealed class ThrowingEventPublisher : IEventPublisher
    {
        public Task PublishAsync(
            EventEnvelope eventEnvelope,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("Synthetic outbox handler failure during replay test.");
        }
    }
}


