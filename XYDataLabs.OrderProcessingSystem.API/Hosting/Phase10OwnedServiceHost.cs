using Asp.Versioning;
using Microsoft.ApplicationInsights;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc.ApplicationParts;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.API.Security;
using XYDataLabs.OrderProcessingSystem.API.Services;
using XYDataLabs.OrderProcessingSystem.Application;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.Features;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.RazorpayAdapter;

namespace XYDataLabs.OrderProcessingSystem.API.Hosting;

public enum Phase10ServiceKind
{
    Orders,
    Payments,
    Inventory,
    Notifications
}

public static class Phase10OwnedServiceHost
{
    public static void AddPhase10OwnedService(
        this WebApplicationBuilder builder,
        Phase10ServiceKind serviceKind)
    {
        ArgumentNullException.ThrowIfNull(builder);

        var environmentName = builder.Environment.EnvironmentName switch
        {
            "Development" => Constants.Environments.Dev,
            "Staging" => Constants.Environments.Staging,
            "Production" => Constants.Environments.Production,
            _ => Constants.Environments.Dev
        };
        var isDocker = string.Equals(
            Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
            "true",
            StringComparison.OrdinalIgnoreCase);

        SharedSettingsLoader.LoadSharedSettings(builder.Configuration, environmentName, isDocker);
        builder.Services.AddSingleton<IValidateOptions<TenantConfigurationOptions>, TenantConfigurationOptionsValidator>();
        builder.Services.AddOptions<TenantConfigurationOptions>()
            .Bind(builder.Configuration.GetSection(TenantConfigurationOptions.SectionName))
            .ValidateOnStart();

        builder.Services.AddHttpClient();
        var redisConnectionString = builder.Configuration.GetConnectionString("Redis");
        if (!string.IsNullOrWhiteSpace(redisConnectionString))
        {
            builder.Services.AddStackExchangeRedisCache(options =>
            {
                options.Configuration = redisConnectionString;
                options.InstanceName = "OrderProcessing:";
            });
        }
        else
        {
            builder.Services.AddDistributedMemoryCache();
        }
        var consumerKind = serviceKind switch
        {
            Phase10ServiceKind.Inventory => "Inventory",
            Phase10ServiceKind.Notifications => "Notifications",
            _ => null
        };
        builder.AddPhase10ServiceHostInfrastructure(
            consumerKind,
            enableOutboxPublisher: serviceKind == Phase10ServiceKind.Orders,
            enablePaymentReconciliation: serviceKind == Phase10ServiceKind.Payments);
        builder.Services.AddScoped<ITenantPaymentProviderResolver, TenantPaymentProviderResolver>();
        builder.InjectApplicationDependencies();
        var identityEnabled = builder.Configuration
            .GetSection("IdentityProvider")
            .GetValue("Enabled", false);
        if (identityEnabled)
        {
            builder.Services.AddAuthorization(options =>
            {
                options.FallbackPolicy = new AuthorizationPolicyBuilder()
                    .RequireAuthenticatedUser()
                    .Build();
            });
            builder.Services
                .AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = "KeycloakLocal";
                    options.DefaultChallengeScheme = "KeycloakLocal";
                })
                .AddScheme<AuthenticationSchemeOptions, KeycloakIntrospectionAuthenticationHandler>(
                    "KeycloakLocal",
                    _ => { });
        }
        else
        {
            builder.Services.AddAuthorization();
        }

        var controllerTypes = RegisterOwnedModules(builder, serviceKind);
        builder.Services
            .AddControllers()
            .ConfigureApplicationPartManager(manager =>
            {
                manager.ApplicationParts.Clear();
                manager.ApplicationParts.Add(
                    new AssemblyPart(typeof(InfoController).Assembly));
                foreach (var provider in manager.FeatureProviders
                    .OfType<ControllerFeatureProvider>()
                    .ToArray())
                {
                    manager.FeatureProviders.Remove(provider);
                }
                manager.FeatureProviders.Add(
                    new OwnedControllerFeatureProvider(controllerTypes));
            });
        builder.Services
            .AddApiVersioning(options =>
            {
                options.DefaultApiVersion = new ApiVersion(1, 0);
                options.AssumeDefaultVersionWhenUnspecified = true;
                options.ReportApiVersions = true;
                options.ApiVersionReader = new UrlSegmentApiVersionReader();
            })
            .AddMvc();

        var healthChecks = builder.Services.AddHealthChecks();
        var connectionString = builder.Configuration
            .GetConnectionString("OrderProcessingSystemDbConnection");
        if (!string.IsNullOrWhiteSpace(connectionString))
        {
            healthChecks.AddSqlServer(
                connectionString,
                name: "sqlserver",
                tags: ["ready"]);
        }
    }

    public static WebApplication MapPhase10OwnedService(
        this WebApplication app,
        Phase10ServiceKind serviceKind)
    {
        ArgumentNullException.ThrowIfNull(app);

        InitializePhase10OwnedServiceDatabase(app, serviceKind);

        if (app.Configuration.GetSection("IdentityProvider").GetValue("Enabled", false))
        {
            app.UseAuthentication();
        }
        app.UseAuthorization();
        app.UseMiddleware<TenantClaimConsistencyMiddleware>();
        app.UseMiddleware<TenantMiddleware>();
        app.MapControllers();
        app.MapGet("/", () => Results.Ok(new
        {
            service = $"XYDataLabs.OrderProcessingSystem.{serviceKind}",
            status = "healthy"
        })).AllowAnonymous();
        app.MapHealthChecks("/health", ReadyHealthOptions()).AllowAnonymous();
        app.MapHealthChecks("/health/ready", ReadyHealthOptions()).AllowAnonymous();
        app.MapHealthChecks("/health/live", new HealthCheckOptions
        {
            Predicate = _ => false
        }).AllowAnonymous();
        return app;
    }

    private static void InitializePhase10OwnedServiceDatabase(WebApplication app, Phase10ServiceKind serviceKind)
    {
        using var scope = app.Services.CreateScope();

        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var seedOrders = serviceKind == Phase10ServiceKind.Orders;
        var integrationEventMapperRegistry = seedOrders
            ? scope.ServiceProvider.GetRequiredService<IIntegrationEventMapperRegistry>()
            : null;

        DbInitializer.InitializeSharedPool(
            dbContext,
            app.Configuration,
            applyMigrations: true,
            seedOrders: seedOrders);
        DbInitializer.InitializeDedicatedTenants(
            dbContext,
            app.Configuration,
            applyMigrations: true,
            integrationEventMapperRegistry: integrationEventMapperRegistry,
            seedOrders: seedOrders);
    }

    private static Type[] RegisterOwnedModules(
        WebApplicationBuilder builder,
        Phase10ServiceKind serviceKind)
    {
        switch (serviceKind)
        {
            case Phase10ServiceKind.Orders:
                builder.Services.AddCqrs(typeof(OrdersModuleRegistration).Assembly);
                builder.Services.AddOrdersModule();
                builder.Services.AddInventoryModule();
                return
                [
                    typeof(InfoController),
                    typeof(CustomerController),
                    typeof(OrderController),
                    typeof(AuditController)
                ];
            case Phase10ServiceKind.Payments:
                builder.Services.AddCqrs(typeof(PaymentsModuleRegistration).Assembly);
                builder.Services.AddPaymentsModule();
                builder.Services.AddScoped<IPaymentProviderGateway>(serviceProvider =>
                {
                    var resolver = serviceProvider
                        .GetRequiredService<ITenantPaymentProviderResolver>();
                    var providerType = resolver.ResolveCurrentTenantProvider().ProviderType;
                    return serviceProvider
                        .GetRequiredKeyedService<IPaymentProviderGateway>(providerType);
                });
                builder.Services.AddOpenPayAdapter(builder.Configuration);
                builder.Services.AddRazorpayAdapter(builder.Configuration);
                if (builder.Configuration.GetValue(
                    "PaymentProviders:UseDeterministicAdapters",
                    false))
                {
                    builder.Services.AddKeyedSingleton<IPaymentProviderGateway>(
                        PaymentProviderTypes.OpenPay,
                        (_, _) => new DeterministicPaymentProviderGateway(
                            PaymentProviderTypes.OpenPay));
                    builder.Services.AddKeyedSingleton<IPaymentProviderGateway>(
                        PaymentProviderTypes.Razorpay,
                        (_, _) => new DeterministicPaymentProviderGateway(
                            PaymentProviderTypes.Razorpay));
                }
                builder.Services.AddScoped<IPaymentTelemetryTracker>(serviceProvider =>
                    new ApplicationInsightsPaymentTelemetryTracker(serviceProvider.GetService<TelemetryClient>()));
                builder.Services.AddOptions<PaymentGatewayRequestDefaults>()
                    .Bind(builder.Configuration.GetSection("OpenPay"));
                return
                [
                    typeof(PaymentsController),
                    typeof(PaymentCallbackController),
                    typeof(WebhookController),
                    typeof(DlqAdminController)
                ];
            case Phase10ServiceKind.Inventory:
                builder.Services.AddCqrs(typeof(InventoryModuleRegistration).Assembly);
                builder.Services.AddInventoryModule();
                return [typeof(InventoryController), typeof(ProductController)];
            case Phase10ServiceKind.Notifications:
                builder.Services.AddCqrs(typeof(NotificationsModuleRegistration).Assembly);
                builder.Services.AddNotificationsModule();
                return [typeof(NotificationsController)];
            default:
                throw new ArgumentOutOfRangeException(nameof(serviceKind), serviceKind, null);
        }
    }

    private static HealthCheckOptions ReadyHealthOptions()
        => new() { Predicate = check => check.Tags.Contains("ready") };
}
