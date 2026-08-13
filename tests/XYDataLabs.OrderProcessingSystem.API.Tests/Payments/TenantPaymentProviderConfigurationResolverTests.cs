using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Payments;

public class TenantPaymentProviderConfigurationResolverTests
{
    [Fact]
    public void ResolveCurrentTenantConfiguration_UsesTenantStoredValuesAndConfigurationKey()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 42,
            ProviderType = PaymentProviderTypes.OpenPay,
            MerchantId = "mt_tenant_42",
            PublicKey = "pk_tenant_42",
            PrivateKeyConfigurationKey = "PaymentProviders:Tenant42:OpenPay:PrivateKey",
            IsProduction = true
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["PaymentProviders:Tenant42:OpenPay:PrivateKey"] = "sk_tenant_42"
            });

        var result = sut.ResolveCurrentTenantConfiguration();

        result.ProviderType.Should().Be(PaymentProviderTypes.OpenPay);
        result.MerchantId.Should().Be("mt_tenant_42");
        result.PublicKey.Should().Be("pk_tenant_42");
        result.PrivateKey.Should().Be("sk_tenant_42");
        result.IsProduction.Should().BeTrue();
    }

    [Fact]
    public void ResolveCurrentTenantConfiguration_FallsBackToLegacyProviderConfigurationKeys()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 7,
            ProviderType = PaymentProviderTypes.Razorpay,
            IsProduction = false
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["Razorpay:MerchantId"] = "rzp_test_fallback",
                ["Razorpay:PrivateKey"] = "fallback-private-key"
            });

        var result = sut.ResolveCurrentTenantConfiguration();

        result.ProviderType.Should().Be(PaymentProviderTypes.Razorpay);
        result.MerchantId.Should().Be("rzp_test_fallback");
        result.PublicKey.Should().BeNull();
        result.PrivateKey.Should().Be("fallback-private-key");
        result.IsProduction.Should().BeFalse();
    }

    [Fact]
    public void ResolveCurrentTenantConfiguration_ReadsTenantAliasSecrets_FromKeyVaultStyleKeys()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 42,
            ProviderType = PaymentProviderTypes.OpenPay,
            MerchantId = "mt_tenant_42",
            PublicKey = "pk_tenant_42",
            PrivateKeyConfigurationKey = "PaymentProviders:Tenant42:OpenPay:PrivateKey",
            IsProduction = false
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["PaymentProviders--Tenant42--OpenPay--PrivateKey"] = "sk_tenant_42"
            });

        var result = sut.ResolveCurrentTenantConfiguration();

        result.PrivateKey.Should().Be("sk_tenant_42");
    }

    [Fact]
    public void ResolveCurrentTenantConfiguration_ForOpenPay_FallsBackToAlternateConfigurationKeyShapes()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 7,
            ProviderType = PaymentProviderTypes.OpenPay,
            PrivateKeyConfigurationKey = "PaymentProviders:TenantA:OpenPay:PrivateKey",
            IsProduction = false
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["OpenPay--MerchantId"] = "mt_fallback_openpay",
                ["OpenPay__PublicKey"] = "pk_fallback_openpay",
                ["PaymentProviders__TenantA__OpenPay__PrivateKey"] = "sk_fallback_openpay"
            });

        var result = sut.ResolveCurrentTenantConfiguration();

        result.MerchantId.Should().Be("mt_fallback_openpay");
        result.PublicKey.Should().Be("pk_fallback_openpay");
        result.PrivateKey.Should().Be("sk_fallback_openpay");
    }

    [Fact]
    public void ResolveCurrentTenantConfiguration_WhenTenantAliasIsUnavailable_FallsBackToProviderPrivateKey()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 7,
            ProviderType = PaymentProviderTypes.OpenPay,
            MerchantId = "mt_tenant_7",
            PublicKey = "pk_tenant_7",
            PrivateKeyConfigurationKey = "PaymentProviders:TenantA:OpenPay:PrivateKey",
            IsProduction = false
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["OpenPay:PrivateKey"] = "sk_provider_fallback"
            });

        var result = sut.ResolveCurrentTenantConfiguration();

        result.PrivateKey.Should().Be("sk_provider_fallback");
    }

    [Fact]
    public void ResolveCurrentTenantConfiguration_ForOpenPay_ThrowsWhenPublicKeyMissing()
    {
        var paymentProvider = new PaymentProvider
        {
            TenantId = 99,
            ProviderType = PaymentProviderTypes.OpenPay,
            MerchantId = "mt_tenant_99",
            PrivateKeyConfigurationKey = "PaymentProviders:Tenant99:OpenPay:PrivateKey"
        };

        var sut = CreateResolver(
            paymentProvider,
            new Dictionary<string, string?>
            {
                ["PaymentProviders:Tenant99:OpenPay:PrivateKey"] = "sk_tenant_99"
            });

        var act = () => sut.ResolveCurrentTenantConfiguration();

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*missing PublicKey*");
    }

    private static TenantPaymentProviderConfigurationResolver CreateResolver(
        PaymentProvider paymentProvider,
        IReadOnlyDictionary<string, string?> configurationValues)
    {
        var paymentProviderResolver = new Mock<ITenantPaymentProviderResolver>();
        paymentProviderResolver
            .Setup(resolver => resolver.ResolveCurrentTenantProvider())
            .Returns(paymentProvider);

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(configurationValues)
            .Build();

        return new TenantPaymentProviderConfigurationResolver(paymentProviderResolver.Object, configuration);
    }
}
