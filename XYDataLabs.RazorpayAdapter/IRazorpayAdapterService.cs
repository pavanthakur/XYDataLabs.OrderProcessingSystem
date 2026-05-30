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
