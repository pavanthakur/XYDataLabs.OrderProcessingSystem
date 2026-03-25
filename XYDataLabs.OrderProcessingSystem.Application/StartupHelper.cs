using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using System.Reflection;
using Microsoft.Extensions.Hosting;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;

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

            // Register OpenPay adapter (external payment gateway)
            builder.Services.AddOpenPayAdapter(builder.Configuration);
            builder.Services.AddScoped<IOpenPayAdapterService, OpenPayAdapterService>();

            // Initialize AppMasterData as Singleton
            builder.Services.AddSingleton<AppMasterData>(serviceProvider =>
            {
                using var scope = serviceProvider.CreateScope();
                var dbContext = scope.ServiceProvider.GetRequiredService<IAppDbContext>();
                return new AppMasterData(dbContext);
            });
        }
    }
}
