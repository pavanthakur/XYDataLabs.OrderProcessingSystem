using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

internal sealed class GatewayWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly Uri _ordersBaseAddress;
    private readonly Uri _uiBaseAddress;

    public GatewayWebApplicationFactory(Uri ordersBaseAddress, Uri uiBaseAddress)
    {
        _ordersBaseAddress = ordersBaseAddress;
        _uiBaseAddress = uiBaseAddress;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, configBuilder) =>
        {
            configBuilder.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ReverseProxy:Clusters:orders-cluster:Destinations:orders-api:Address"] = _ordersBaseAddress.ToString(),
                ["ReverseProxy:Clusters:ui-cluster:Destinations:web-ui:Address"] = _uiBaseAddress.ToString(),
                ["Gateway:AllowedHosts:0"] = "localhost",
                ["Gateway:AllowedHosts:1"] = "orders.localhost",
                ["Gateway:AllowedHosts:2"] = "ui.localhost",
                ["Gateway:MaxRequestBodySizeBytes"] = "1048576"
            });
        });
    }
}