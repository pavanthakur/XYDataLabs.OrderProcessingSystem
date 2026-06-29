using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Events;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Events;

public sealed class OrderCreatedV1Handler : IEventHandler<OrderCreatedV1>
{
    private readonly IEventPublisher _eventPublisher;
    private readonly ILogger<OrderCreatedV1Handler> _logger;

    public OrderCreatedV1Handler(
        IEventPublisher eventPublisher,
        ILogger<OrderCreatedV1Handler> logger)
    {
        _eventPublisher = eventPublisher;
        _logger = logger;
    }

    public async Task HandleAsync(EventEnvelope envelope, OrderCreatedV1 @event, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[{Handler}] Processing OrderCreatedV1. MessageId: {MessageId}, CustomerId: {CustomerId}",
            nameof(OrderCreatedV1Handler),
            envelope.MessageId,
            @event.CustomerId);

        var orderId = ResolveWorkflowOrderId(envelope);
        var inventoryReserved = new InventoryReservedV1(
            orderId,
            $"SKU-{@event.CustomerId:D4}",
            Math.Max(1, @event.ProductCount),
            DateTime.UtcNow);

        var inventoryEnvelope = EventEnvelope.Create(
            nameof(InventoryReservedV1),
            schemaVersion: 1,
            occurredUtc: inventoryReserved.OccurredUtc,
            payload: inventoryReserved,
            correlationId: envelope.CorrelationId ?? envelope.MessageId.ToString("N"),
            causationId: envelope.MessageId.ToString("N"),
            traceParent: envelope.TraceParent,
            tenantId: envelope.TenantId);

        await _eventPublisher.PublishAsync(inventoryEnvelope, cancellationToken).ConfigureAwait(false);
    }

    private static int ResolveWorkflowOrderId(EventEnvelope envelope)
    {
        var bytes = envelope.MessageId.ToByteArray();
        var value = BitConverter.ToInt32(bytes, 0) & int.MaxValue;
        return value == 0 ? 1 : value;
    }
}
