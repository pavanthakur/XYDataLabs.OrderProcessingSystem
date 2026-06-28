using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.Payments.API;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class ModuleBoundaryTests
    {
        [Fact]
        public void APIContracts_Should_Expose_The_Final_Module_Surface()
        {
            typeof(IOrderModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Orders.API");
            typeof(IInventoryModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.API");
            typeof(INotificationsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.API");
            typeof(IPaymentsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Payments.API");
        }
    }
}

