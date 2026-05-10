using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

namespace XYDataLabs.OrderProcessingSystem.Domain.Events
{
    public sealed record OrderCreatedDomainEvent(
        CustomerId CustomerId,
        DateTime OrderDate,
        decimal TotalPrice,
        int ProductCount,
        DateTime OccurredUtc);
}