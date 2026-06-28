using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.API;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Commands;

public sealed record CreateOrderCommand(CustomerId CustomerId, IReadOnlyCollection<ProductId> ProductIds) : ICommand<Result<OrderDto>>;

