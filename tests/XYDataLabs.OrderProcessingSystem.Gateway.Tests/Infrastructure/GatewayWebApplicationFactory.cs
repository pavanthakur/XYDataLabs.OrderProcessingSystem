using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

internal sealed class GatewayWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly Uri _ordersBaseAddress;
    private readonly Uri _paymentsBaseAddress;
    private readonly Uri _inventoryBaseAddress;
    private readonly Uri _notificationsBaseAddress;
    private readonly Uri _uiBaseAddress;

    public GatewayWebApplicationFactory(
        Uri ordersBaseAddress,
        Uri paymentsBaseAddress,
        Uri inventoryBaseAddress,
        Uri notificationsBaseAddress,
        Uri uiBaseAddress)
    {
        _ordersBaseAddress = ordersBaseAddress;
        _paymentsBaseAddress = paymentsBaseAddress;
        _inventoryBaseAddress = inventoryBaseAddress;
        _notificationsBaseAddress = notificationsBaseAddress;
        _uiBaseAddress = uiBaseAddress;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            services.AddDataProtection().UseEphemeralDataProtectionProvider();
        });
        builder.ConfigureAppConfiguration((_, configBuilder) =>
        {
            configBuilder.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ReverseProxy:Routes:orders-order-api-route:ClusterId"] = "orders-cluster",
                ["ReverseProxy:Routes:orders-order-api-route:Order"] = "20",
                ["ReverseProxy:Routes:orders-order-api-route:Match:Path"] = "/api/v{version}/Order/{**catch-all}",
                ["ReverseProxy:Routes:orders-customer-api-route:ClusterId"] = "orders-cluster",
                ["ReverseProxy:Routes:orders-customer-api-route:Order"] = "20",
                ["ReverseProxy:Routes:orders-customer-api-route:Match:Path"] = "/api/v{version}/Customer/{**catch-all}",
                ["ReverseProxy:Routes:orders-audit-api-route:ClusterId"] = "orders-cluster",
                ["ReverseProxy:Routes:orders-audit-api-route:Order"] = "20",
                ["ReverseProxy:Routes:orders-audit-api-route:Match:Path"] = "/api/v{version}/Audit/{**catch-all}",
                ["ReverseProxy:Routes:orders-info-api-route:ClusterId"] = "orders-cluster",
                ["ReverseProxy:Routes:orders-info-api-route:Order"] = "20",
                ["ReverseProxy:Routes:orders-info-api-route:Match:Path"] = "/api/v{version}/Info/{**catch-all}",
                ["ReverseProxy:Routes:payments-api-route:ClusterId"] = "payments-cluster",
                ["ReverseProxy:Routes:payments-api-route:Order"] = "10",
                ["ReverseProxy:Routes:payments-api-route:Match:Path"] = "/api/v{version}/Payments/{**catch-all}",
                ["ReverseProxy:Routes:product-api-route:ClusterId"] = "inventory-cluster",
                ["ReverseProxy:Routes:product-api-route:Order"] = "10",
                ["ReverseProxy:Routes:product-api-route:Match:Path"] = "/api/v{version}/Product/{**catch-all}",
                ["ReverseProxy:Routes:inventory-api-route:ClusterId"] = "inventory-cluster",
                ["ReverseProxy:Routes:inventory-api-route:Order"] = "10",
                ["ReverseProxy:Routes:inventory-api-route:Match:Path"] = "/api/v{version}/Inventory/{**catch-all}",
                ["ReverseProxy:Routes:notifications-api-route:ClusterId"] = "notifications-cluster",
                ["ReverseProxy:Routes:notifications-api-route:Order"] = "10",
                ["ReverseProxy:Routes:notifications-api-route:Match:Path"] = "/api/v{version}/Notifications/{**catch-all}",
                ["ReverseProxy:Routes:inventory-route:ClusterId"] = "inventory-cluster",
                ["ReverseProxy:Routes:inventory-route:Match:Path"] = "/inventory/{**catch-all}",
                ["ReverseProxy:Routes:inventory-route:Transforms:0:PathRemovePrefix"] = "/inventory",
                ["ReverseProxy:Routes:notifications-route:ClusterId"] = "notifications-cluster",
                ["ReverseProxy:Routes:notifications-route:Match:Path"] = "/notifications/{**catch-all}",
                ["ReverseProxy:Routes:notifications-route:Transforms:0:PathRemovePrefix"] = "/notifications",
                ["ReverseProxy:Routes:ui-route:ClusterId"] = "ui-cluster",
                ["ReverseProxy:Routes:ui-route:Match:Path"] = "/app/{**catch-all}",
                ["ReverseProxy:Routes:ui-route:Transforms:0:PathRemovePrefix"] = "/app",
                ["ReverseProxy:Clusters:orders-cluster:Destinations:orders-primary:Address"] = _ordersBaseAddress.ToString(),
                ["ReverseProxy:Clusters:payments-cluster:Destinations:payments-primary:Address"] = _paymentsBaseAddress.ToString(),
                ["ReverseProxy:Clusters:inventory-cluster:Destinations:inventory-primary:Address"] = _inventoryBaseAddress.ToString(),
                ["ReverseProxy:Clusters:notifications-cluster:Destinations:notifications-primary:Address"] = _notificationsBaseAddress.ToString(),
                ["ReverseProxy:Clusters:ui-cluster:Destinations:ui-primary:Address"] = _uiBaseAddress.ToString(),
                ["Gateway:AllowedHosts:0"] = "localhost",
                ["Gateway:AllowedHosts:1"] = "orders.localhost",
                ["Gateway:AllowedHosts:2"] = "inventory.localhost",
                ["Gateway:AllowedHosts:3"] = "notifications.localhost",
                ["Gateway:AllowedHosts:4"] = "payments.localhost",
                ["Gateway:AllowedHosts:5"] = "ui.localhost",
                ["Gateway:AllowedHosts:6"] = "orderprocessing-gate-local",
                ["Gateway:MaxRequestBodySizeBytes"] = "1048576"
            });
        });
    }
}
