using AutoMapper;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class UpdateCustomerCommandHandler : ICommandHandler<UpdateCustomerCommand, Result<int>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public UpdateCustomerCommandHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<int>> HandleAsync(UpdateCustomerCommand command, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers.FindAsync([command.CustomerId], cancellationToken);
        if (customer is null)
            return Error.NotFound;

        _mapper.Map(new DTO.UpdateCustomerRequestDto { Name = command.Name, Email = command.Email }, customer);
        _context.Customers.Update(customer);
        await _context.SaveChangesAsync(cancellationToken);

        return customer.CustomerId;
    }
}
