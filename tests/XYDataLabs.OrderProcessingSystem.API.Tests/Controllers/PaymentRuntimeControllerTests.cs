using System.Security.Claims;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Payments.API.Controllers;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class PaymentRuntimeControllerTests
{
    [Theory]
    [InlineData(false,false,"sandbox")]
    [InlineData(true,false,"deterministic")]
    [InlineData(false,true,"live")]
    public void ReportsResolvedImplementation_WithoutSecrets(bool simulation,bool production,string expected)
    {
        var gateway = new Mock<IPaymentProviderGateway>();
        gateway.SetupGet(x=>x.ProviderType).Returns("OpenPay");
        gateway.SetupGet(x=>x.IsSimulation).Returns(simulation);
        var provider = new Mock<ITenantPaymentProviderResolver>();
        provider.Setup(x=>x.ResolveCurrentTenantProvider()).Returns(new PaymentProvider {ProviderType="OpenPay",Use3DSecure=true});
        var resolver = new Mock<ITenantPaymentProviderConfigurationResolver>();
        resolver.Setup(x=>x.ResolveCurrentTenantConfiguration()).Returns(new PaymentProviderRuntimeConfiguration("OpenPay","PRIVATE-MERCHANT","PRIVATE-PUBLICKEY","PRIVATE-SECRET",production));
        var controller = new PaymentRuntimeController {ControllerContext=new ControllerContext {HttpContext=new DefaultHttpContext {User=new ClaimsPrincipal(new ClaimsIdentity([new Claim("tenant_code","TenantA")],"test"))}}};
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> {{"IdentityProvider:Enabled","true"}}).Build();
        var result = controller.Get(gateway.Object,provider.Object,resolver.Object,config).Should().BeOfType<OkObjectResult>().Subject;
        var json = JsonSerializer.Serialize(result.Value);
        json.Should().Contain(expected).And.NotContain("PRIVATE-");
        controller.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity());
        controller.Get(gateway.Object,provider.Object,resolver.Object,config).Should().BeOfType<UnauthorizedResult>();
    }
}
