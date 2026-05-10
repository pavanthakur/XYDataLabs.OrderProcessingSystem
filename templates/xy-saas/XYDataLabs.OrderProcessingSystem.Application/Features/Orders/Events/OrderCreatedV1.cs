using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Events;

public sealed record OrderCreatedV1(
    int CustomerId,
    DateTime OrderDate,
    decimal TotalPrice,
    int ProductCount) : IIntegrationEvent;