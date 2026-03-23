using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public class InfoControllerTests
{
    [Fact]
    public async Task GetRuntimeConfiguration_ReturnsActiveTenantConfiguration()
    {
        var controller = CreateController("TenantA", [
            new TenantInfo(1, "TenantA", "Tenant A"),
            new TenantInfo(2, "TenantB", "Tenant B")
        ]);

        var result = await controller.GetRuntimeConfiguration(CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        okResult.Value.Should().NotBeNull();
        okResult.Value!.GetType().GetProperty("ActiveTenantCode")!.GetValue(okResult.Value)
            .Should().Be("TenantA");
        okResult.Value!.GetType().GetProperty("ConfiguredActiveTenantCode")!.GetValue(okResult.Value)
            .Should().Be("TenantA");
        okResult.Value!.GetType().GetProperty("TenantHeaderName")!.GetValue(okResult.Value)
            .Should().Be(TenantMiddleware.TenantHeaderName);

        var availableTenants = Assert.IsAssignableFrom<System.Collections.IEnumerable>(
            okResult.Value!.GetType().GetProperty("AvailableTenants")!.GetValue(okResult.Value));
        availableTenants.Cast<object>().Should().HaveCount(2);
    }

    [Fact]
    public async Task GetRuntimeConfiguration_ReturnsRequestedTenant_WhenHeaderMatchesActiveTenant()
    {
        var controller = CreateController("TenantA", [
            new TenantInfo(1, "TenantA", "Tenant A"),
            new TenantInfo(2, "TenantB", "Tenant B")
        ]);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };
        controller.ControllerContext.HttpContext.Request.Headers[TenantMiddleware.TenantHeaderName] = "TenantB";

        var result = await controller.GetRuntimeConfiguration(CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        okResult.Value!.GetType().GetProperty("ActiveTenantCode")!.GetValue(okResult.Value)
            .Should().Be("TenantB");
    }

    [Fact]
    public async Task GetRuntimeConfiguration_ReturnsProblem_WhenActiveTenantCodeIsMissing()
    {
        var controller = CreateController(string.Empty, [
            new TenantInfo(1, "TenantA", "Tenant A")
        ]);

        var result = await controller.GetRuntimeConfiguration(CancellationToken.None);

        var objectResult = Assert.IsType<ObjectResult>(result);
        objectResult.StatusCode.Should().Be(500);
    }

    private static InfoController CreateController(string activeTenantCode, IReadOnlyList<TenantInfo> tenants)
    {
        var tenantRegistry = new Mock<ITenantRegistry>();
        tenantRegistry
            .Setup(r => r.GetActiveTenantsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(tenants);

        return new InfoController(
            Mock.Of<ILogger<InfoController>>(),
            tenantRegistry.Object,
            Options.Create(new TenantConfigurationOptions { ActiveTenantCode = activeTenantCode }),
            TimeProvider.System);
    }
}