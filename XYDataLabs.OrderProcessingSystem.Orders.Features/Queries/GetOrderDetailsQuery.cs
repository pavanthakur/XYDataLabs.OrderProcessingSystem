using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.API;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Queries;

public sealed record GetOrderDetailsQuery(OrderId OrderId) : IQuery<Result<OrderDto>>;

