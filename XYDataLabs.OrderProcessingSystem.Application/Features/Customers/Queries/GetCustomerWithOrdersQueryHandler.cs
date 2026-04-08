using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed class GetCustomerWithOrdersQueryHandler : IQueryHandler<GetCustomerWithOrdersQuery, Result<CustomerDto>>
{
    private readonly IAppDbContext _context;

    public GetCustomerWithOrdersQueryHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<CustomerDto>> HandleAsync(GetCustomerWithOrdersQuery query, CancellationToken cancellationToken = default)
    {
        var customer = await _context.Customers
            .Include(c => c.Orders)
            .FirstOrDefaultAsync(c => c.CustomerId == query.CustomerId, cancellationToken);

        if (customer is null)
            return Error.NotFound;

        return customer.ToDto();
    }
}
