using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using InventoryOrderCreatedHandler = XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure.Events.OrderCreatedV1Handler;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure.Module;

public static class InventoryInfrastructureRegistration
{
    public static IServiceCollection AddInventoryInfrastructure(this IServiceCollection services)
    {
        services.AddScoped<InventoryOrderCreatedHandler>();
        services.AddScoped<IEventHandler<OrderCreatedV1>>(provider =>
        {
            var innerHandler = provider.GetRequiredService<InventoryOrderCreatedHandler>();
            var idempotencyGuard = provider.GetRequiredService<IIdempotencyGuard>();
            var logger = provider.GetRequiredService<Microsoft.Extensions.Logging.ILogger<IdempotentEventHandlerDecorator<OrderCreatedV1>>>();
            return new IdempotentEventHandlerDecorator<OrderCreatedV1>(innerHandler, idempotencyGuard, logger);
        });
        return services;
    }
}

