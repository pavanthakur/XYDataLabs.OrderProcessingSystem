using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Products.Queries;

public sealed class GetAllProductsQueryHandler : IQueryHandler<GetAllProductsQuery, Result<IEnumerable<ProductDto>>>
{
    private readonly IAppDbContext _context;

    public GetAllProductsQueryHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<IEnumerable<ProductDto>>> HandleAsync(GetAllProductsQuery query, CancellationToken cancellationToken = default)
    {
        var products = await _context.Products
            .OrderBy(product => product.Name)
            .ToListAsync(cancellationToken);

        return Result<IEnumerable<ProductDto>>.Success(products.Select(static product => product.ToDto()));
    }
}