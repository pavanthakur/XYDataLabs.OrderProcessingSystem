using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Queries;

public sealed record GetOrderDetailsQuery(OrderId OrderId) : IQuery<Result<OrderDto>>;

