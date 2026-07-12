using FluentAssertions;
using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests;

public sealed class GatewayTopologyTests
{
    [Fact]
    public void Gateway_AppSettings_Should_Define_The_Phase10_ContainerTopology()
    {
        var config = new ConfigurationBuilder()
            .AddJsonFile(Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Gateway\appsettings.json"), optional: false)
            .Build();

        config["ReverseProxy:Routes:orders-api-route:Match:Path"].Should().Be("/api/{**catch-all}");
        config["ReverseProxy:Routes:inventory-route:Match:Path"].Should().Be("/inventory/{**catch-all}");
        config["ReverseProxy:Routes:notifications-route:Match:Path"].Should().Be("/notifications/{**catch-all}");
        config["ReverseProxy:Routes:ui-route:Match:Path"].Should().Be("/app/{**catch-all}");

        config["ReverseProxy:Routes:orders-api-route:Match:Hosts:0"].Should().BeNull();
        config["ReverseProxy:Routes:inventory-route:Match:Hosts:0"].Should().BeNull();
        config["ReverseProxy:Routes:notifications-route:Match:Hosts:0"].Should().BeNull();
        config["ReverseProxy:Routes:ui-route:Match:Hosts:0"].Should().BeNull();

        config["Gateway:AllowedHosts:0"].Should().Be("localhost");
        config["Gateway:AllowedHosts:1"].Should().Be("orders.localhost");
        config["Gateway:AllowedHosts:2"].Should().Be("inventory.localhost");
        config["Gateway:AllowedHosts:3"].Should().Be("notifications.localhost");
        config["Gateway:AllowedHosts:4"].Should().Be("ui.localhost");
    }
}
