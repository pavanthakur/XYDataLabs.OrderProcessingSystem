using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class CreateCustomerCommandHandler : ICommandHandler<CreateCustomerCommand, Result<int>>
{
    private readonly IAppDbContext _context;

    public CreateCustomerCommandHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<int>> HandleAsync(CreateCustomerCommand command, CancellationToken cancellationToken = default)
    {
        var customer = new CreateCustomerRequestDto { Name = command.Name, Email = command.Email }.ToEntity();
        _context.Customers.Add(customer);

        if (await _context.SaveChangesAsync(cancellationToken) > 0)
            return customer.CustomerId.Value;

        return Error.Create("CreateFailed", "Failed to create customer.");
    }
}
