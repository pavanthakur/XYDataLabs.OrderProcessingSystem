using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class DeleteCustomerCommandHandler : ICommandHandler<DeleteCustomerCommand, Result<bool>>
{
    private readonly IAppDbContext _context;

    public DeleteCustomerCommandHandler(IAppDbContext context) => _context = context;

    public async Task<Result<bool>> HandleAsync(DeleteCustomerCommand command, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers.FindAsync([command.CustomerId], cancellationToken);
        if (customer is null)
            return Error.NotFound;

        _context.Customers.Remove(customer);
        await _context.SaveChangesAsync(cancellationToken);

        return true;
    }
}
