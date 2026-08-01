using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public static class Phase10ServiceHostExtensions
{
    public static void AddPhase10ServiceHostInfrastructure(
        this IHostApplicationBuilder builder,
        string? consumerKind = null,
        bool enableOutboxPublisher = false,
        bool enablePaymentReconciliation = false)
    {
        ArgumentNullException.ThrowIfNull(builder);

        var defaultConnectionString = builder.Configuration.GetConnectionString(
            Constants.Configuration.OrderProcessingSystemDbConnectionString)
            ?? throw new InvalidOperationException(
                $"ConnectionStrings:{Constants.Configuration.OrderProcessingSystemDbConnectionString} is required.");
        var registryConnectionString = builder.Configuration.GetConnectionString(
            Constants.Configuration.TenantRegistryDbConnectionString)
            ?? defaultConnectionString;

        builder.Services.AddHttpContextAccessor();
        builder.Services.AddSingleton(TimeProvider.System);
        builder.Services.AddScoped<ScopedTenantContextAccessor>();
        builder.Services.AddScoped<ITenantProvider, HeaderTenantProvider>();
        builder.Services.AddScoped<ITenantResolver, EntityFrameworkTenantResolver>();
        builder.Services.AddScoped<ITenantRegistry, TenantRegistryService>();
        builder.Services.AddScoped<ITenantPaymentProviderResolver, Payments.Phase10TenantPaymentProviderResolver>();

        builder.Services.AddDbContext<TenantRegistryDbContext>(options =>
            options.UseSqlServer(
                registryConnectionString,
                sql => sql.EnableRetryOnFailure(5, TimeSpan.FromSeconds(30), null)));
        builder.Services.AddDbContext<OrderProcessingSystemDbContext>((serviceProvider, options) =>
        {
            var tenantProvider = serviceProvider.GetRequiredService<ITenantProvider>();
            var connectionString = tenantProvider.HasTenantContext
                && !tenantProvider.IsSharedPool
                && !string.IsNullOrWhiteSpace(tenantProvider.ConnectionString)
                    ? tenantProvider.ConnectionString
                    : defaultConnectionString;
            options.UseSqlServer(
                connectionString,
                sql => sql.EnableRetryOnFailure(5, TimeSpan.FromSeconds(30), null));
        });
        builder.Services.AddScoped<XYDataLabs.OrderProcessingSystem.Application.Abstractions.IAppDbContext>(serviceProvider =>
            serviceProvider.GetRequiredService<OrderProcessingSystemDbContext>());
        builder.Services.AddScoped<XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions.IAppDbContext>(serviceProvider =>
            serviceProvider.GetRequiredService<OrderProcessingSystemDbContext>());
        builder.Services.AddScoped<ITenantPaymentProviderConfigurationResolver, Payments.TenantPaymentProviderConfigurationResolver>();
        builder.Services.AddScoped<IWebhookSignatureValidator, WebhookSignatureValidator>();
        builder.Services.AddScoped<IIdempotencyGuard, SqlIdempotencyGuard>();
        builder.Services.AddScoped<IDlqReplayApprovalService, DlqReplayApprovalService>();

        builder.Services.Configure<ServiceBusOptions>(
            builder.Configuration.GetSection(ServiceBusOptions.SectionName));
        builder.Services.AddSingleton<ServiceBusMessageFactory>();
        var options = builder.Configuration
            .GetSection(ServiceBusOptions.SectionName)
            .Get<ServiceBusOptions>() ?? new ServiceBusOptions();
        if (options.Enabled)
        {
            if (string.IsNullOrWhiteSpace(options.ConnectionString))
            {
                throw new InvalidOperationException(
                    "ServiceBus:ConnectionString is required when ServiceBus:Enabled is true.");
            }

            builder.Services.AddSingleton(_ => new ServiceBusClient(options.ConnectionString));
            builder.Services.AddScoped<IEventPublisher, ServiceBusEventPublisher>();
            builder.Services.AddHostedService<DlqReplayRequestPublisher>();
            if (!string.IsNullOrWhiteSpace(consumerKind))
            {
                builder.Services.AddScoped<IIdempotencyGuard, NoOpIdempotencyGuard>();
                builder.Services.AddSingleton(CreateConsumerSubscription(consumerKind, options));
                builder.Services.AddSingleton<IServiceBusConsumerMessageProcessor, ServiceBusConsumerMessageProcessor>();
                builder.Services.AddHostedService<ServiceBusSubscriptionConsumerWorker>();
            }
        }
        else
        {
            builder.Services.AddScoped<IEventPublisher, InMemoryEventPublisher>();
        }

        if (enableOutboxPublisher)
        {
            builder.Services.AddScoped<OutboxPublisherWorker>();
            builder.Services.AddHostedService<OutboxPublisherWorker>();
        }

        if (enablePaymentReconciliation)
        {
            builder.Services.AddScoped<PaymentReconciliationWorker>();
            builder.Services.AddHostedService<PaymentReconciliationWorker>();
        }
    }

    private static ServiceBusConsumerSubscription CreateConsumerSubscription(string consumerKind, ServiceBusOptions options)
    {
        return consumerKind switch
        {
            "Inventory" => ServiceBusConsumerSubscription.ForInventory(options.SubscriptionName),
            "Notifications" => ServiceBusConsumerSubscription.ForNotifications(options.SubscriptionName),
            "Orders" => ServiceBusConsumerSubscription.ForOrdersPaymentState(options.PaymentStateSubscriptionName),
            _ => throw new InvalidOperationException($"Unsupported Phase 10 consumer kind '{consumerKind}'.")
        };
    }
}

internal sealed class NoOpIdempotencyGuard : IIdempotencyGuard
{
    public Task<bool> HasProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
        => Task.FromResult(false);

    public Task MarkProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
        => Task.CompletedTask;
}
