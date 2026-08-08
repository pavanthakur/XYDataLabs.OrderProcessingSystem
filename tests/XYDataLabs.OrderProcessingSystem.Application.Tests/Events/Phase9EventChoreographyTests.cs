using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Events;

public sealed class Phase9EventChoreographyTests
{
    [Fact]
    public void Orders_Module_Should_Not_Consume_Its_Own_OrderCreated_Integration_Event()
    {
        var ordersEventHandlers = typeof(OrdersModuleRegistration).Assembly
            .GetTypes()
            .Where(type => type is { IsAbstract: false, IsInterface: false })
            .Where(type => type.GetInterfaces().Any(static iface =>
                iface.IsGenericType
                && iface.GetGenericTypeDefinition() == typeof(IEventHandler<>)
                && iface.GetGenericArguments()[0] == typeof(OrderCreatedV1)))
            .Select(static type => type.FullName)
            .ToArray();

        ordersEventHandlers.Should().BeEmpty(
            "Orders publishes OrderCreatedV1, but downstream module-owned effects must be handled outside the Orders feature assembly");
    }
}
