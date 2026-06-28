using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Features.Events;

public sealed class NotificationRequestedDomainEventMapper
    : DomainEventToIntegrationEventMapper<NotificationRequestedDomainEvent, NotificationRequestedV1>
{
    public override NotificationRequestedV1 Map(NotificationRequestedDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);

        return new NotificationRequestedV1(
            "OrderNotification",
            domainEvent.Recipient,
            domainEvent.Subject,
            domainEvent.Body);
    }
}
