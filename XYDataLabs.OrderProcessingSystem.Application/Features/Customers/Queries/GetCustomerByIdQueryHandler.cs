using AutoMapper;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed class GetCustomerByIdQueryHandler : IQueryHandler<GetCustomerByIdQuery, Result<CustomerDto>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public GetCustomerByIdQueryHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<CustomerDto>> HandleAsync(GetCustomerByIdQuery query, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers.FindAsync([query.CustomerId], cancellationToken);
        if (customer is null)
            return Error.NotFound;

        return _mapper.Map<CustomerDto>(customer);
    }
}
