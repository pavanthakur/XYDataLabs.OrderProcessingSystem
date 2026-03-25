using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;

public sealed record CreateOrderCommand(int CustomerId, List<int> ProductIds) : ICommand<Result<OrderDto>>;
