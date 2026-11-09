using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Payments.API.Controllers;

[ApiController]
[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/Payments/runtime")]
public sealed class PaymentRuntimeController : ControllerBase
{
    [HttpGet]
    public IActionResult Get(
        [FromServices] IPaymentProviderGateway gateway,
        [FromServices] ITenantPaymentProviderResolver providerResolver,
        [FromServices] ITenantPaymentProviderConfigurationResolver configurationResolver,
        [FromServices] IConfiguration configuration)
    {
        // Identity-disabled local fixture hosts retain compatibility; enabled
        // hosts must authenticate and pass tenant middleware before discovery.
        if (configuration.GetValue("IdentityProvider:Enabled", false) && User.Identity?.IsAuthenticated != true)
            return Unauthorized();
        var provider = providerResolver.ResolveCurrentTenantProvider();
        var runtime = configurationResolver.ResolveCurrentTenantConfiguration();
        return Ok(new
        {
            success = true,
            data = new
            {
                adapterMode = gateway.IsSimulation ? "deterministic" : runtime.IsProduction ? "live" : "sandbox",
                providerType = gateway.ProviderType,
                isProduction = runtime.IsProduction,
                configuredThreeDs = provider.Use3DSecure,
                supportedCurrencies = PaymentCurrencyPolicy.GetSupportedCurrencies(provider.ProviderType),
                collectionMode = provider.ProviderType.Equals(PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase)
                    && !provider.Use3DSecure ? "provider_checkout" : "direct_card_form"
            }
        });
    }
}
