using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Features.Events;

public sealed class NotificationRequestedV1Handler : IEventHandler<NotificationRequestedV1>
{
    private readonly ILogger<NotificationRequestedV1Handler> _logger;

    public NotificationRequestedV1Handler(ILogger<NotificationRequestedV1Handler> logger)
    {
        _logger = logger;
    }

    public Task HandleAsync(EventEnvelope envelope, NotificationRequestedV1 @event, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[{Handler}] Processing NotificationRequestedV1. MessageId: {MessageId}, NotificationType: {NotificationType}, Recipient: {Recipient}",
            nameof(NotificationRequestedV1Handler),
            envelope.MessageId,
            @event.NotificationType,
            @event.Recipient);

        return Task.CompletedTask;
    }
}
