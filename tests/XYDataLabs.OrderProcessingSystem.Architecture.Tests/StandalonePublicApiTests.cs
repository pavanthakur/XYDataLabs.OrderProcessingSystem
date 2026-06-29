using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.Payments.API;
using XYDataLabs.OrderProcessingSystem.Tenants.API;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class StandaloneAPITests
{
    [Fact]
    public void Standalone_API_Projects_Should_Expose_The_Module_Contracts()
    {
        typeof(IOrderModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Orders.API");
        typeof(IInventoryModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.API");
        typeof(INotificationsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.API");
        typeof(IPaymentsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Payments.API");
        typeof(ITenantRegistryApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Tenants.API");
    }
}

