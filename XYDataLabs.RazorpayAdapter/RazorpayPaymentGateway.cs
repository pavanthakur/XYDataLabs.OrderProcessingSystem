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
    /// Creates a Razorpay payment.
    /// <list type="bullet">
    ///   <item><description>
    ///     <c>Use3DSecure = false</c> (or no card details): Creates a Razorpay Order only.
    ///     The returned <c>ChargeResult.Id</c> is the <c>order_id</c>; the frontend passes it
    ///     to Razorpay Checkout JS which handles 3DS internally inside its own popup.
    ///   </description></item>
    ///   <item><description>
    ///     <c>Use3DSecure = true</c>: Creates a Razorpay Order then immediately submits card
    ///     details via the S2S JSON v2 API (<c>POST /v1/payments/create/json</c>) with
    ///     <c>auth.type = "3ds"</c>. Returns <c>charge_pending</c> status and the bank ACS
    ///     redirect URL so the user completes OTP/3DS inline in our UI, matching OpenPay behaviour.
    ///   </description></item>
    /// </list>
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

            // --- Razorpay Checkout JS path (Use3DSecure = false) ---
            // Return the order_id so the frontend can open the Razorpay Checkout popup.
            // 3DS is handled internally by Razorpay in this flow; no card details needed server-side.
            if (!request.Use3DSecure || request.CardDetails is null)
            {
                return new PaymentGatewayChargeResult(
                    Id: order.OrderId,
                    Status: order.Status,
                    Amount: order.Amount,
                    CreatedAt: order.CreatedAt,
                    Authorization: null,
                    ErrorMessage: null,
                    RedirectUrl: request.RedirectUrl);
            }

            // --- Razorpay S2S JSON v2 path (Use3DSecure = true) ---
            // Submit card details + auth.type:"3ds" directly to Razorpay.
            // Razorpay responds with the bank ACS URL for OTP which the frontend redirects to,
            // matching the OpenPay charge_pending + threeDSecureUrl redirect pattern.
            var s2s = await _razorpayService.CreateS2SPaymentAsync(new RazorpayS2SPaymentRequest(
                OrderId: order.OrderId,
                Amount: request.Amount,
                Currency: request.Currency,
                Email: request.Customer.Email,
                // TODO: Add a phone field to the payment form and pass it here.
                // Razorpay requires contact for S2S; using a placeholder for now.
                Contact: "9999999999",
                CardNumber: request.CardDetails.CardNumber,
                CardName: request.CardDetails.HolderName,
                CardExpiryMonth: request.CardDetails.ExpirationMonth,
                CardExpiryYear: request.CardDetails.ExpirationYear,
                CardCvv: request.CardDetails.Cvv2,
                CallbackUrl: request.RedirectUrl), cancellationToken);

            // When NextRedirectUrl is set → bank requires OTP → return charge_pending + redirect URL.
            // When null → card was directly authorized (rare in test mode but handled for robustness).
            var status = s2s.NextRedirectUrl is not null ? "charge_pending" : "completed";

            return new PaymentGatewayChargeResult(
                Id: s2s.PaymentId,
                Status: status,
                Amount: request.Amount,
                CreatedAt: DateTime.UtcNow,
                Authorization: null,
                ErrorMessage: s2s.ErrorMessage,
                RedirectUrl: s2s.NextRedirectUrl);
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
        if (!IsValidRazorpayPaymentId(chargeId))
        {
            throw new ArgumentException(
                $"Invalid Razorpay payment ID format. Expected 'pay_' but got '{chargeId}'.",
                nameof(chargeId));
        }

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

    private static bool IsValidRazorpayPaymentId(string? paymentId)
    {
        return !string.IsNullOrWhiteSpace(paymentId)
            && paymentId.StartsWith("pay_", StringComparison.OrdinalIgnoreCase);
    }
}
