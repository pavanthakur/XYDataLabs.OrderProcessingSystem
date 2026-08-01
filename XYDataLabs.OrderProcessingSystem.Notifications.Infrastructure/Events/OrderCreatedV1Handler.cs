using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure.Events;

public sealed class OrderCreatedV1Handler(
    OrderProcessingSystemDbContext dbContext,
    ILogger<OrderCreatedV1Handler> logger) : IEventHandler<OrderCreatedV1>
{
    public Task HandleAsync(
        EventEnvelope envelope,
        OrderCreatedV1 integrationEvent,
        CancellationToken cancellationToken = default)
    {
        if (envelope.TenantId is null or <= 0)
        {
            throw new InvalidOperationException("OrderCreatedV1 requires a valid envelope TenantId.");
        }

        if (integrationEvent.OrderReferenceId is null || integrationEvent.OrderReferenceId == Guid.Empty)
        {
            throw new InvalidOperationException(
                "OrderCreatedV1 requires OrderReferenceId for notification delivery processing.");
        }

        var tenantId = envelope.TenantId.Value;

        logger.LogInformation(
            "[{Handler}] Accepting notification delivery for tenant {TenantId}, order {OrderReferenceId}, message {MessageId}.",
            nameof(OrderCreatedV1Handler),
            tenantId,
            integrationEvent.OrderReferenceId,
            envelope.MessageId);

        dbContext.NotificationDeliveries.Add(new NotificationDelivery
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            OrderReferenceId = integrationEvent.OrderReferenceId.Value,
            NotificationType = "OrderCreated",
            Sink = "local-deterministic",
            AcceptedUtc = DateTime.UtcNow,
            CorrelationId = envelope.CorrelationId
        });

        return Task.CompletedTask;
    }
}

