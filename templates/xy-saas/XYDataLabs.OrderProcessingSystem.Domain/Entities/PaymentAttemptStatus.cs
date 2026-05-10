namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public enum PaymentAttemptStatus
    {
        PendingProviderCall = 0,
        ProviderAccepted = 1,
        Succeeded = 2,
        Failed = 3,
        UnknownNeedsReconciliation = 4,
    }
}