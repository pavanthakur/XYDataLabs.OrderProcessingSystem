using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Events;

public sealed class PaymentAttemptSucceededDomainEventMapper
    : DomainEventToIntegrationEventMapper<PaymentAttemptSucceededDomainEvent, PaymentAttemptSucceededV1>
{
    public override PaymentAttemptSucceededV1 Map(PaymentAttemptSucceededDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);

        return new PaymentAttemptSucceededV1(
            domainEvent.AttemptId,
            domainEvent.TenantId,
            domainEvent.ProviderName,
            domainEvent.CustomerOrderId,
            domainEvent.OccurredUtc);
    }
}
