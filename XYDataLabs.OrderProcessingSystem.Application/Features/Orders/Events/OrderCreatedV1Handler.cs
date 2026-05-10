using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Events;

public sealed class OrderCreatedV1Handler : IEventHandler<OrderCreatedV1>
{
    private readonly ILogger<OrderCreatedV1Handler> _logger;

    public OrderCreatedV1Handler(ILogger<OrderCreatedV1Handler> logger)
    {
        _logger = logger;
    }

    public Task HandleAsync(EventEnvelope envelope, OrderCreatedV1 @event, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[{Handler}] Processing OrderCreatedV1. MessageId: {MessageId}, CustomerId: {CustomerId}",
            nameof(OrderCreatedV1Handler),
            envelope.MessageId,
            @event.CustomerId);

        // Simulated side-effect (e.g. sending notification, confirming stock)
        // Since we are proving Phase 8 outbox dispatch, just successfully completing is sufficient.
        return Task.CompletedTask;
    }
}
