namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

public interface ITenantPaymentProviderConfigurationResolver
{
    PaymentProviderRuntimeConfiguration ResolveCurrentTenantConfiguration();
}

public sealed record PaymentProviderRuntimeConfiguration(
    string ProviderType,
    string MerchantId,
    string? PublicKey,
    string PrivateKey,
    bool IsProduction);