using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class UpdateCustomerCommandHandler : ICommandHandler<UpdateCustomerCommand, Result<int>>
{
    private readonly IAppDbContext _context;

    public UpdateCustomerCommandHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<int>> HandleAsync(UpdateCustomerCommand command, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers.FindAsync([command.CustomerId], cancellationToken);
        if (customer is null)
            return Error.NotFound;

        customer.ApplyUpdate(new UpdateCustomerRequestDto { Name = command.Name, Email = command.Email });
        _context.Customers.Update(customer);
        await _context.SaveChangesAsync(cancellationToken);

        return customer.CustomerId.Value;
    }
}
