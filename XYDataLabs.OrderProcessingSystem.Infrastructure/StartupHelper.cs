using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using XYDataLabs.OrderProcessingSystem.SharedKernel;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure
{
    public static class StartupHelper
    {
        public static void InjectInfrastructureDependencies(this IHostApplicationBuilder builder)
        {
            var enableSensitiveDataLogging = builder.Configuration.GetValue<bool>(Constants.Configuration.EnableEfSensitiveDataLogging);

            builder.Services.AddDbContext<OrderProcessingSystemDbContext>(options =>
            {
                options.UseSqlServer(
                    builder.Configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString),
                    sqlOptions => sqlOptions.EnableRetryOnFailure(
                        maxRetryCount: 5,
                        maxRetryDelay: TimeSpan.FromSeconds(30),
                        errorNumbersToAdd: null));

                if (enableSensitiveDataLogging)
                {
                    options.LogTo(Console.WriteLine, LogLevel.Information)
                           .EnableSensitiveDataLogging()
                           .EnableDetailedErrors();
                }
            });

            // Forward IAppDbContext to the EF-registered concrete context
            builder.Services.AddScoped<IAppDbContext>(sp =>
                sp.GetRequiredService<OrderProcessingSystemDbContext>());

            // IDistributedCache — Redis when configured, in-memory fallback otherwise
            var redisConnection = builder.Configuration.GetConnectionString("Redis");
            if (!string.IsNullOrWhiteSpace(redisConnection))
            {
                builder.Services.AddStackExchangeRedisCache(options =>
                {
                    options.Configuration = redisConnection;
                    options.InstanceName = "OrderProcessing:";
                });
            }
            else
            {
                builder.Services.AddDistributedMemoryCache();
            }
        }
    }
}
