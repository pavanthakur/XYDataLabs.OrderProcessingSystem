using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Events;

public sealed class InventoryReservedDomainEventMapper
    : DomainEventToIntegrationEventMapper<InventoryReservedDomainEvent, InventoryReservedV1>
{
    public override InventoryReservedV1 Map(InventoryReservedDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);

        return new InventoryReservedV1(
            domainEvent.OrderId,
            domainEvent.ProductSku,
            domainEvent.QuantityReserved,
            domainEvent.OccurredUtc);
    }
}
