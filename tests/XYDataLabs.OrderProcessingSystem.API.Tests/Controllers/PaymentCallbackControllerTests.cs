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

    [Fact]
    public void RedirectToClientCallback_RewritesLoopbackFrontendBaseUrl_ToHttps_WhenProfileRequiresIt()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Frontend:WebBaseUrl"] = "http://localhost:5173",
                ["USE_HTTPS"] = "true"
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
            .Which.Url.Should().Be("https://localhost:5173/payments/callback?id=pay_123&tenantCode=TenantA");
    }

    [Fact]
    public void RedirectToClientCallback_UsesAllowedClientCallbackOrigin_WhenProvided()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Frontend:WebBaseUrl"] = "http://localhost:5173",
                ["ApiSettings:UI:http:Host"] = "localhost",
                ["ApiSettings:UI:http:Port"] = "5173",
                ["ApiSettings:UI:https:Host"] = "localhost",
                ["ApiSettings:UI:https:Port"] = "5174",
                ["USE_HTTPS"] = "true"
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

        controller.ControllerContext.HttpContext.Request.QueryString = new QueryString(
            "?id=pay_123&tenantCode=TenantA&clientCallbackOrigin=http%3A%2F%2Flocalhost%3A5173");

        var result = controller.RedirectToClientCallback();

        result.Should().BeOfType<RedirectResult>()
            .Which.Url.Should().Be("http://localhost:5173/payments/callback?id=pay_123&tenantCode=TenantA&clientCallbackOrigin=http%3A%2F%2Flocalhost%3A5173");
    }
}