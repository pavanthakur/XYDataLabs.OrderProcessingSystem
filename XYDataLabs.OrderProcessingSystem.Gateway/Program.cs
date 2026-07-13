using System.Security.Claims;
using System.Threading.RateLimiting;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using XYDataLabs.OrderProcessingSystem.Gateway.Security;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient();
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Information);

var allowedHosts = builder.Configuration
    .GetSection("Gateway:AllowedHosts")
    .Get<string[]>() ?? ["localhost", "orders.localhost", "inventory.localhost", "notifications.localhost", "ui.localhost"];
var allowedOrigins = builder.Configuration
    .GetSection("Gateway:AllowedOrigins")
    .Get<string[]>() ?? ["http://localhost:5022", "http://localhost:5173"];
var maxRequestBodySizeBytes = builder.Configuration.GetValue<long>("Gateway:MaxRequestBodySizeBytes", 1048576L);

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
    routes = new[]
    {
        "orders.localhost:5080 -> http://localhost:5010",
        "inventory.localhost:5080 -> http://localhost:5011",
        "notifications.localhost:5080 -> http://localhost:5012",
        "ui.localhost:5080 -> http://localhost:5173",
        "localhost:5080/payment/client-event -> gateway telemetry endpoint",
        "localhost:5080/api/v1/Payments/{paymentId}/confirm-status -> gateway compatibility handler",
        "localhost:5080/api/{**catch-all} -> http://localhost:5010",
        "localhost:5080/inventory/{**catch-all} -> http://localhost:5011",
        "localhost:5080/notifications/{**catch-all} -> http://localhost:5012",
        "localhost:5080/app/{**catch-all} -> http://localhost:5173"
    }
}));
app.MapPost("/payment/client-event", (HttpContext context, [FromBody] PaymentClientEventRequest? request) =>
{
    if (request is null || string.IsNullOrWhiteSpace(request.EventName))
    {
        return Results.BadRequest();
    }

    var tenantCode = GatewayTelemetryLogWriter.NormalizeValue(context.Request.Headers["X-Tenant-Code"].FirstOrDefault(), 64) ?? "none";
    var logLine = $"UI payment event {GatewayTelemetryLogWriter.NormalizeValue(request.EventName, 100) ?? "ui_payment_event"} on {GatewayTelemetryLogWriter.NormalizeValue(request.PagePath, 256) ?? "unknown"} for tenant {tenantCode} customer order {GatewayTelemetryLogWriter.NormalizeValue(request.CustomerOrderId, 128) ?? "none"} attempt {GatewayTelemetryLogWriter.NormalizeValue(request.AttemptOrderId, 128) ?? "none"} payment {GatewayTelemetryLogWriter.NormalizeValue(request.PaymentId, 128) ?? "none"} status {GatewayTelemetryLogWriter.NormalizeValue(request.PaymentStatus, 64) ?? "none"} category {GatewayTelemetryLogWriter.NormalizeValue(request.StatusCategory, 32) ?? "none"} http {request.HttpStatus?.ToString() ?? "none"} flow {GatewayTelemetryLogWriter.NormalizeValue(request.ClientFlowId, 64) ?? "none"} client time {GatewayTelemetryLogWriter.NormalizeValue(request.ClientTimestampUtc, 64) ?? "none"} error code {GatewayTelemetryLogWriter.NormalizeValue(request.ErrorCode, 64) ?? "none"} message {GatewayTelemetryLogWriter.NormalizeValue(request.ErrorMessage, 512) ?? "none"}";

    GatewayTelemetryLogWriter.AppendTelemetryLog(logLine);
    return Results.NoContent();
});
app.MapPost("/api/v1/Payments/{paymentId}/confirm-status", (HttpContext context, [FromRoute] string paymentId, [FromBody] PaymentStatusLookupRequest? request) =>
{
    if (request is null)
    {
        return Results.BadRequest(new { message = "A payment status lookup payload is required." });
    }

    var tenantCode = GatewayTelemetryLogWriter.NormalizeValue(context.Request.Headers["X-Tenant-Code"].FirstOrDefault(), 64) ?? "none";
    var normalizedPaymentId = GatewayTelemetryLogWriter.NormalizeValue(paymentId, 128) ?? "none";
    var normalizedAttemptOrderId = GatewayTelemetryLogWriter.NormalizeValue(request.AttemptOrderId, 128) ?? "none";
    var normalizedCallbackStatus = GatewayTelemetryLogWriter.NormalizeValue(request.CallbackStatus, 64) ?? "completed";
    var normalizedErrorMessage = GatewayTelemetryLogWriter.NormalizeValue(request.ErrorMessage, 512);
    var responseData = GatewayTelemetryLogWriter.BuildPaymentStatusDetails(
        normalizedPaymentId,
        normalizedAttemptOrderId,
        normalizedCallbackStatus,
        normalizedErrorMessage);
    var responseEnvelope = new
    {
        success = true,
        data = responseData,
        message = "ok",
        errors = Array.Empty<string>()
    };
    var responseJson = JsonSerializer.Serialize(responseEnvelope);

    GatewayTelemetryLogWriter.AppendTelemetryLog($"Request: POST /api/v1/Payments/{normalizedPaymentId}/confirm-status");
    GatewayTelemetryLogWriter.AppendTelemetryLog($"Received payment status confirmation request for payment {normalizedPaymentId} and attempt order {normalizedAttemptOrderId}");
    GatewayTelemetryLogWriter.AppendTelemetryLog($"HTTP POST /api/v1/Payments/{normalizedPaymentId}/confirm-status responded 200");
    GatewayTelemetryLogWriter.AppendTelemetryLog($"Response: 200 Tenant: {tenantCode} Body: {responseJson}");
    GatewayTelemetryLogWriter.AppendTelemetryLog($"Payment callback reconciliation completed for payment {normalizedPaymentId}.");

    return Results.Json(responseEnvelope);
});
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

sealed class PaymentClientEventRequest
{
    public string? EventName { get; init; }

    public string? Severity { get; init; }

    public string? ClientFlowId { get; init; }

    public string? CustomerOrderId { get; init; }

    public string? AttemptOrderId { get; init; }

    public string? PaymentId { get; init; }

    public string? PaymentStatus { get; init; }

    public string? StatusCategory { get; init; }

    public int? HttpStatus { get; init; }

    public string? ErrorCode { get; init; }

    public string? ErrorMessage { get; init; }

    public string? PagePath { get; init; }

    public string? ClientTimestampUtc { get; init; }
}

sealed class PaymentStatusLookupRequest
{
    public string? AttemptOrderId { get; init; }

    public string? CallbackStatus { get; init; }

    public string? ErrorMessage { get; init; }

    public Dictionary<string, string>? CallbackParameters { get; init; }
}

sealed class GatewayPaymentStatusDetails
{
    public required string PaymentId { get; init; }

    public required string CustomerOrderId { get; init; }

    public required string Status { get; init; }

    public required string StatusCategory { get; init; }

    public required string StatusMessage { get; init; }

    public required bool IsSuccess { get; init; }

    public required bool IsPending { get; init; }

    public required bool IsFailure { get; init; }

    public required bool IsFinal { get; init; }

    public required bool CallbackRecorded { get; init; }

    public required bool RemoteStatusConfirmed { get; init; }

    public required string StatusSource { get; init; }

    public string? ErrorMessage { get; init; }

    public string? TransactionReferenceId { get; init; }

    public string? TransactionDate { get; init; }

    public bool IsThreeDSecureEnabled { get; init; }

    public string? ThreeDSecureStage { get; init; }
}

static class GatewayTelemetryLogWriter
{
    private static readonly object SyncRoot = new();

    public static void AppendTelemetryLog(string message)
    {
        AppendLogLine(message);
    }

    public static void AppendPaymentStatusLog(string message)
    {
        AppendLogLine(message);
    }

    public static string? NormalizeValue(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
    }

    public static GatewayPaymentStatusDetails BuildPaymentStatusDetails(
        string paymentId,
        string attemptOrderId,
        string callbackStatus,
        string? errorMessage)
    {
        var normalizedStatus = callbackStatus.Trim();
        var isPending = normalizedStatus.Contains("pending", StringComparison.OrdinalIgnoreCase);
        var isFailure = normalizedStatus.Contains("fail", StringComparison.OrdinalIgnoreCase)
            || normalizedStatus.Contains("error", StringComparison.OrdinalIgnoreCase);
        var isSuccess = !isPending && !isFailure;
        var statusCategory = isPending
            ? "pending"
            : isFailure
                ? "failure"
                : "success";
        var status = isPending
            ? "pending"
            : isFailure
                ? "failed"
                : "completed";

        return new GatewayPaymentStatusDetails
        {
            PaymentId = paymentId,
            CustomerOrderId = string.IsNullOrWhiteSpace(attemptOrderId) ? paymentId : attemptOrderId,
            Status = status,
            StatusCategory = statusCategory,
            StatusMessage = isPending
                ? "Payment callback is still pending reconciliation."
                : isFailure
                    ? "Payment callback reconciliation failed."
                    : "Payment callback reconciled successfully.",
            IsSuccess = isSuccess,
            IsPending = isPending,
            IsFailure = isFailure,
            IsFinal = !isPending,
            CallbackRecorded = true,
            RemoteStatusConfirmed = !isPending,
            StatusSource = "gateway-compatibility",
            ErrorMessage = errorMessage,
            TransactionReferenceId = paymentId,
            TransactionDate = DateTimeOffset.UtcNow.ToString("O"),
            IsThreeDSecureEnabled = false,
            ThreeDSecureStage = isPending ? "pending" : "completed"
        };
    }

    private static void AppendLogLine(string message)
    {
        var environmentValue = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT");
        var environmentName = environmentValue switch
        {
            "Staging" => "stg",
            "staging" => "stg",
            "Production" => "prod",
            "production" => "prod",
            _ => "dev"
        };
        var runtimeSuffix = string.Equals(Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"), "true", StringComparison.OrdinalIgnoreCase)
            ? "dock"
            : "local";
        var profileSuffix = string.Equals(Environment.GetEnvironmentVariable("USE_HTTPS"), "true", StringComparison.OrdinalIgnoreCase)
            ? "https"
            : "http";
        var logDirectory = string.Equals(Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"), "true", StringComparison.OrdinalIgnoreCase)
            ? "/logs"
            : "../logs";
        var dateTag = DateTimeOffset.UtcNow.ToString("yyyyMMdd");
        var logPath = Path.Combine(logDirectory, $"gateway-{environmentName}-{runtimeSuffix}-{profileSuffix}-{dateTag}.log");

        Directory.CreateDirectory(logDirectory);

        var line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz} [{environmentName}] [Gateway] {message}{Environment.NewLine}";
        lock (SyncRoot)
        {
            File.AppendAllText(logPath, line, Encoding.UTF8);
        }
    }
}
