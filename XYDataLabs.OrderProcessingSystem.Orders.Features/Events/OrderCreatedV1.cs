using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Events;

public sealed record OrderCreatedV1(
    int CustomerId,
    DateTime OrderDate,
    decimal TotalPrice,
    int ProductCount,
    Guid? OrderReferenceId = null,
    string CurrencyCode = "MXN") : IIntegrationEvent;
