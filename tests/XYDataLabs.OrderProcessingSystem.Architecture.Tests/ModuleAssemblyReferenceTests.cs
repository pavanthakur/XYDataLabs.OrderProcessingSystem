using FluentAssertions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleAssemblyReferenceTests
{
    [Fact]
    public void ModuleAPI_Assemblies_Should_Expose_AssemblyReference_Markers()
    {
        typeof(global::XYDataLabs.OrderProcessingSystem.Orders.API.AssemblyReference).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Inventory.API.AssemblyReference).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Notifications.API.AssemblyReference).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Payments.API.AssemblyReference).Assembly.Should().NotBeNull();
    }
}

