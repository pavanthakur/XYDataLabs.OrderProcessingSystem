using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.API;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleAPIRegistrationTests
{
    [Fact]
    public void AddModuleRegistration_Should_Register_All_Module_Contracts()
    {
        var services = new ServiceCollection();

        services.AddInventoryModule();
        services.AddNotificationsModule();
        services.AddPaymentsModule();

        services.Any(descriptor =>
            descriptor.ServiceType == typeof(IInventoryModuleApi) &&
            descriptor.ImplementationType is not null &&
            descriptor.ImplementationType.Name == "InventoryService").Should().BeTrue();

        services.Any(descriptor =>
            descriptor.ServiceType == typeof(INotificationsModuleApi) &&
            descriptor.ImplementationType is not null &&
            descriptor.ImplementationType.Name == "NotificationsService").Should().BeTrue();

        services.Any(descriptor =>
            descriptor.ServiceType == typeof(IPaymentsModuleApi) &&
            descriptor.ImplementationType is not null &&
            descriptor.ImplementationType.Name == "PaymentsService").Should().BeTrue();
    }
}

