namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

/// <summary>
/// Currency capabilities of this integration, not a claim about every currency
/// a provider may support after separate merchant/account provisioning.
/// </summary>
public static class PaymentCurrencyPolicy
{
    private static readonly IReadOnlyList<string> RazorpayCurrencies = Array.AsReadOnly(new[] { "INR" });

    // Other adapters retain their existing capability checks; do not invent a
    // currency allowlist for them or silently convert the persisted order.
    public static IReadOnlyList<string>? GetSupportedCurrencies(string providerType) =>
        string.Equals(providerType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase)
            ? RazorpayCurrencies
            : null;

    public static bool IsSupported(string providerType, string currency) =>
        GetSupportedCurrencies(providerType) is not { } supported
        || supported.Contains(currency, StringComparer.OrdinalIgnoreCase);

    public static string GetUnsupportedCurrencyMessage(string providerType, string currency) =>
        $"Order currency {currency} is not supported by {providerType} in this integration. Supported currency: {string.Join(", ", GetSupportedCurrencies(providerType) ?? [])}. Select a matching order/provider; no currency conversion was performed.";
}
