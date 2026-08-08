using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.HttpOverrides;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using XYDataLabs.OrderProcessingSystem.Gateway.Security;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient();
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Information);

var allowedHosts = builder.Configuration
    .GetSection("Gateway:AllowedHosts")
    .Get<string[]>() ?? ["localhost", "orders.localhost", "payments.localhost", "inventory.localhost", "notifications.localhost", "ui.localhost"];
var allowedOrigins = builder.Configuration
    .GetSection("Gateway:AllowedOrigins")
    .Get<string[]>() ?? ["http://localhost:5022", "http://localhost:5173"];
var maxRequestBodySizeBytes = builder.Configuration.GetValue<long>("Gateway:MaxRequestBodySizeBytes", 1048576L);
var configuredRouteSummaries = builder.Configuration
    .GetSection("ReverseProxy:Clusters")
    .GetChildren()
    .SelectMany(clusterSection =>
    {
        var destinationSections = clusterSection.GetSection("Destinations").GetChildren();
        return destinationSections.Select(destinationSection =>
            $"{clusterSection.Key}/{destinationSection.Key} -> {destinationSection["Address"] ?? "(missing)"}");
    })
    .ToArray();

builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.AddServiceDefaults("XYDataLabs.OrderProcessingSystem.Gateway");
builder.Services.AddAuthorization();
builder.Services.AddCors(options =>
{
    options.AddPolicy("local-phase10-browser", policy =>
    {
        policy.WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

var identityProviderSection = builder.Configuration.GetSection("IdentityProvider");
var identityEnabled = identityProviderSection.GetValue("Enabled", false);
if (identityEnabled)
{
    builder.Services
        .AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = "KeycloakLocal";
            options.DefaultChallengeScheme = "KeycloakLocal";
        })
        .AddScheme<AuthenticationSchemeOptions, KeycloakIntrospectionAuthenticationHandler>("KeycloakLocal", _ => { });
}

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("gateway-fixed-window", httpContext =>
    {
        var tenantOrHost = httpContext.Request.Headers["X-Tenant-Code"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(tenantOrHost))
        {
            tenantOrHost = httpContext.Request.Host.Host;
        }

        return RateLimitPartition.GetFixedWindowLimiter(tenantOrHost ?? "anonymous", _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 120,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        });
    });
});
builder.Services
    .AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();

app.UseExceptionHandler();
app.UseForwardedHeaders();
app.UseCors("local-phase10-browser");
if (identityEnabled)
{
    app.UseAuthentication();
    app.Use(async (context, next) =>
    {
        var path = context.Request.Path;
        var isAnonymousPath =
            path.StartsWithSegments("/health", StringComparison.OrdinalIgnoreCase)
            || path.Equals("/", StringComparison.OrdinalIgnoreCase)
            || path.StartsWithSegments("/api/v1/info", StringComparison.OrdinalIgnoreCase)
            || path.StartsWithSegments("/payment/callback", StringComparison.OrdinalIgnoreCase)
            || path.StartsWithSegments("/payments/callback", StringComparison.OrdinalIgnoreCase)
            || path.Value?.Contains("/webhook/", StringComparison.OrdinalIgnoreCase) == true;

        if (!isAnonymousPath && context.User.Identity?.IsAuthenticated != true)
        {
            await context.ChallengeAsync().ConfigureAwait(false);
            return;
        }

        await next().ConfigureAwait(false);
    });
    app.UseMiddleware<TenantClaimConsistencyMiddleware>();
}

app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/health", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }

    var requestHost = context.Request.Host.Host;
    var isAzureContainerAppsHost = requestHost.EndsWith(".azurecontainerapps.io", StringComparison.OrdinalIgnoreCase);
    var isInternalGatewayServiceHost = requestHost.StartsWith("orderprocessing-gate-", StringComparison.OrdinalIgnoreCase);
    var isAllowedHost = allowedHosts.Contains(requestHost, StringComparer.OrdinalIgnoreCase)
        || isAzureContainerAppsHost
        || isInternalGatewayServiceHost;

    if (!isAllowedHost)
    {
        await Results.Problem(
            title: "Unsupported gateway host.",
            detail: $"Host '{requestHost}' is not configured for this gateway.",
            statusCode: StatusCodes.Status400BadRequest,
            extensions: new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["correlationId"] = context.TraceIdentifier
            }).ExecuteAsync(context);
        return;
    }

    if (context.Request.ContentLength is long contentLength && contentLength > maxRequestBodySizeBytes)
    {
        await Results.Problem(
            title: "Request payload too large.",
            detail: $"Requests larger than {maxRequestBodySizeBytes} bytes are rejected at the gateway.",
            statusCode: StatusCodes.Status413PayloadTooLarge,
            extensions: new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["correlationId"] = context.TraceIdentifier
            }).ExecuteAsync(context);
        return;
    }

    context.Response.Headers.TryAdd("X-Correlation-Id", context.TraceIdentifier);
    await next();
});

app.UseRateLimiter();

app.MapDefaultEndpoints();
app.MapGet("/", (HttpContext context) => Results.Ok(new
{
    service = "XYDataLabs.OrderProcessingSystem.Gateway",
    status = "healthy",
    acceptedHost = context.Request.Host.Host,
    summary = $"Accepted host: {context.Request.Host.Host}",
    routes = configuredRouteSummaries
}));
app.MapReverseProxy(proxyPipeline =>
{
    proxyPipeline.Use(async (context, next) =>
    {
        context.Request.Headers.TryAdd("X-Correlation-Id", context.TraceIdentifier);
        await next().ConfigureAwait(false);
    });
});

await app.RunAsync();

public partial class Program
{
    protected Program()
    {
    }
}
