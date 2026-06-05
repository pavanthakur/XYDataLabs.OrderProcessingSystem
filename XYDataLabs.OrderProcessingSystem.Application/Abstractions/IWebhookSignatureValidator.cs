namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

/// <summary>
/// Validates provider-specific webhook signatures before the payload is deserialized.
/// Defined in Application; implemented per-provider in Infrastructure.
/// </summary>
public interface IWebhookSignatureValidator
{
    /// <summary>
    /// Returns true if the raw payload signature is valid for the given provider.
    /// Must be called with the raw, unmodified request body before any deserialization.
    /// </summary>
    /// <param name="providerName">Canonical provider name (e.g. "Razorpay", "OpenPay").</param>
    /// <param name="rawPayload">Raw request body string exactly as received from the provider.</param>
    /// <param name="signatureHeaderValue">Value of the provider-specific signature header (null if header was absent).</param>
    bool Validate(string providerName, string rawPayload, string? signatureHeaderValue);
}
