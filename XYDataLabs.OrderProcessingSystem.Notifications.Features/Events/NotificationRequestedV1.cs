using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Features.Events;

public sealed record NotificationRequestedV1(
    string NotificationType,
    string Recipient,
    string Subject,
    string Body) : IIntegrationEvent;
