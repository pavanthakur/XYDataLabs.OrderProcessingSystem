using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public class InfoControllerTests
{
    [Fact]
    public void GetRuntimeConfiguration_ReturnsActiveTenantConfiguration()
    {
        var controller = CreateController("TenantA");

        var result = controller.GetRuntimeConfiguration();

        var okResult = Assert.IsType<OkObjectResult>(result);
        okResult.Value.Should().NotBeNull();
        okResult.Value!.GetType().GetProperty("ActiveTenantCode")!.GetValue(okResult.Value)
            .Should().Be("TenantA");
        okResult.Value!.GetType().GetProperty("TenantHeaderName")!.GetValue(okResult.Value)
            .Should().Be(TenantMiddleware.TenantHeaderName);
    }

    [Fact]
    public void GetRuntimeConfiguration_ReturnsProblem_WhenActiveTenantCodeIsMissing()
    {
        var controller = CreateController(string.Empty);

        var result = controller.GetRuntimeConfiguration();

        var objectResult = Assert.IsType<ObjectResult>(result);
        objectResult.StatusCode.Should().Be(500);
    }

    private static InfoController CreateController(string activeTenantCode)
    {
        return new InfoController(
            Mock.Of<ILogger<InfoController>>(),
            Options.Create(new TenantConfigurationOptions { ActiveTenantCode = activeTenantCode }),
            TimeProvider.System);
    }
}