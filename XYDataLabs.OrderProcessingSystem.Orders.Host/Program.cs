using System.Threading.RateLimiting;
using Asp.Versioning;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.Host;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

var builder = WebApplication.CreateBuilder(args);

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

builder.Configuration.LoadSharedSettings(environmentName, isDocker);
builder.AddServiceDefaults("XYDataLabs.OrderProcessingSystem.Orders.Host");
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

builder.AddPhase10ServiceHostInfrastructure(consumerKind: "Orders", enableOutboxPublisher: true);
builder.InjectApplicationDependencies();
builder.Services.AddCqrs(typeof(OrdersModuleRegistration).Assembly);
builder.Services.AddOrdersModule();
builder.Services.AddInventoryModule();

builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

var identityEnabled = builder.Configuration
    .GetSection("IdentityProvider")
    .GetValue("Enabled", false);
if (identityEnabled)
{
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

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("api-per-tenant", httpContext =>
    {
        var tenantCode = httpContext.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault() ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(tenantCode, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 200,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        });
    });
});

builder.Services
    .AddControllers()
    .AddApplicationPart(AssemblyReference.Assembly);
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
var connectionString = builder.Configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
if (!string.IsNullOrWhiteSpace(connectionString))
{
    healthChecks.AddSqlServer(
        connectionString,
        name: "sqlserver",
        tags: ["ready"]);
}

var app = builder.Build();

app.UseExceptionHandler();
if (identityEnabled)
{
    app.UseAuthentication();
}
app.UseAuthorization();
app.UseMiddleware<TenantClaimConsistencyMiddleware>();
app.UseMiddleware<TenantMiddleware>();
app.UseRateLimiter();

app.MapControllers();
app.MapDefaultEndpoints();
app.MapHealthChecks("/health", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready", StringComparer.OrdinalIgnoreCase)
}).AllowAnonymous();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
}).AllowAnonymous();
app.MapGet("/", () => Results.Ok(new
{
    service = "XYDataLabs.OrderProcessingSystem.Orders",
    status = "healthy"
})).AllowAnonymous();

await app.RunAsync();

public partial class Program;
