using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed record UpdateCustomerCommand(int CustomerId, string Name, string Email) : ICommand<Result<int>>;
