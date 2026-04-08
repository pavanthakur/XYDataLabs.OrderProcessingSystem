using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed record UpdateCustomerCommand(CustomerId CustomerId, string Name, string Email) : ICommand<Result<int>>;
