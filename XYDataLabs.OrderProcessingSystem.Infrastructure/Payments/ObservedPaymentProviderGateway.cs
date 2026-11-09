using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;

/// <summary>Safe operation evidence. Never logs customer, card or credential payloads.</summary>
public sealed class ObservedPaymentProviderGateway(IPaymentProviderGateway inner, ILogger<ObservedPaymentProviderGateway> logger)
    : IPaymentProviderGateway
{
    public string ProviderType => inner.ProviderType;
    public bool IsSimulation => inner.IsSimulation;
    public Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCreateCustomerRequest request, CancellationToken cancellationToken = default)
        => inner.CreateCustomerAsync(request, cancellationToken);
    public Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCreateCardTokenRequest request, CancellationToken cancellationToken = default)
        => inner.CreateCardTokenAsync(request, cancellationToken);
    public async Task<PaymentGatewayChargeResult> CreateChargeAsync(PaymentGatewayCreateChargeRequest request, CancellationToken cancellationToken = default)
    {
        var result = await inner.CreateChargeAsync(request, cancellationToken);
        Record("create-charge", result);
        return result;
    }
    public async Task<PaymentGatewayChargeResult> GetChargeAsync(string chargeId, string? customerId = null, CancellationToken cancellationToken = default)
    {
        var result = await inner.GetChargeAsync(chargeId, customerId, cancellationToken);
        Record("fetch-charge", result);
        return result;
    }
    private void Record(string operation, PaymentGatewayChargeResult result) => logger.LogInformation(
        "PaymentProviderEvidence Provider={Provider} Simulation={Simulation} Operation={Operation} ProviderPaymentId={ProviderPaymentId} Amount={Amount} Currency={Currency} Status={Status}",
        ProviderType, IsSimulation, operation, result.Id, result.Amount, result.Currency, result.Status);
}
