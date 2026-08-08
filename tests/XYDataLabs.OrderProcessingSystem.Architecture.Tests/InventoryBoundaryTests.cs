using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Services;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class InventoryBoundaryTests
    {
        [Fact]
        public void Inventory_API_Should_Be_Implemented_By_The_Inventory_Module()
        {
            typeof(IInventoryModuleApi).Assembly.Should().NotBeSameAs(typeof(InventoryService).Assembly);
            typeof(IInventoryModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.API");
            typeof(InventoryService).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.Features.Services");
        }
    }
}

