using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.RazorpayAdapter;

/// <summary>
/// Internal interface for Razorpay SDK operations.
/// Kept separate from IPaymentProviderGateway so the gateway facade controls mapping.
/// </summary>
public interface IRazorpayAdapterService : IPaymentProviderAdapter
{
    /// <summary>
    /// Creates a Razorpay Order (server-side step of the Orders API checkout flow).
    /// Returns the order_id used by Razorpay Checkout on the frontend.
    /// </summary>
    Task<RazorpayOrderResult> CreateOrderAsync(RazorpayCreateOrderRequest request, CancellationToken cancellationToken = default);

    /// <summary>
    /// Retrieves a Razorpay Payment by payment_id (set after Razorpay Checkout completion).
    /// </summary>
    Task<RazorpayPaymentResult> GetPaymentAsync(string paymentId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a Razorpay S2S payment via the JSON v2 API (<c>POST /v1/payments/create/json</c>).
    /// Used when <c>Use3DSecure = true</c>: submits card details server-side and returns the
    /// bank ACS redirect URL so the user can complete OTP in our UI rather than a Razorpay popup.
    /// </summary>
    Task<RazorpayS2SPaymentResult> CreateS2SPaymentAsync(RazorpayS2SPaymentRequest request, CancellationToken cancellationToken = default);
}

public sealed record RazorpayCreateOrderRequest(
    decimal Amount,
    string Currency,
    string Receipt,
    string? Notes = null);

public sealed record RazorpayOrderResult(
    string OrderId,
    string Status,
    decimal Amount,
    string Currency,
    DateTime CreatedAt);

public sealed record RazorpayPaymentResult(
    string PaymentId,
    string? OrderId,
    string? Status,
    decimal Amount,
    string Currency,
    DateTime CreatedAt,
    string? ErrorCode,
    string? ErrorDescription);

/// <summary>
/// Input for the Razorpay S2S JSON v2 payment creation endpoint.
/// <c>Contact</c> is required by Razorpay; use a placeholder until the payment form exposes a phone field.
/// </summary>
public sealed record RazorpayS2SPaymentRequest(
    string OrderId,
    decimal Amount,
    string Currency,
    string Email,
    string Contact,
    string CardNumber,
    string CardName,
    string CardExpiryMonth,
    string CardExpiryYear,
    string CardCvv,
    string CallbackUrl);

/// <summary>
/// Result from the Razorpay S2S payment creation.
/// When <c>NextRedirectUrl</c> is set the user must be redirected there for OTP/3DS.
/// When it is null the payment was directly authorized and no redirect is needed.
/// </summary>
public sealed record RazorpayS2SPaymentResult(
    string PaymentId,
    string? Status,
    string? NextRedirectUrl,
    string? ErrorMessage);
