using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using System.Reflection;
using XYDataLabs.OrderProcessingSystem.Infrastructure;
using Microsoft.Extensions.Hosting;
using FluentValidation;
using Microsoft.AspNetCore.DataProtection.Repositories;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Application.Services;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Application
{
    public static class StartupHelper
    {
        public static void InjectApplicationDependencies(this IHostApplicationBuilder builder)
        {
            // Use the correct extension method for adding validators
            builder.Services.AddValidatorsFromAssembly(Assembly.GetExecutingAssembly());

            // Register Application Services 
            builder.Services.AddScoped<IOrderService, OrderService>(); // Scoped to ensure a new instance per request
            builder.Services.AddScoped<ICustomerService, CustomerService>();

            // Register OpenPay services
            builder.Services.AddOpenPayAdapter(builder.Configuration);
            builder.Services.AddScoped<IOpenPayAdapterService, OpenPayAdapterService>();
            builder.Services.AddScoped<IOpenPayService, OpenPayService>();

            // Initialize AppMasterData as Singleton
            builder.Services.AddSingleton<AppMasterData>(serviceProvider =>
            {
                // Create a new scope to resolve scoped dependencies
                using var scope = serviceProvider.CreateScope();
                var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
                
                // Ensure database is initialized with seed data before loading master data
                DbInitializer.Initialize(dbContext);
                
                return new AppMasterData(dbContext);
            });

            //Finally InjectInfrastructureDependencies
            builder.InjectInfrastructureDependencies();
        }
    }
}
