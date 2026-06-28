using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.API;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.API;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleRegistrationFacadeTests
{
    [Fact]
    public void AddOrdersInventoryNotificationsPaymentsModule_Should_Register_Module_Contracts()
    {
        var services = new ServiceCollection();

        services.AddOrdersModule();
        services.AddInventoryModule();
        services.AddNotificationsModule();
        services.AddPaymentsModule();

        services.Any(descriptor => descriptor.ServiceType == typeof(IOrderModuleApi)).Should().BeTrue();
        services.Any(descriptor => descriptor.ServiceType == typeof(IInventoryModuleApi)).Should().BeTrue();
        services.Any(descriptor => descriptor.ServiceType == typeof(INotificationsModuleApi)).Should().BeTrue();
        services.Any(descriptor => descriptor.ServiceType == typeof(IPaymentsModuleApi)).Should().BeTrue();
    }
}

