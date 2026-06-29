namespace XYDataLabs.OrderProcessingSystem.Inventory.API;

public interface IInventoryModuleApi
{
    Task<bool> CheckStockAsync(string productId);

    Task<int> GetStockLevelAsync(string productId);

    Task UpdateStockAsync(string productId, int quantity);
}

