using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Queries;

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
