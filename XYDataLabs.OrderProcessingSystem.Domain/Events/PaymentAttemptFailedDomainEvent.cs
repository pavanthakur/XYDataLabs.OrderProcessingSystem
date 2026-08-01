namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public sealed record PaymentAttemptFailedDomainEvent(
        int AttemptId,
        int TenantId,
        string ProviderName,
        string CustomerOrderId,
        string? ErrorReason,
        DateTime OccurredUtc);
}
