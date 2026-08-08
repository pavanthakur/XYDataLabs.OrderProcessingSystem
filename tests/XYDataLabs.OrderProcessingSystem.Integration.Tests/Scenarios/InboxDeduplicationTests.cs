using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Events;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class InboxDeduplicationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public InboxDeduplicationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        // Force the app to build so services are available
        _ = _factory.CreateClient();
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task Event_Publisher_Should_Idempotently_Process_Duplicate_Messages()
    {
        // Arrange
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);

        var messageId = Guid.NewGuid();
        
        var @event = new OrderCreatedV1(
            CustomerId: 1,
            OrderDate: DateTime.UtcNow,
            TotalPrice: 19.99m,
            ProductCount: 1,
            OrderReferenceId: Guid.NewGuid(),
            CurrencyCode: "MXN");

        var envelope = new EventEnvelope(
            MessageId: messageId,
            EventType: nameof(OrderCreatedV1),
            SchemaVersion: 1,
            OccurredUtc: DateTime.UtcNow,
            Payload: @event,
            TenantId: tenant.TenantId
        );

        // Exercise the SQL-backed idempotency decorator directly so the proof stays valid
        // even as the Phase 10 runtime fans the same event out to multiple module consumers.
        using var scope = _factory.Services.CreateScope();

        var httpContextAccessor = scope.ServiceProvider.GetRequiredService<Microsoft.AspNetCore.Http.IHttpContextAccessor>();
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.Items["TenantContext"] = tenant.ToTenantContext();
        httpContextAccessor.HttpContext = httpContext;

        var idempotencyGuard = scope.ServiceProvider.GetRequiredService<IIdempotencyGuard>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<IdempotentEventHandlerDecorator<OrderCreatedV1>>>();
        var probeHandler = new CountingOrderCreatedHandler();
        var decorator = new IdempotentEventHandlerDecorator<OrderCreatedV1>(probeHandler, idempotencyGuard, logger);

        // Act - First Execution (Should succeed)
        await decorator.HandleAsync(envelope, @event);

        // Act - Second Execution (Duplicate - should be skipped silently via IdempotencyGuard)
        await decorator.HandleAsync(envelope, @event);

        // Assert
        probeHandler.InvocationCount.Should().Be(1);

        var inboxMessages = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            dbContext => dbContext.InboxMessages
                .Where(m => m.MessageId == messageId)
                .ToListAsync());

        // Inbox should have exactly 1 record showing the successful unique processing 
        inboxMessages.Should().ContainSingle();
        inboxMessages[0].EventType.Should().Be("Processed");
        inboxMessages[0].TenantId.Should().Be(tenant.TenantId);
    }

    private sealed class CountingOrderCreatedHandler : IEventHandler<OrderCreatedV1>
    {
        public int InvocationCount { get; private set; }

        public Task HandleAsync(
            EventEnvelope envelope,
            OrderCreatedV1 integrationEvent,
            CancellationToken cancellationToken = default)
        {
            InvocationCount++;
            return Task.CompletedTask;
        }
    }
}


