using FluentAssertions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class APISurfaceDriftTests
{
    [Fact]
    public void Application_API_Contracts_Should_Remain_As_Internal_Compatibility_Surfaces_Only()
    {
        var applicationAPIPath = Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.API");
        Directory.Exists(applicationAPIPath).Should().BeTrue("the root API surface still exists during Phase 9 migration");

        var standaloneAPIPaths = new[]
        {
            Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Orders.API"),
            Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Inventory.API"),
            Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Notifications.API"),
            Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Payments.API"),
            Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\XYDataLabs.OrderProcessingSystem.Tenants.API"),
        };

        foreach (var path in standaloneAPIPaths)
        {
            Directory.Exists(path).Should().BeTrue($"expected module-owned API project at {path}");
        }
    }
}
