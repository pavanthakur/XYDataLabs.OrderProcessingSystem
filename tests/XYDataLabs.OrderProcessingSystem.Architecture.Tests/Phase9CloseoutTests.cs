using System;
using System.IO;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.Payments.API;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class Phase9CloseoutTests
{
    [Fact]
    public void Phase9Roadmap_ShouldInclude_All_Subphases_Through_9_10()
    {
        var roadmap = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\local models\zoocode\phase9\phase9-roadmap.md"));
        roadmap.Should().Contain("### 9.8 - Inventory Module Isolation");
        roadmap.Should().Contain("### 9.9 - Notifications Module Isolation");
        roadmap.Should().Contain("### 9.10 - Validation and Closeout");
    }

    [Fact]
    public void Phase9_API_Surface_Should_Include_All_Module_Contracts()
    {
        typeof(IOrderModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Orders.API");
        typeof(IInventoryModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Inventory.API");
        typeof(INotificationsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.API");
        typeof(IPaymentsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Payments.API");
    }
}

