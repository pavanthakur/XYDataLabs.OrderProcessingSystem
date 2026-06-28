using System.Linq.Expressions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Specifications;

public sealed class ProductsByIdsSpecification : Specification<Product>
{
    private readonly IReadOnlyCollection<int> _productIds;

    public ProductsByIdsSpecification(IReadOnlyCollection<int> productIds)
    {
        _productIds = productIds;
    }

    public override Expression<Func<Product, bool>> Criteria => product => _productIds.Contains(product.ProductId);
}
