using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Events;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Events;

public sealed class InventoryReservedV1Handler : IEventHandler<InventoryReservedV1>
{
    private readonly IEventPublisher _eventPublisher;
    private readonly ILogger<InventoryReservedV1Handler> _logger;

    public InventoryReservedV1Handler(
        IEventPublisher eventPublisher,
        ILogger<InventoryReservedV1Handler> logger)
    {
        _eventPublisher = eventPublisher;
        _logger = logger;
    }

    public async Task HandleAsync(EventEnvelope envelope, InventoryReservedV1 @event, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[{Handler}] Processing InventoryReservedV1. MessageId: {MessageId}, OrderId: {OrderId}, ProductSku: {ProductSku}",
            nameof(InventoryReservedV1Handler),
            envelope.MessageId,
            @event.OrderId,
            @event.ProductSku);

        var notificationRequested = new NotificationRequestedV1(
            "InventoryReservationConfirmed",
            $"customer-{@event.OrderId}@example.test",
            $"Inventory reserved for order {@event.OrderId}",
            $"Inventory reservation completed for {@event.ProductSku} x{@event.QuantityReserved}.");

        var notificationEnvelope = EventEnvelope.Create(
            nameof(NotificationRequestedV1),
            schemaVersion: 1,
            occurredUtc: @event.OccurredUtc,
            payload: notificationRequested,
            correlationId: envelope.CorrelationId ?? envelope.MessageId.ToString("N"),
            causationId: envelope.MessageId.ToString("N"),
            traceParent: envelope.TraceParent,
            tenantId: envelope.TenantId);

        await _eventPublisher.PublishAsync(notificationEnvelope, cancellationToken).ConfigureAwait(false);
    }
}
