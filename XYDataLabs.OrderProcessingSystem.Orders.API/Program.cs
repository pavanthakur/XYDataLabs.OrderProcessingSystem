using System.Net.Mime;

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

app.MapGet("/api/v1/Info/payment-configuration", () => Results.Json(new
{
    activeProviderType = "OpenPay",
    activeProviderName = "OpenPay Sandbox",
    collectionMode = "Local",
    browserKey = "local-browser-key",
    browserMerchantId = "local-merchant-id",
    isProduction = false,
    isThreeDSecure = false
}, contentType: MediaTypeNames.Application.Json));
app.MapGet("/v1/Info/payment-configuration", () => Results.Json(new
{
    activeProviderType = "OpenPay",
    activeProviderName = "OpenPay Sandbox",
    collectionMode = "Local",
    browserKey = "local-browser-key",
    browserMerchantId = "local-merchant-id",
    isProduction = false,
    isThreeDSecure = false
}, contentType: MediaTypeNames.Application.Json));

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

public partial class Program;
