using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class PaymentCallbackControllerTests
{
    [Fact]
    public void RedirectToClientCallback_UsesConfiguredFrontendBaseUrl()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Frontend:WebBaseUrl"] = "http://localhost:5173"
            })
            .Build();

        var controller = new PaymentCallbackController(
            configuration,
            Mock.Of<ILogger<PaymentCallbackController>>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };

        controller.ControllerContext.HttpContext.Request.QueryString = new QueryString("?id=pay_123&tenantCode=TenantA");

        var result = controller.RedirectToClientCallback();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("http://localhost:5173/payments/callback?id=pay_123&tenantCode=TenantA");
    }
}