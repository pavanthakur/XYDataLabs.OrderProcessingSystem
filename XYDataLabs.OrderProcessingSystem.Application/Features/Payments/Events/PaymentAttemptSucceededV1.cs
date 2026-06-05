using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Events;

public sealed record PaymentAttemptSucceededV1(
    int AttemptId,
    int TenantId,
    string ProviderName,
    string CustomerOrderId,
    DateTime OccurredUtc) : IIntegrationEvent;
