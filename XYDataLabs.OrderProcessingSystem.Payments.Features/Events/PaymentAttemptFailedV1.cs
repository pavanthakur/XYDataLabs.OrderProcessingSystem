using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Events;

public sealed record PaymentAttemptFailedV1(
    int AttemptId,
    int TenantId,
    string ProviderName,
    string? ErrorReason,
    DateTime OccurredUtc) : IIntegrationEvent;
