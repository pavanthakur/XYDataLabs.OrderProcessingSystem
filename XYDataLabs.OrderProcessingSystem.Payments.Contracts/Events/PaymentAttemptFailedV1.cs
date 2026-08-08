using XYDataLabs.OrderProcessingSystem.Eventing.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

public sealed record PaymentAttemptFailedV1(
    int AttemptId,
    int TenantId,
    string ProviderName,
    string CustomerOrderId,
    string? ErrorReason,
    DateTime OccurredUtc) : IIntegrationEvent;
