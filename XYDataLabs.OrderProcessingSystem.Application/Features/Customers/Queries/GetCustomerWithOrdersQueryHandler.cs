using AutoMapper;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed class GetCustomerWithOrdersQueryHandler : IQueryHandler<GetCustomerWithOrdersQuery, Result<CustomerDto>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public GetCustomerWithOrdersQueryHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<CustomerDto>> HandleAsync(GetCustomerWithOrdersQuery query, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers
            .Include(c => c.Orders)
            .FirstOrDefaultAsync(c => c.CustomerId == query.CustomerId, cancellationToken);

        if (customer is null)
            return Error.NotFound;

        return _mapper.Map<CustomerDto>(customer);
    }
}
