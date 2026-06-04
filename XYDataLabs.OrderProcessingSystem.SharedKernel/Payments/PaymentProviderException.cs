namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

/// <summary>
/// Base class for all payment provider failures that are surfaced above the adapter boundary.
/// Adapters catch provider-specific SDK exceptions and re-throw as one of the typed subclasses
/// so that the Application layer can apply the correct retry / reconciliation / terminal policy
/// without taking a dependency on any provider SDK.
/// </summary>
public class PaymentProviderException : Exception
{
    /// <summary>Provider-specific error code string, if available.</summary>
    public string? ProviderErrorCode { get; }

    protected PaymentProviderException(string message, string? providerErrorCode = null, Exception? inner = null)
        : base(message, inner)
    {
        ProviderErrorCode = providerErrorCode;
    }
}

/// <summary>
/// A definitive customer-action failure returned by the payment provider:
/// card declined, insufficient funds, expired card, invalid CVV, authentication required,
/// or a hard decline from the issuer.
///
/// Handling rule (architecture doc §8.5):
///   • <em>Never</em> retry — retrying would not change the outcome.
///   • <em>Never</em> reconcile — the provider rejected the charge before accepting it.
///   • The corresponding <c>PaymentAttempt</c> must be marked <see cref="XYDataLabs.OrderProcessingSystem.Domain.Entities.PaymentAttemptStatus.Failed"/> (terminal).
/// </summary>
public sealed class PaymentProviderCustomerActionException : PaymentProviderException
{
    public PaymentProviderCustomerActionException(
        string message,
        string? providerErrorCode = null,
        Exception? inner = null)
        : base(message, providerErrorCode, inner) { }
}

/// <summary>
/// Thrown when the payment provider API endpoint or feature is not enabled on the merchant account.
/// This is a configuration/activation error — not a customer-action failure.
///
/// Handling rule:
///   • Do <em>not</em> treat as a terminal card-level failure.
///   • The <c>PaymentAttempt</c> is marked failed but with a clear setup-required message.
///   • Operator must enable the feature on the provider dashboard before the integration can work.
/// </summary>
public sealed class PaymentProviderIntegrationNotEnabledException : PaymentProviderException
{
    public PaymentProviderIntegrationNotEnabledException(
        string message,
        string? providerErrorCode = null,
        Exception? inner = null)
        : base(message, providerErrorCode, inner) { }
}
