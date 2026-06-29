using Microsoft.Extensions.DependencyInjection;
using System.Reflection;
using Microsoft.Extensions.Hosting;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Application
{
    public static class StartupHelper
    {
        public static void InjectApplicationDependencies(this IHostApplicationBuilder builder)
        {
            if (builder is null)
            {
                throw new ArgumentNullException(nameof(builder));
            }

            // Register CQRS: handlers, validators, pipeline behaviors, dispatcher
            builder.Services.AddCqrs(Assembly.GetExecutingAssembly());

            // Register Event Type mapping resolution for background workers
            builder.Services.AddSingleton<Events.IIntegrationEventTypeResolver, Events.IntegrationEventTypeResolver>();

            // AppMasterData is scoped so each request gets the tenant-routed DbContext.
            // This ensures dedicated-tier tenants load providers from their own DB — no
            // cross-tenant data exposure. Changing Use3DSecure takes effect immediately
            // (no API restart required).
            builder.Services.AddScoped<AppMasterData>();

        }
    }
}
