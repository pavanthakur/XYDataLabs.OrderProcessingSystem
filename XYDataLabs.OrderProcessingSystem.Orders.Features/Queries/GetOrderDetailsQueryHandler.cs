using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Mappings;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Queries;

public sealed class GetOrderDetailsQueryHandler : IQueryHandler<GetOrderDetailsQuery, Result<OrderDto>>
{
    private readonly IAppDbContext _context;

    public GetOrderDetailsQueryHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<OrderDto>> HandleAsync(GetOrderDetailsQuery query, CancellationToken cancellationToken = default)
    {
        var order = await _context.Orders
            .Include(o => o.OrderProducts)
            .ThenInclude(oi => oi.Product)
            .FirstOrDefaultAsync(o => o.OrderId == query.OrderId, cancellationToken);

        if (order is null)
            return Error.NotFound;

        return order.ToDto();
    }
}

