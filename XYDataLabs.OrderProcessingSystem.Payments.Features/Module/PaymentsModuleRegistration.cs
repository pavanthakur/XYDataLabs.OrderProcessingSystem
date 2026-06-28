using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Services;
using XYDataLabs.OrderProcessingSystem.Payments.API;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Module;

public static class PaymentsModuleRegistration
{
    public static IServiceCollection AddPaymentsModule(this IServiceCollection services)
    {
        services.AddScoped<IPaymentsModuleApi, PaymentsService>();
        return services;
    }
}

