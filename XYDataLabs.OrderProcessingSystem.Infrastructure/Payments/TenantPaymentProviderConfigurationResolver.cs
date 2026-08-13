using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;

public sealed class TenantPaymentProviderConfigurationResolver : ITenantPaymentProviderConfigurationResolver
{
    private readonly ITenantPaymentProviderResolver _paymentProviderResolver;
    private readonly IConfiguration _configuration;

    public TenantPaymentProviderConfigurationResolver(
        ITenantPaymentProviderResolver paymentProviderResolver,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(paymentProviderResolver);
        ArgumentNullException.ThrowIfNull(configuration);

        _paymentProviderResolver = paymentProviderResolver;
        _configuration = configuration;
    }

    public PaymentProviderRuntimeConfiguration ResolveCurrentTenantConfiguration()
    {
        var paymentProvider = _paymentProviderResolver.ResolveCurrentTenantProvider();
        var merchantId = ResolveMerchantId(paymentProvider);
        var publicKey = ResolvePublicKey(paymentProvider);
        var privateKeyConfigurationKey = ResolvePrivateKeyConfigurationKey(paymentProvider);
        var privateKey = ResolveConfigurationValue(privateKeyConfigurationKey);
        privateKey ??= ResolveConfigurationValue(GetFallbackConfigurationKey(paymentProvider.ProviderType, "PrivateKey"));

        if (string.IsNullOrWhiteSpace(privateKey))
        {
            throw new InvalidOperationException(
                $"Payment provider '{paymentProvider.ProviderType}' for tenant {paymentProvider.TenantId} " +
                $"is missing configuration value '{privateKeyConfigurationKey}'.");
        }

        if (string.Equals(paymentProvider.ProviderType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrWhiteSpace(publicKey))
        {
            throw new InvalidOperationException(
                $"Payment provider '{paymentProvider.ProviderType}' for tenant {paymentProvider.TenantId} is missing PublicKey.");
        }

        return new PaymentProviderRuntimeConfiguration(
            paymentProvider.ProviderType,
            merchantId,
            publicKey,
            privateKey,
            paymentProvider.IsProduction);
    }

    private string ResolveMerchantId(PaymentProvider paymentProvider)
    {
        if (!string.IsNullOrWhiteSpace(paymentProvider.MerchantId))
        {
            return paymentProvider.MerchantId;
        }

        var fallbackMerchantId = _configuration[GetFallbackConfigurationKey(paymentProvider.ProviderType, "MerchantId")];
        fallbackMerchantId ??= ResolveConfigurationValue(GetFallbackConfigurationKey(paymentProvider.ProviderType, "MerchantId"));
        if (!string.IsNullOrWhiteSpace(fallbackMerchantId))
        {
            return fallbackMerchantId;
        }

        throw new InvalidOperationException(
            $"Payment provider '{paymentProvider.ProviderType}' for tenant {paymentProvider.TenantId} is missing MerchantId.");
    }

    private string? ResolvePublicKey(PaymentProvider paymentProvider)
    {
        if (!string.Equals(paymentProvider.ProviderType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(paymentProvider.PublicKey))
        {
            return paymentProvider.PublicKey;
        }

        return ResolveConfigurationValue(GetFallbackConfigurationKey(paymentProvider.ProviderType, "PublicKey"));
    }

    private static string ResolvePrivateKeyConfigurationKey(PaymentProvider paymentProvider)
    {
        if (!string.IsNullOrWhiteSpace(paymentProvider.PrivateKeyConfigurationKey))
        {
            return paymentProvider.PrivateKeyConfigurationKey;
        }

        return GetFallbackConfigurationKey(paymentProvider.ProviderType, "PrivateKey");
    }

    private static string GetFallbackConfigurationKey(string providerType, string keyName)
    {
        if (string.Equals(providerType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase))
        {
            return $"OpenPay:{keyName}";
        }

        if (string.Equals(providerType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase))
        {
            return $"Razorpay:{keyName}";
        }

        throw new InvalidOperationException($"Unsupported payment provider type '{providerType}'.");
    }

    private string? ResolveConfigurationValue(string configurationKey)
    {
        foreach (var candidateKey in ExpandConfigurationKeyCandidates(configurationKey))
        {
            var value = _configuration[candidateKey];
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return null;
    }

    private static IEnumerable<string> ExpandConfigurationKeyCandidates(string configurationKey)
    {
        yield return configurationKey;

        var envStyleKey = configurationKey.Replace(":", "__");
        if (!string.Equals(envStyleKey, configurationKey, StringComparison.Ordinal))
        {
            yield return envStyleKey;
        }

        var keyVaultStyleKey = configurationKey.Replace(":", "--");
        if (!string.Equals(keyVaultStyleKey, configurationKey, StringComparison.Ordinal)
            && !string.Equals(keyVaultStyleKey, envStyleKey, StringComparison.Ordinal))
        {
            yield return keyVaultStyleKey;
        }
    }
}
