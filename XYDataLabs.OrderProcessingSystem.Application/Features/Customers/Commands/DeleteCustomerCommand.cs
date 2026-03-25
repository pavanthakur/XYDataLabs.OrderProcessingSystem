using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed record DeleteCustomerCommand(int CustomerId) : ICommand<Result<bool>>;
