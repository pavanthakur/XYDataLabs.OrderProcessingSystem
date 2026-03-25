using AutoMapper;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class CreateCustomerCommandHandler : ICommandHandler<CreateCustomerCommand, Result<int>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public CreateCustomerCommandHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<int>> HandleAsync(CreateCustomerCommand command, CancellationToken cancellationToken = default)
    {
        var customer = _mapper.Map<Customer>(new DTO.CreateCustomerRequestDto { Name = command.Name, Email = command.Email });
        _context.Customers.Add(customer);

        if (await _context.SaveChangesAsync(cancellationToken) > 0)
            return customer.CustomerId;

        return Error.Create("CreateFailed", "Failed to create customer.");
    }
}
