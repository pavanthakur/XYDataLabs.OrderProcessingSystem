using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

var allowedHosts = builder.Configuration
    .GetSection("Gateway:AllowedHosts")
    .Get<string[]>() ?? ["localhost", "orders.localhost", "ui.localhost"];
var maxRequestBodySizeBytes = builder.Configuration.GetValue<long>("Gateway:MaxRequestBodySizeBytes", 1048576L);

builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
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

app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/health", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }

    if (!allowedHosts.Contains(context.Request.Host.Host, StringComparer.OrdinalIgnoreCase))
    {
        await Results.Problem(
            title: "Unsupported gateway host.",
            detail: $"Host '{context.Request.Host.Host}' is not configured for this gateway.",
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

app.MapHealthChecks("/health/alive");
app.MapHealthChecks("/health/ready");
app.MapGet("/", () => Results.Ok(new
{
    service = "XYDataLabs.OrderProcessingSystem.Gateway",
    status = "healthy",
    routes = new[]
    {
        "orders.localhost:5080 -> http://localhost:5010",
        "ui.localhost:5080 -> http://localhost:5173",
        "localhost:5080/api/{**catch-all} -> http://localhost:5010",
        "localhost:5080/app/{**catch-all} -> http://localhost:5173"
    }
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

public partial class Program;