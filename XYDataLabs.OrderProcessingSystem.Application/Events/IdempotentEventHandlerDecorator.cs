using Microsoft.Extensions.Logging;
using SharedIntegrationEvent = XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.IIntegrationEvent;

namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public class IdempotentEventHandlerDecorator<TEvent> : IEventHandler<TEvent>
    where TEvent : class, SharedIntegrationEvent
{
    private readonly IEventHandler<TEvent> _innerHandler;
    private readonly IIdempotencyGuard _idempotencyGuard;
    private readonly ILogger<IdempotentEventHandlerDecorator<TEvent>> _logger;

    public IdempotentEventHandlerDecorator(
        IEventHandler<TEvent> innerHandler,
        IIdempotencyGuard idempotencyGuard,
        ILogger<IdempotentEventHandlerDecorator<TEvent>> logger)
    {
        _innerHandler = innerHandler;
        _idempotencyGuard = idempotencyGuard;
        _logger = logger;
    }

    public async Task HandleAsync(EventEnvelope envelope, TEvent @event, CancellationToken cancellationToken = default)
    {
        var messageId = envelope.MessageId;

        // Check if we've processed this message already.
        if (await _idempotencyGuard.HasProcessedAsync(messageId, cancellationToken))
        {
            _logger.LogInformation("Message {MessageId} for Event {EventType} already processed. Skipping duplicate.", messageId, envelope.EventType);
            return;
        }

        // Execute the real handler logic
        await _innerHandler.HandleAsync(envelope, @event, cancellationToken);

        // Record successful execution
        await _idempotencyGuard.MarkProcessedAsync(messageId, cancellationToken);
    }
}
