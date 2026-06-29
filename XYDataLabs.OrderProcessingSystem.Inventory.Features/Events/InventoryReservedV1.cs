using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Events;

public sealed record InventoryReservedV1(
    int OrderId,
    string ProductSku,
    int QuantityReserved,
    DateTime OccurredUtc) : IIntegrationEvent;
