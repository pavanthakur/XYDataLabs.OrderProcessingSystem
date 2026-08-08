using XYDataLabs.OrderProcessingSystem.Eventing.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

public sealed record PaymentAttemptSucceededV1(
    int AttemptId,
    int TenantId,
    string ProviderName,
    string CustomerOrderId,
    DateTime OccurredUtc) : IIntegrationEvent;
