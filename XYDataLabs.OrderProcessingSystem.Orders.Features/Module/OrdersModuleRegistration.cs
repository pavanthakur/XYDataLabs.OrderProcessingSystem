using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Services;
using XYDataLabs.OrderProcessingSystem.Orders.API;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Module;

public static class OrdersModuleRegistration
{
    public static IServiceCollection AddOrdersModule(this IServiceCollection services)
    {
        services.AddScoped<IOrderModuleApi, OrdersService>();
        return services;
    }
}

