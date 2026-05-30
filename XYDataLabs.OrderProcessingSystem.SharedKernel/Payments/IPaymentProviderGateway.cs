namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

public interface IPaymentProviderGateway : IPaymentProviderAdapter
{
    Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCreateCustomerRequest request, CancellationToken cancellationToken = default);

    Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCreateCardTokenRequest request, CancellationToken cancellationToken = default);

    Task<PaymentGatewayChargeResult> CreateChargeAsync(PaymentGatewayCreateChargeRequest request, CancellationToken cancellationToken = default);

    Task<PaymentGatewayChargeResult> GetChargeAsync(string chargeId, string? customerId = null, CancellationToken cancellationToken = default);
}

public sealed record PaymentGatewayCreateCustomerRequest(string Name, string Email);

public sealed record PaymentGatewayCustomer(string Id, string Name, string Email);

public sealed record PaymentGatewayCreateCardTokenRequest(
    string CardNumber,
    string HolderName,
    string ExpirationYear,
    string ExpirationMonth,
    string Cvv2,
    string DeviceSessionId);

public sealed record PaymentGatewayCardToken(string Id, DateTime? CreatedAt);

public sealed record PaymentGatewayCreateChargeRequest(
    string SourceId,
    decimal Amount,
    string Currency,
    string Description,
    string DeviceSessionId,
    string AttemptOrderId,
    bool Use3DSecure,
    string RedirectUrl,
    PaymentGatewayCustomer Customer);

public sealed record PaymentGatewayChargeResult(
    string Id,
    string? Status,
    decimal Amount,
    DateTime? CreatedAt,
    string? Authorization,
    string? ErrorMessage,
    string? RedirectUrl);