using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Specifications;

public sealed class ProductsByIdsSpecification : Specification<Product>
{
    private readonly int[] _productIds;

    public ProductsByIdsSpecification(IEnumerable<int> productIds)
    {
        _productIds = productIds?.Distinct().ToArray() ?? [];
    }

    public override System.Linq.Expressions.Expression<Func<Product, bool>> Criteria
        => product => _productIds.Length > 0 && _productIds.Contains(product.ProductId);
}
