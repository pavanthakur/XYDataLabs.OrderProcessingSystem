using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.Payments.API;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class SharedContractsGuardTests
{
    [Fact]
    public void Core_Assemblies_Should_Not_Reference_SharedContracts()
    {
        var referencedAssemblies = new[]
        {
            typeof(StartupHelper).Assembly,
            typeof(IOrderModuleApi).Assembly,
            typeof(IInventoryModuleApi).Assembly,
            typeof(INotificationsModuleApi).Assembly,
            typeof(IPaymentsModuleApi).Assembly
        }
        .SelectMany(assembly => assembly.GetReferencedAssemblies())
        .Select(assembly => assembly.Name ?? string.Empty)
        .ToArray();

        referencedAssemblies.Should().NotContain(name =>
            name.Contains("SharedContracts", StringComparison.OrdinalIgnoreCase));
    }
}
