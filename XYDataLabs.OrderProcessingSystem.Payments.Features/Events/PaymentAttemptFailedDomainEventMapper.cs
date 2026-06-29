using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Events;

public sealed class PaymentAttemptFailedDomainEventMapper
    : DomainEventToIntegrationEventMapper<PaymentAttemptFailedDomainEvent, PaymentAttemptFailedV1>
{
    public override PaymentAttemptFailedV1 Map(PaymentAttemptFailedDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);

        return new PaymentAttemptFailedV1(
            domainEvent.AttemptId,
            domainEvent.TenantId,
            domainEvent.ProviderName,
            domainEvent.ErrorReason,
            domainEvent.OccurredUtc);
    }
}
