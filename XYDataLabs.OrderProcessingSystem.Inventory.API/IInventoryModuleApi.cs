namespace XYDataLabs.OrderProcessingSystem.Inventory.API;

public interface IInventoryModuleApi
{
    Task<IReadOnlyList<InventoryProductSnapshot>> GetProductsByIdsAsync(
        IReadOnlyCollection<int> productIds,
        CancellationToken cancellationToken = default);

    Task<bool> CheckStockAsync(string productId);

    Task<int> GetStockLevelAsync(string productId);

    Task UpdateStockAsync(string productId, int quantity);
}

public sealed record InventoryProductSnapshot(
    int ProductId,
    string Name,
    string? Description,
    decimal Price);

