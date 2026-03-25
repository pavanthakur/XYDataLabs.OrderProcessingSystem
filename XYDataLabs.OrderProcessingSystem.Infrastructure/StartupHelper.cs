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
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure
{
    public static class StartupHelper
    {
        public static void InjectInfrastructureDependencies(this IHostApplicationBuilder builder)
        {
            var observabilityOptions = builder.Configuration
                .GetSection(ObservabilityOptions.SectionName)
                .Get<ObservabilityOptions>() ?? new ObservabilityOptions();

            var defaultConnectionString = builder.Configuration.GetConnectionString(
                Constants.Configuration.OrderProcessingSystemDbConnectionString);

            // TenantRegistryDbContext — lightweight context for tenant resolution.
            // Always uses the shared/admin connection string. No ITenantProvider dependency.
            builder.Services.AddDbContext<TenantRegistryDbContext>(options =>
            {
                options.UseSqlServer(defaultConnectionString,
                    sqlOptions => sqlOptions.EnableRetryOnFailure(
                        maxRetryCount: 5,
                        maxRetryDelay: TimeSpan.FromSeconds(30),
                        errorNumbersToAdd: null));
            });

            // Business DbContext — routes to dedicated DB when tenant is resolved as Dedicated tier.
            builder.Services.AddDbContext<OrderProcessingSystemDbContext>((sp, options) =>
            {
                var tenantProvider = sp.GetService<ITenantProvider>();

                // Route to dedicated DB if tenant is resolved and not shared pool
                var connectionString = tenantProvider is not null
                    && tenantProvider.HasTenantContext
                    && !tenantProvider.IsSharedPool
                    && !string.IsNullOrWhiteSpace(tenantProvider.ConnectionString)
                        ? tenantProvider.ConnectionString
                        : defaultConnectionString;

                options.UseSqlServer(connectionString,
                    sqlOptions => sqlOptions.EnableRetryOnFailure(
                        maxRetryCount: 5,
                        maxRetryDelay: TimeSpan.FromSeconds(30),
                        errorNumbersToAdd: null));

                if (observabilityOptions.EnableEfSensitiveDataLogging)
                {
                    options.LogTo(Console.WriteLine, LogLevel.Information)
                           .EnableSensitiveDataLogging()
                           .EnableDetailedErrors();
                }
            });

            // Forward IAppDbContext to the EF-registered concrete context
            builder.Services.AddScoped<IAppDbContext>(sp =>
                sp.GetRequiredService<OrderProcessingSystemDbContext>());

            // Tenant registry service — read-only access to tenant list via TenantRegistryDbContext
            builder.Services.AddScoped<ITenantRegistry, Multitenancy.TenantRegistryService>();

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
