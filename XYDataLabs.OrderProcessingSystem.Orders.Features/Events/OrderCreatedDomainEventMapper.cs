using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Events;

public sealed class OrderCreatedDomainEventMapper : DomainEventToIntegrationEventMapper<OrderCreatedDomainEvent, OrderCreatedV1>
{
    public override OrderCreatedV1 Map(OrderCreatedDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);

        return new OrderCreatedV1(
            domainEvent.CustomerId.Value,
            domainEvent.OrderDate,
            domainEvent.TotalPrice,
            domainEvent.ProductCount,
            domainEvent.OrderReferenceId,
            domainEvent.CurrencyCode);
    }
}
