using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Services;

public sealed class InventoryService(IAppDbContext context) : IInventoryModuleApi
{
    public async Task<IReadOnlyList<InventoryProductSnapshot>> GetProductsByIdsAsync(
        IReadOnlyCollection<int> productIds,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(productIds);

        if (productIds.Count == 0)
        {
            return [];
        }

        var resolvedProductIds = productIds
            .Distinct()
            .Select(static productId => new ProductId(productId))
            .ToArray();

        return await context.Products
            .Where(product => resolvedProductIds.Contains(product.ProductId))
            .OrderBy(product => product.Name)
            .Select(product => new InventoryProductSnapshot(
                product.ProductId.Value,
                product.Name,
                product.Description,
                product.Price.Value))
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);
    }

    public Task<bool> CheckStockAsync(string productId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(productId);
        return Task.FromResult(true);
    }

    public Task<int> GetStockLevelAsync(string productId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(productId);
        return Task.FromResult(0);
    }

    public Task UpdateStockAsync(string productId, int quantity)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(productId);
        ArgumentOutOfRangeException.ThrowIfNegative(quantity);
        return Task.CompletedTask;
    }
}

