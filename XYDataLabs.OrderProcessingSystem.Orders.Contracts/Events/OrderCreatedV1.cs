using XYDataLabs.OrderProcessingSystem.Eventing.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

public sealed record OrderCreatedV1(
    int CustomerId,
    DateTime OrderDate,
    decimal TotalPrice,
    int ProductCount,
    Guid? OrderReferenceId = null,
    string CurrencyCode = "MXN") : IIntegrationEvent;
