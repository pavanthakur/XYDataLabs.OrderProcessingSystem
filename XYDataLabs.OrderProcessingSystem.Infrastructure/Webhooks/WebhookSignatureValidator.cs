using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

/// <summary>
/// Per-provider HMAC webhook signature validator.
/// Webhook secrets are resolved from IConfiguration (sourced from Key Vault at runtime).
/// Timing-safe comparison via CryptographicOperations.FixedTimeEquals prevents timing attacks.
/// </summary>
internal sealed class WebhookSignatureValidator : IWebhookSignatureValidator
{
    // Config key pattern: Webhooks:{ProviderName}:Secret
    private const string ConfigKeyPattern = "Webhooks:{0}:Secret";

    private readonly IConfiguration _configuration;
    private readonly ILogger<WebhookSignatureValidator> _logger;

    public WebhookSignatureValidator(IConfiguration configuration, ILogger<WebhookSignatureValidator> logger)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(logger);
        _configuration = configuration;
        _logger = logger;
    }

    public bool Validate(string providerName, string rawPayload, string? signatureHeaderValue)
    {
        if (string.IsNullOrWhiteSpace(signatureHeaderValue))
        {
            _logger.LogWarning(
                "Webhook signature header absent. Provider={ProviderName}", providerName);
            return false;
        }

        var secretKey = string.Format(ConfigKeyPattern, providerName);
        var secret = _configuration[secretKey];

        if (string.IsNullOrWhiteSpace(secret))
        {
            // Secret not configured for this environment — log at warning and reject.
            // In local dev, set Webhooks:{Provider}:Secret in user secrets or appsettings.local.json.
            _logger.LogWarning(
                "Webhook secret not configured for provider {ProviderName}. Key={ConfigKey}",
                providerName, secretKey);
            return false;
        }

        _logger.LogInformation(
            "Webhook secret resolved for provider {ProviderName}. Key={ConfigKey} Length={SecretLength} SecretHash={SecretHash} PayloadLen={PayloadLength} PayloadHash={PayloadHash}",
            providerName,
            secretKey,
            secret.Length,
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(secret))).Substring(0, 12),
            rawPayload?.Length ?? 0,
            rawPayload is null ? "<null>" : Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(rawPayload))).Substring(0, 12));

        return providerName switch
        {
            var p when string.Equals(p, "Razorpay", StringComparison.OrdinalIgnoreCase)
                => ValidateRazorpay(rawPayload ?? string.Empty, secret, signatureHeaderValue),
            var p when string.Equals(p, "OpenPay", StringComparison.OrdinalIgnoreCase)
                => ValidateOpenPay(rawPayload ?? string.Empty, secret, signatureHeaderValue),
            _ => RejectUnknown(providerName)
        };
    }

    /// <summary>
    /// Razorpay: HMAC-SHA256 of rawPayload, hex-encoded, compared to X-Razorpay-Signature header.
    /// Reference: https://razorpay.com/docs/webhooks/validate-test/#validate-webhooks
    /// </summary>
    private bool ValidateRazorpay(string rawPayload, string secret, string headerValue)
    {
        var keyBytes = Encoding.UTF8.GetBytes(secret);
        var payloadBytes = Encoding.UTF8.GetBytes(rawPayload);
        var expectedHash = HMACSHA256.HashData(keyBytes, payloadBytes);
        var expectedHex = Convert.ToHexString(expectedHash); // uppercase hex

        var headerBytes = Encoding.UTF8.GetBytes(headerValue.ToUpperInvariant());
        var expectedBytes = Encoding.UTF8.GetBytes(expectedHex);

        return CryptographicOperations.FixedTimeEquals(headerBytes, expectedBytes);
    }

    /// <summary>
    /// OpenPay: HMAC-SHA256 of rawPayload, base64-encoded, compared to X-OpenPay-Signature header.
    /// Adjust if the provider uses a different scheme.
    /// </summary>
    private bool ValidateOpenPay(string rawPayload, string secret, string headerValue)
    {
        var keyBytes = Encoding.UTF8.GetBytes(secret);
        var payloadBytes = Encoding.UTF8.GetBytes(rawPayload);
        var expectedHash = HMACSHA256.HashData(keyBytes, payloadBytes);
        var expectedBase64 = Convert.ToBase64String(expectedHash);

        var headerBytes = Encoding.UTF8.GetBytes(headerValue);
        var expectedBytes = Encoding.UTF8.GetBytes(expectedBase64);

        return CryptographicOperations.FixedTimeEquals(headerBytes, expectedBytes);
    }

    private bool RejectUnknown(string providerName)
    {
        _logger.LogWarning("No HMAC validation scheme registered for provider {ProviderName}", providerName);
        return false;
    }
}
