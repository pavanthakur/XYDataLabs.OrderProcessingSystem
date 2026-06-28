using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Services;
using XYDataLabs.OrderProcessingSystem.Inventory.API;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;

public static class InventoryModuleRegistration
{
    public static IServiceCollection AddInventoryModule(this IServiceCollection services)
    {
        services.AddScoped<IInventoryModuleApi, InventoryService>();
        return services;
    }
}

