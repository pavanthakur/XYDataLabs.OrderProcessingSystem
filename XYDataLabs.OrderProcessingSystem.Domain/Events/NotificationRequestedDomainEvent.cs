namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public sealed record NotificationRequestedDomainEvent(
        int OrderId,
        string Recipient,
        string Subject,
        string Body,
        DateTime OccurredUtc);
}
