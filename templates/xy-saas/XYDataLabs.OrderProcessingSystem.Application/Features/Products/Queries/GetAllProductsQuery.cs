using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Products.Queries;

public sealed record GetAllProductsQuery : IQuery<Result<IEnumerable<ProductDto>>>, ICacheable
{
    public string CacheKey => "products:all";
    public TimeSpan? Expiration => TimeSpan.FromMinutes(5);
}