using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.Domain.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.Domain.Module;
using XYDataLabs.OrderProcessingSystem.Orders.Domain.Module;
using XYDataLabs.OrderProcessingSystem.Payments.Domain.Module;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleContextMappingTests
{
    [Fact]
    public void Module_Context_Names_Should_Match_Phase9_Bounded_Contexts()
    {
        OrdersModuleInfo.ModuleName.Should().Be("Orders");
        InventoryModuleInfo.ModuleName.Should().Be("Inventory");
        NotificationsModuleInfo.ModuleName.Should().Be("Notifications");
        PaymentsModuleInfo.ModuleName.Should().Be("Payments");
    }

    [Fact]
    public void Module_Schema_Names_Should_Match_Phase9_Database_Schemas()
    {
        OrdersModuleInfo.SchemaName.Should().Be("orders");
        InventoryModuleInfo.SchemaName.Should().Be("inventory");
        NotificationsModuleInfo.SchemaName.Should().Be("notifications");
        PaymentsModuleInfo.SchemaName.Should().Be("payments");
    }
}
