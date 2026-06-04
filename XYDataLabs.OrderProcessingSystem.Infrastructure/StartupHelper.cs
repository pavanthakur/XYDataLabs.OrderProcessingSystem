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
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

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

            var tenantRegistryConnectionString = builder.Configuration.GetConnectionString(
                Constants.Configuration.TenantRegistryDbConnectionString)
                ?? defaultConnectionString; // Local fallback: same DB when TenantRegistryDbConnection is absent

            // TenantRegistryDbContext — lightweight context for tenant resolution.
            // Local: same physical DB as business DB. Staging/Prod: separate ops-controlled DB.
            // No ITenantProvider dependency — breaks the circular reference.
            builder.Services.AddDbContext<TenantRegistryDbContext>(options =>
            {
                options.UseSqlServer(tenantRegistryConnectionString,
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
            builder.Services.AddScoped<ITenantPaymentProviderConfigurationResolver, Payments.TenantPaymentProviderConfigurationResolver>();

            // Tenant registry service — read-only access to tenant list via TenantRegistryDbContext
            builder.Services.AddScoped<ITenantRegistry, Multitenancy.TenantRegistryService>();

            // Phase 8 Idempotency Guard
            builder.Services.AddScoped<Application.Events.IIdempotencyGuard, Events.SqlIdempotencyGuard>();

            // Phase 8 Background Publish Dispatchers
            builder.Services.AddScoped<Application.Events.IEventPublisher, Events.InMemoryEventPublisher>();
            builder.Services.AddHostedService<Events.OutboxPublisherWorker>();
            builder.Services.AddHostedService<Events.PaymentReconciliationWorker>();

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
