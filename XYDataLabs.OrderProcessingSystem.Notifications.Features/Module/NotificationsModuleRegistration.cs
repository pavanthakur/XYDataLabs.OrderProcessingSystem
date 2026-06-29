using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Services;
using XYDataLabs.OrderProcessingSystem.Notifications.API;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;

public static class NotificationsModuleRegistration
{
    public static IServiceCollection AddNotificationsModule(this IServiceCollection services)
    {
        services.AddScoped<INotificationsModuleApi, NotificationsService>();
        return services;
    }
}

