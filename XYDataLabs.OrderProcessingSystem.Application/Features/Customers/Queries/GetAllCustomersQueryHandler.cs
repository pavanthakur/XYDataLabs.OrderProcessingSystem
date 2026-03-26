using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed class GetAllCustomersQueryHandler : IQueryHandler<GetAllCustomersQuery, Result<IEnumerable<CustomerDto>>>
{
    private readonly IAppDbContext _context;

    public GetAllCustomersQueryHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<IEnumerable<CustomerDto>>> HandleAsync(GetAllCustomersQuery query, CancellationToken cancellationToken = default)
    {
        var customers = await _context.Customers.ToListAsync(cancellationToken);
        return Result<IEnumerable<CustomerDto>>.Success(customers.Select(c => c.ToDto()));
    }
}
