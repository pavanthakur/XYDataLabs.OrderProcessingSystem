using FluentAssertions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class OrdersModuleProjectSplitTests
{
    [Fact]
    public void Orders_Module_Projects_Should_Exist()
    {
        typeof(global::XYDataLabs.OrderProcessingSystem.Orders.Domain.Module.OrdersModuleInfo).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Orders.Features.Module.OrdersModuleRegistration).Assembly.Should().NotBeNull();
    }

}
