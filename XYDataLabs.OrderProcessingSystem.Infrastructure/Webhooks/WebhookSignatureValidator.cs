using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

/// <summary>
/// Stub HMAC validator for Phase 8.7 scaffold.
/// Phase 8.7 implementation will replace this with per-provider HMAC verification
/// using secrets retrieved from Key Vault via IConfiguration / IOptions.
/// </summary>
internal sealed class WebhookSignatureValidator : IWebhookSignatureValidator
{
    private readonly ILogger<WebhookSignatureValidator> _logger;

    public WebhookSignatureValidator(ILogger<WebhookSignatureValidator> logger)
    {
        ArgumentNullException.ThrowIfNull(logger);
        _logger = logger;
    }

    public bool Validate(string providerName, string rawPayload, string? signatureHeaderValue)
    {
        // TODO (Phase 8.7): Implement per-provider HMAC validation.
        // - Razorpay: SHA256 HMAC of rawPayload with webhook secret; compare to X-Razorpay-Signature header.
        // - OpenPay:  Provider-specific signature scheme; validate accordingly.
        // Webhook secrets are stored in Key Vault (kv-orderprocessing-{env}) and never in config files.
        // Use HMAC.HashData(SHA256, Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(rawPayload)).
        // Use CryptographicOperations.FixedTimeEquals to prevent timing attacks.

        _logger.LogWarning(
            "WebhookSignatureValidator is using the Phase 8.7 stub — all signatures accepted. Provider={ProviderName}",
            providerName);

        return true;
    }
}
