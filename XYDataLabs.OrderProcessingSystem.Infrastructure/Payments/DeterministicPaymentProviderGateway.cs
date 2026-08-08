using System.Collections.Concurrent;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;

public sealed class DeterministicPaymentProviderGateway(string providerType)
    : IPaymentProviderGateway
{
    private readonly ConcurrentDictionary<string, PaymentGatewayChargeResult> _charges =
        new(StringComparer.Ordinal);

    public string ProviderType { get; } = providerType;

    public Task<PaymentGatewayCustomer> CreateCustomerAsync(
        PaymentGatewayCreateCustomerRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new PaymentGatewayCustomer(
            $"det-customer-{CreateStableSuffix(request.Email)}",
            request.Name,
            request.Email));
    }

    public Task<PaymentGatewayCardToken> CreateCardTokenAsync(
        PaymentGatewayCreateCardTokenRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new PaymentGatewayCardToken(
            $"det-card-{CreateStableSuffix(request.CardNumber)}",
            DateTime.UtcNow));
    }

    public Task<PaymentGatewayChargeResult> CreateChargeAsync(
        PaymentGatewayCreateChargeRequest request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var cardNumber = request.CardDetails?.CardNumber ?? string.Empty;
        if (cardNumber.EndsWith("0002", StringComparison.Ordinal))
        {
            throw new PaymentProviderCustomerActionException(
                "Deterministic provider decline.",
                "deterministic_decline");
        }

        if (cardNumber.EndsWith("9995", StringComparison.Ordinal))
        {
            throw new TimeoutException("Deterministic provider timeout.");
        }

        var chargeId = $"DET-{ProviderType.ToUpperInvariant()}-{CreateStableSuffix(request.AttemptOrderId)}";
        var result = new PaymentGatewayChargeResult(
            chargeId,
            "completed",
            request.Amount,
            DateTime.UtcNow,
            $"det-auth-{CreateStableSuffix(request.AttemptOrderId)}",
            null,
            null);
        _charges[chargeId] = result;
        return Task.FromResult(result);
    }

    public Task<PaymentGatewayChargeResult> GetChargeAsync(
        string chargeId,
        string? customerId = null,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _charges.TryGetValue(chargeId, out var result)
            ? Task.FromResult(result)
            : throw new KeyNotFoundException(
                $"Deterministic charge '{chargeId}' was not found.");
    }

    private static string CreateStableSuffix(string value)
    {
        var hash = System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash.AsSpan(0, 8));
    }
}
