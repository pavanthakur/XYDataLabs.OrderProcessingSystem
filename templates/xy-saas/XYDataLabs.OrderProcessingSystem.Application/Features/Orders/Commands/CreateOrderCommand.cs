using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;

public sealed record CreateOrderCommand(CustomerId CustomerId, IReadOnlyCollection<ProductId> ProductIds) : ICommand<Result<OrderDto>>;
