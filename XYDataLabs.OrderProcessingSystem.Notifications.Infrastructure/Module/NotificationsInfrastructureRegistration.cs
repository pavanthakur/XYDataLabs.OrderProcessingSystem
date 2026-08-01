using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using NotificationOrderCreatedHandler = XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure.Events.OrderCreatedV1Handler;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure.Module;

public static class NotificationsInfrastructureRegistration
{
    public static IServiceCollection AddNotificationsInfrastructure(this IServiceCollection services)
    {
        services.AddScoped<NotificationOrderCreatedHandler>();
        services.AddScoped<IEventHandler<OrderCreatedV1>>(provider =>
        {
            var innerHandler = provider.GetRequiredService<NotificationOrderCreatedHandler>();
            var idempotencyGuard = provider.GetRequiredService<IIdempotencyGuard>();
            var logger = provider.GetRequiredService<Microsoft.Extensions.Logging.ILogger<IdempotentEventHandlerDecorator<OrderCreatedV1>>>();
            return new IdempotentEventHandlerDecorator<OrderCreatedV1>(innerHandler, idempotencyGuard, logger);
        });
        return services;
    }
}

