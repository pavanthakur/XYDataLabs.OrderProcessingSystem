using Razorpay.Api.Errors;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.RazorpayAdapter;

/// <summary>
/// Implements IPaymentProviderGateway by mapping provider-neutral gateway records
/// to Razorpay Orders API concepts. Card tokenization and customer pre-registration
/// are not required by the Razorpay Orders API checkout flow — those methods return
/// stubs that satisfy the interface contract while signalling they are no-ops.
/// </summary>
public sealed class RazorpayPaymentGateway : IPaymentProviderGateway
{
    private readonly IRazorpayAdapterService _razorpayService;

    public string ProviderType => _razorpayService.ProviderType;

    public RazorpayPaymentGateway(IRazorpayAdapterService razorpayService)
    {
        ArgumentNullException.ThrowIfNull(razorpayService);
        _razorpayService = razorpayService;
    }

    /// <summary>
    /// Razorpay Orders API does not require server-side customer pre-registration.
    /// Returns a stub customer ID derived from the email so downstream code can
    /// store a stable reference without a real provider call.
    /// </summary>
    public Task<PaymentGatewayCustomer> CreateCustomerAsync(
        PaymentGatewayCreateCustomerRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        // No Razorpay API call needed — customer identity is passed directly to Order creation.
        var stubId = $"razorpay-cust-{request.Email.Replace("@", "-at-", StringComparison.OrdinalIgnoreCase)}";
        return Task.FromResult(new PaymentGatewayCustomer(stubId, request.Name, request.Email));
    }

    /// <summary>
    /// Card tokenization is handled client-side by Razorpay.js / Checkout.
    /// The token (payment_id) arrives in the webhook/callback after checkout completion.
    /// This method is a no-op stub — the token ID is not available server-side at this step.
    /// </summary>
    public Task<PaymentGatewayCardToken> CreateCardTokenAsync(
        PaymentGatewayCreateCardTokenRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Not applicable for Razorpay — token (payment_id) comes back via callback after checkout.
        return Task.FromResult(new PaymentGatewayCardToken("razorpay-token-pending", DateTime.UtcNow));
    }

    /// <summary>
    /// Creates a Razorpay Order (server-side step). The returned ChargeResult.Id is the
    /// Razorpay order_id, which the frontend passes to Razorpay Checkout. The status is
    /// "created" until the customer completes payment. RedirectUrl is the payment callback
    /// URL the frontend should return to after Razorpay Checkout completes.
    /// </summary>
    public async Task<PaymentGatewayChargeResult> CreateChargeAsync(
        PaymentGatewayCreateChargeRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        try
        {
            var order = await _razorpayService.CreateOrderAsync(new RazorpayCreateOrderRequest(
                Amount: request.Amount,
                Currency: request.Currency,
                Receipt: request.AttemptOrderId,
                Notes: request.Description), cancellationToken);

            return new PaymentGatewayChargeResult(
                Id: order.OrderId,
                Status: order.Status,
                Amount: order.Amount,
                CreatedAt: order.CreatedAt,
                Authorization: null,
                ErrorMessage: null,
                RedirectUrl: request.RedirectUrl);
        }
        catch (BadRequestError ex)
        {
            // Razorpay BadRequestError (HTTP 400) signals a terminal rejection of the order
            // request — invalid amount, bad currency, or a definitive refusal. This is a
            // customer-action outcome: no retry, no reconciliation.
            throw new PaymentProviderCustomerActionException(
                $"Razorpay rejected order creation: {ex.Message}",
                providerErrorCode: null,
                inner: ex);
        }
    }

    /// <summary>
    /// Fetches a Razorpay Payment by payment_id.
    /// Maps Razorpay payment status to the gateway status contract:
    ///   "captured"  → "completed"
    ///   "failed"    → "failed"
    ///   "created"   → "created" (pending)
    /// </summary>
    public async Task<PaymentGatewayChargeResult> GetChargeAsync(
        string chargeId,
        string? customerId = null,
        CancellationToken cancellationToken = default)
    {
        var payment = await _razorpayService.GetPaymentAsync(chargeId, cancellationToken);

        // Normalize Razorpay statuses to the same vocabulary used by the reconciliation worker
        var normalizedStatus = payment.Status switch
        {
            "captured" => "completed",
            "failed" => "failed",
            "created" => "created",
            "authorized" => "authorized",
            _ => payment.Status
        };

        var errorMessage = payment.ErrorDescription is not null
            ? $"[{payment.ErrorCode}] {payment.ErrorDescription}"
            : null;

        return new PaymentGatewayChargeResult(
            Id: chargeId,
            Status: normalizedStatus,
            Amount: payment.Amount,
            CreatedAt: payment.CreatedAt,
            Authorization: null,
            ErrorMessage: errorMessage,
            RedirectUrl: null);
    }
}
