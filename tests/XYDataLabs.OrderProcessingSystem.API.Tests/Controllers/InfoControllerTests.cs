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
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public class InfoControllerTests
{
    [Fact]
    public void GetPaymentConfiguration_ReturnsRazorpayCheckoutContract()
    {
        var controller = CreateController(
            "TenantA",
            [new TenantInfo(1, "TenantA", "Tenant A")],
            new PaymentProvider { Name = "Razorpay", ProviderType = "Razorpay", MerchantId = "rzp_test_browser_key", PrivateKeyConfigurationKey = "Razorpay:PrivateKey" });

        var result = controller.GetPaymentConfiguration();

        var okResult = Assert.IsType<OkObjectResult>(result);
        okResult.Value.Should().NotBeNull();
        okResult.Value!.GetType().GetProperty("ActiveProviderType")!.GetValue(okResult.Value)
            .Should().Be("Razorpay");
        okResult.Value!.GetType().GetProperty("CollectionMode")!.GetValue(okResult.Value)
            .Should().Be("provider_checkout");
        okResult.Value!.GetType().GetProperty("BrowserKey")!.GetValue(okResult.Value)
            .Should().Be("rzp_test_browser_key");
        okResult.Value!.GetType().GetProperty("BrowserMerchantId")!.GetValue(okResult.Value)
            .Should().BeNull();
        okResult.Value!.GetType().GetProperty("IsProduction")!.GetValue(okResult.Value)
            .Should().Be(false);
    }

    [Fact]
    public void GetPaymentConfiguration_ReturnsOpenPayDirectCardContract()
    {
        var controller = CreateController(
            "TenantA",
            [new TenantInfo(1, "TenantA", "Tenant A")],
            new PaymentProvider { Name = "OpenPay", ProviderType = "OpenPay", MerchantId = "mt_test_openpay_merchant", PublicKey = "pk_test_openpay_browser_key", PrivateKeyConfigurationKey = "OpenPay:PrivateKey" });

        var result = controller.GetPaymentConfiguration();

        var okResult = Assert.IsType<OkObjectResult>(result);
        okResult.Value!.GetType().GetProperty("CollectionMode")!.GetValue(okResult.Value)
            .Should().Be("direct_card_form");
        okResult.Value!.GetType().GetProperty("BrowserKey")!.GetValue(okResult.Value)
            .Should().Be("pk_test_openpay_browser_key");
        okResult.Value!.GetType().GetProperty("BrowserMerchantId")!.GetValue(okResult.Value)
            .Should().Be("mt_test_openpay_merchant");
        okResult.Value!.GetType().GetProperty("IsProduction")!.GetValue(okResult.Value)
            .Should().Be(false);
    }

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

    private static InfoController CreateController(
        string activeTenantCode,
        IReadOnlyList<TenantInfo> tenants,
        PaymentProvider? paymentProvider = null)
    {
        var tenantRegistry = new Mock<ITenantRegistry>();
        tenantRegistry
            .Setup(r => r.GetActiveTenantsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(tenants);

        var paymentProviderResolver = new Mock<ITenantPaymentProviderResolver>();
        paymentProviderResolver
            .Setup(r => r.ResolveCurrentTenantProvider())
            .Returns(paymentProvider ?? new PaymentProvider { Name = "OpenPay", ProviderType = "OpenPay", MerchantId = "mt_test_openpay_merchant", PublicKey = "pk_test_openpay_browser_key", PrivateKeyConfigurationKey = "OpenPay:PrivateKey" });

        var paymentProviderConfigurationResolver = new Mock<ITenantPaymentProviderConfigurationResolver>();
        paymentProviderConfigurationResolver
            .Setup(r => r.ResolveCurrentTenantConfiguration())
            .Returns(() =>
            {
                var provider = paymentProvider ?? new PaymentProvider
                {
                    Name = "OpenPay",
                    ProviderType = PaymentProviderTypes.OpenPay,
                    MerchantId = "mt_test_openpay_merchant",
                    PublicKey = "pk_test_openpay_browser_key",
                    PrivateKeyConfigurationKey = "OpenPay:PrivateKey",
                    IsProduction = false
                };

                return new PaymentProviderRuntimeConfiguration(
                    provider.ProviderType,
                    provider.MerchantId ?? string.Empty,
                    provider.PublicKey,
                    "test-private-key",
                    provider.IsProduction);
            });

        return new InfoController(
            Mock.Of<ILogger<InfoController>>(),
            tenantRegistry.Object,
            paymentProviderResolver.Object,
            paymentProviderConfigurationResolver.Object,
            Options.Create(new TenantConfigurationOptions { ActiveTenantCode = activeTenantCode }),
            TimeProvider.System);
    }
}