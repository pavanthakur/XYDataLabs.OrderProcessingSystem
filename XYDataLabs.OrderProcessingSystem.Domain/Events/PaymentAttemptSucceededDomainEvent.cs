namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public sealed record PaymentAttemptSucceededDomainEvent(
        int AttemptId,
        int TenantId,
        string ProviderName,
        string CustomerOrderId,
        DateTime OccurredUtc);
}
