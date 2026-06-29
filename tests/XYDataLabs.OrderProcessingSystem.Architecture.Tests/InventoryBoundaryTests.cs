using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Application.API.Services;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class InventoryBoundaryTests
    {
        [Fact]
        public void Inventory_API_Should_Stay_In_The_Application_Surface()
        {
            typeof(IInventoryModuleApi).Assembly.Should().NotBeSameAs(typeof(InventoryService).Assembly);
            typeof(IInventoryModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.API");
            typeof(InventoryService).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Application.API.Services");
        }
    }
}

