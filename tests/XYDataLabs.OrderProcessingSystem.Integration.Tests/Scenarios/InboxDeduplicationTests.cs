using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
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

        var eventId = Guid.NewGuid();
        var messageId = Guid.NewGuid();
        
        var @event = new OrderCreatedV1(
            CustomerId: 1,
            OrderDate: DateTime.UtcNow,
            TotalPrice: 19.99m,
            ProductCount: 1);

        var envelope = new EventEnvelope(
            MessageId: messageId,
            EventType: nameof(OrderCreatedV1),
            SchemaVersion: 1,
            OccurredUtc: DateTime.UtcNow,
            Payload: @event,
            TenantId: tenant.TenantId
        );

        // We dispatch the message twice back-to-back using the API's DI container scope.
        // It should seamlessly handle the first execution (writing to InboxMessages) and ignore the second execution.
        
        using var scope = _factory.Services.CreateScope();
        
        // Ensure tenant context is set since Inbox is tenant-bound
        var httpContextAccessor = scope.ServiceProvider.GetRequiredService<Microsoft.AspNetCore.Http.IHttpContextAccessor>();
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.Items["TenantContext"] = tenant.ToTenantContext();
        httpContextAccessor.HttpContext = httpContext;
        
        var publisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();

        // Act - First Execution (Should succeed)
        await publisher.PublishAsync(envelope);

        // Act - Second Execution (Duplicate - should be skipped silently via IdempotencyGuard)
        await publisher.PublishAsync(envelope);

        // Assert
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
}
