using XYDataLabs.OrderProcessingSystem.Inventory.API;

namespace XYDataLabs.OrderProcessingSystem.Application.API.Services
{
    public sealed class InventoryService : IInventoryModuleApi
    {
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
}

