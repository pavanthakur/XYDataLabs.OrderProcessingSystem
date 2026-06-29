using FluentAssertions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class OtherModuleProjectSplitTests
{
    [Fact]
    public void Inventory_Module_Projects_Should_Exist()
    {
        typeof(global::XYDataLabs.OrderProcessingSystem.Inventory.Domain.Module.InventoryModuleInfo).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Inventory.Features.Module.InventoryModuleRegistration).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure.Module.InventoryInfrastructureMarker).Assembly.Should().NotBeNull();
    }

    [Fact]
    public void Notifications_Module_Projects_Should_Exist()
    {
        typeof(global::XYDataLabs.OrderProcessingSystem.Notifications.Domain.Module.NotificationsModuleInfo).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Notifications.Features.Module.NotificationsModuleRegistration).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure.Module.NotificationsInfrastructureMarker).Assembly.Should().NotBeNull();
    }

    [Fact]
    public void Payments_Module_Projects_Should_Exist()
    {
        typeof(global::XYDataLabs.OrderProcessingSystem.Payments.Domain.Module.PaymentsModuleInfo).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Payments.Features.Module.PaymentsModuleRegistration).Assembly.Should().NotBeNull();
        typeof(global::XYDataLabs.OrderProcessingSystem.Payments.Infrastructure.Module.PaymentsInfrastructureMarker).Assembly.Should().NotBeNull();
    }

    [Fact]
    public void Inventory_Notifications_Payments_Feature_Assemblies_Should_Not_Depend_On_API_Or_Infrastructure()
    {
        var inventoryReferences = typeof(global::XYDataLabs.OrderProcessingSystem.Inventory.Features.Module.InventoryModuleRegistration)
            .Assembly
            .GetReferencedAssemblies()
            .Select(assembly => assembly.Name)
            .ToArray();

        var notificationsReferences = typeof(global::XYDataLabs.OrderProcessingSystem.Notifications.Features.Module.NotificationsModuleRegistration)
            .Assembly
            .GetReferencedAssemblies()
            .Select(assembly => assembly.Name)
            .ToArray();

        var paymentsReferences = typeof(global::XYDataLabs.OrderProcessingSystem.Payments.Features.Module.PaymentsModuleRegistration)
            .Assembly
            .GetReferencedAssemblies()
            .Select(assembly => assembly.Name)
            .ToArray();

        inventoryReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.API");
        inventoryReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.Infrastructure");

        notificationsReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.API");
        notificationsReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.Infrastructure");

        paymentsReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.API");
        paymentsReferences.Should().NotContain("XYDataLabs.OrderProcessingSystem.Infrastructure");
    }
}
