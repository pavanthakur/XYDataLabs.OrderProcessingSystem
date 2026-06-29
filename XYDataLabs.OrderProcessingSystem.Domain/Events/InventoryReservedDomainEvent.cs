namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public sealed record InventoryReservedDomainEvent(
        int OrderId,
        string ProductSku,
        int QuantityReserved,
        DateTime OccurredUtc);
}
