using System.Net.Mime;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();

var app = builder.Build();

var availableTenants = new[]
{
    new { tenantId = 1, tenantCode = "TenantA", tenantName = "Tenant A" },
    new { tenantId = 2, tenantCode = "TenantB", tenantName = "Tenant B" },
    new { tenantId = 3, tenantCode = "TenantC", tenantName = "Tenant C" }
};

var customers = new[]
{
    new
    {
        customerId = 101,
        name = "Avery Morgan",
        email = "avery.morgan@example.local",
        orderDtos = Array.Empty<object>()
    },
    new
    {
        customerId = 102,
        name = "Jordan Lee",
        email = "jordan.lee@example.local",
        orderDtos = Array.Empty<object>()
    },
    new
    {
        customerId = 103,
        name = "Taylor Brooks",
        email = "taylor.brooks@example.local",
        orderDtos = Array.Empty<object>()
    }
};

app.MapGet("/api/v1/Info/runtime-configuration", () => Results.Json(new
{
    activeTenantCode = "TenantA",
    configuredActiveTenantCode = "TenantA",
    tenantHeaderName = "X-Tenant-Code",
    availableTenants
}, contentType: MediaTypeNames.Application.Json));
app.MapGet("/v1/Info/runtime-configuration", () => Results.Json(new
{
    activeTenantCode = "TenantA",
    configuredActiveTenantCode = "TenantA",
    tenantHeaderName = "X-Tenant-Code",
    availableTenants
}, contentType: MediaTypeNames.Application.Json));

var tenantRegistry = new[]
{
    new
    {
        tenantId = 1,
        tenantCode = "TenantA",
        tenantName = "Tenant A",
        tenantTier = "SharedPool",
        paymentProviderCode = "Razorpay"
    },
    new
    {
        tenantId = 2,
        tenantCode = "TenantB",
        tenantName = "Tenant B",
        tenantTier = "SharedPool",
        paymentProviderCode = "Razorpay"
    },
    new
    {
        tenantId = 3,
        tenantCode = "TenantC",
        tenantName = "Tenant C",
        tenantTier = "Dedicated",
        paymentProviderCode = "OpenPay"
    }
};

app.MapGet("/api/v1/Info/tenant-registry", () => Results.Json(tenantRegistry, contentType: MediaTypeNames.Application.Json));
app.MapGet("/v1/Info/tenant-registry", () => Results.Json(tenantRegistry, contentType: MediaTypeNames.Application.Json));

app.MapGet("/api/v1/Info/payment-configuration", (HttpContext httpContext) =>
    Results.Json(BuildPaymentConfiguration(httpContext), contentType: MediaTypeNames.Application.Json));
app.MapGet("/v1/Info/payment-configuration", (HttpContext httpContext) =>
    Results.Json(BuildPaymentConfiguration(httpContext), contentType: MediaTypeNames.Application.Json));

app.MapGet("/api/v1/Customer/GetAllCustomers", () => Results.Json(new
{
    success = true,
    data = customers,
    message = "ok",
    errors = Array.Empty<string>()
}, contentType: MediaTypeNames.Application.Json));
app.MapGet("/v1/Customer/GetAllCustomers", () => Results.Json(new
{
    success = true,
    data = customers,
    message = "ok",
    errors = Array.Empty<string>()
}, contentType: MediaTypeNames.Application.Json));

app.MapGet("/api/v1/Customer/GetAllCustomersByName", (string? name, int? pageNumber, int? pageSize) =>
{
    var filtered = string.IsNullOrWhiteSpace(name)
        ? customers
        : customers.Where(customer => customer.name.Contains(name, StringComparison.OrdinalIgnoreCase)).ToArray();

    return Results.Json(new
    {
        success = true,
        data = filtered,
        message = "ok",
        errors = Array.Empty<string>(),
        pageNumber = pageNumber ?? 1,
        pageSize = pageSize ?? 10
    }, contentType: MediaTypeNames.Application.Json);
});
app.MapGet("/v1/Customer/GetAllCustomersByName", (string? name, int? pageNumber, int? pageSize) =>
{
    var filtered = string.IsNullOrWhiteSpace(name)
        ? customers
        : customers.Where(customer => customer.name.Contains(name, StringComparison.OrdinalIgnoreCase)).ToArray();

    return Results.Json(new
    {
        success = true,
        data = filtered,
        message = "ok",
        errors = Array.Empty<string>(),
        pageNumber = pageNumber ?? 1,
        pageSize = pageSize ?? 10
    }, contentType: MediaTypeNames.Application.Json);
});

app.MapGet("/api/v1/Customer/{customerId:int}", (int customerId) =>
{
    var customer = customers.FirstOrDefault(item => item.customerId == customerId);
    return customer is null
        ? Results.NotFound()
        : Results.Json(new
        {
            success = true,
            data = customer,
            message = "ok",
            errors = Array.Empty<string>()
        }, contentType: MediaTypeNames.Application.Json);
});
app.MapGet("/v1/Customer/{customerId:int}", (int customerId) =>
{
    var customer = customers.FirstOrDefault(item => item.customerId == customerId);
    return customer is null
        ? Results.NotFound()
        : Results.Json(new
        {
            success = true,
            data = customer,
            message = "ok",
            errors = Array.Empty<string>()
        }, contentType: MediaTypeNames.Application.Json);
});

app.MapPost("/api/v1/Payments/ProcessPayment", (JsonElement request, HttpContext httpContext) =>
    Results.Json(BuildSuccessfulPaymentEnvelope(request, httpContext), contentType: MediaTypeNames.Application.Json));
app.MapPost("/v1/Payments/ProcessPayment", (JsonElement request, HttpContext httpContext) =>
    Results.Json(BuildSuccessfulPaymentEnvelope(request, httpContext), contentType: MediaTypeNames.Application.Json));

app.MapPost("/api/v1/Payments/{paymentId}/confirm-status", (string paymentId, JsonElement request, HttpContext httpContext) =>
    Results.Json(BuildConfirmedPaymentEnvelope(paymentId, request, httpContext), contentType: MediaTypeNames.Application.Json));
app.MapPost("/v1/Payments/{paymentId}/confirm-status", (string paymentId, JsonElement request, HttpContext httpContext) =>
    Results.Json(BuildConfirmedPaymentEnvelope(paymentId, request, httpContext), contentType: MediaTypeNames.Application.Json));

app.MapPost("/payment/client-event", () => Results.NoContent());

app.MapGet("/", () => Results.Ok(new
{
    service = "XYDataLabs.OrderProcessingSystem.Orders",
    status = "healthy"
}));

app.MapHealthChecks("/health");
app.MapHealthChecks("/health/live", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = _ => false
});

await app.RunAsync();

static object BuildPaymentConfiguration(HttpContext httpContext)
{
    var tenantCode = ResolveTenantCode(httpContext);
    var provider = tenantCode.Equals("TenantC", StringComparison.OrdinalIgnoreCase)
        ? "OpenPay"
        : "Razorpay";

    return new
    {
        activeProviderType = provider,
        activeProviderName = $"{provider} Phase 10 API Smoke",
        collectionMode = "api_smoke",
        browserKey = "phase10-api-smoke-key",
        browserMerchantId = "phase10-api-smoke-merchant",
        isProduction = false,
        isThreeDSecure = false
    };
}

static object BuildSuccessfulPaymentEnvelope(JsonElement request, HttpContext httpContext)
{
    var tenantCode = ResolveTenantCode(httpContext);
    var provider = tenantCode.Equals("TenantC", StringComparison.OrdinalIgnoreCase)
        ? "openpay"
        : "razorpay";
    var paymentId = $"{provider}-phase10-{Guid.NewGuid():N}";
    var requestedCustomerOrderId = GetOptionalJsonString(request, "customerOrderId");
    var customerOrderId = string.IsNullOrWhiteSpace(requestedCustomerOrderId)
        ? $"PHASE10-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}"
        : requestedCustomerOrderId;

    return new
    {
        success = true,
        data = new
        {
            id = paymentId,
            customerOrderId,
            customerId = $"{tenantCode}-automation",
            amount = 100.00m,
            currency = "INR",
            status = "completed",
            createdAt = DateTimeOffset.UtcNow,
            transactionId = $"txn-{paymentId}",
            errorMessage = (string?)null,
            threeDSecureUrl = (string?)null,
            isThreeDSecureEnabled = false,
            threeDSecureStage = "not-applicable"
        },
        message = "Phase 10 payment smoke completed.",
        errors = Array.Empty<string>()
    };
}

static object BuildConfirmedPaymentEnvelope(string paymentId, JsonElement request, HttpContext httpContext)
{
    var attemptOrderId = GetOptionalJsonString(request, "attemptOrderId");
    var customerOrderId = !string.IsNullOrWhiteSpace(attemptOrderId)
        ? attemptOrderId
        : $"PHASE10-{ResolveTenantCode(httpContext)}";

    return new
    {
        success = true,
        data = new
        {
            paymentId,
            customerOrderId,
            status = "completed",
            statusCategory = "success",
            statusMessage = "Phase 10 payment smoke completed successfully.",
            isSuccess = true,
            isPending = false,
            isFailure = false,
            isFinal = true,
            callbackRecorded = true,
            remoteStatusConfirmed = true,
            statusSource = "Phase 10 split Orders API smoke",
            errorMessage = (string?)null,
            transactionReferenceId = $"auth-{paymentId}",
            transactionDate = DateTimeOffset.UtcNow,
            threeDSecureUrl = (string?)null,
            isThreeDSecureEnabled = false,
            threeDSecureStage = "not-applicable"
        },
        message = "Phase 10 payment status confirmed.",
        errors = Array.Empty<string>()
    };
}

static string ResolveTenantCode(HttpContext httpContext)
{
    return httpContext.Request.Headers.TryGetValue("X-Tenant-Code", out var tenantHeader)
        && !string.IsNullOrWhiteSpace(tenantHeader.ToString())
        ? tenantHeader.ToString()
        : "TenantA";
}

static string? GetOptionalJsonString(JsonElement source, string propertyName)
{
    return source.ValueKind == JsonValueKind.Object
        && source.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
        ? property.GetString()
        : null;
}

public partial class Program;
