using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

internal sealed class GatewayWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly Uri _ordersBaseAddress;
    private readonly Uri _inventoryBaseAddress;
    private readonly Uri _notificationsBaseAddress;
    private readonly Uri _uiBaseAddress;

    public GatewayWebApplicationFactory(Uri ordersBaseAddress, Uri inventoryBaseAddress, Uri notificationsBaseAddress, Uri uiBaseAddress)
    {
        _ordersBaseAddress = ordersBaseAddress;
        _inventoryBaseAddress = inventoryBaseAddress;
        _notificationsBaseAddress = notificationsBaseAddress;
        _uiBaseAddress = uiBaseAddress;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, configBuilder) =>
        {
            configBuilder.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ReverseProxy:Routes:orders-api-route:ClusterId"] = "orders-cluster",
                ["ReverseProxy:Routes:orders-api-route:Match:Path"] = "/api/{**catch-all}",
                ["ReverseProxy:Routes:orders-api-route:Transforms:0:PathRemovePrefix"] = "/api",
                ["ReverseProxy:Routes:inventory-route:ClusterId"] = "inventory-cluster",
                ["ReverseProxy:Routes:inventory-route:Match:Path"] = "/inventory/{**catch-all}",
                ["ReverseProxy:Routes:inventory-route:Transforms:0:PathRemovePrefix"] = "/inventory",
                ["ReverseProxy:Routes:notifications-route:ClusterId"] = "notifications-cluster",
                ["ReverseProxy:Routes:notifications-route:Match:Path"] = "/notifications/{**catch-all}",
                ["ReverseProxy:Routes:notifications-route:Transforms:0:PathRemovePrefix"] = "/notifications",
                ["ReverseProxy:Routes:ui-route:ClusterId"] = "ui-cluster",
                ["ReverseProxy:Routes:ui-route:Match:Path"] = "/app/{**catch-all}",
                ["ReverseProxy:Routes:ui-route:Transforms:0:PathRemovePrefix"] = "/app",
                ["ReverseProxy:Clusters:orders-cluster:Destinations:orders-api:Address"] = _ordersBaseAddress.ToString(),
                ["ReverseProxy:Clusters:inventory-cluster:Destinations:inventory-api:Address"] = _inventoryBaseAddress.ToString(),
                ["ReverseProxy:Clusters:notifications-cluster:Destinations:notifications-api:Address"] = _notificationsBaseAddress.ToString(),
                ["ReverseProxy:Clusters:ui-cluster:Destinations:ui-primary:Address"] = _uiBaseAddress.ToString(),
                ["Gateway:AllowedHosts:0"] = "localhost",
                ["Gateway:AllowedHosts:1"] = "orders.localhost",
                ["Gateway:AllowedHosts:2"] = "inventory.localhost",
                ["Gateway:AllowedHosts:3"] = "notifications.localhost",
                ["Gateway:AllowedHosts:4"] = "ui.localhost",
                ["Gateway:AllowedHosts:5"] = "orderprocessing-gate-local",
                ["Gateway:MaxRequestBodySizeBytes"] = "1048576"
            });
        });
    }
}
