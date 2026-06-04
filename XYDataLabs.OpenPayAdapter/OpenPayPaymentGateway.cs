using Openpay;
using Openpay.Entities;
using Openpay.Entities.Request;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OpenPayAdapter;

public sealed class OpenPayPaymentGateway : IPaymentProviderGateway
{
    private readonly IOpenPayAdapterService _openPayAdapterService;

    public OpenPayPaymentGateway(IOpenPayAdapterService openPayAdapterService)
    {
        ArgumentNullException.ThrowIfNull(openPayAdapterService);

        _openPayAdapterService = openPayAdapterService;
    }

    public string ProviderType => _openPayAdapterService.ProviderType;

    public async Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCreateCustomerRequest request, CancellationToken cancellationToken = default)
    {
        var customer = await _openPayAdapterService.CreateCustomerAsync(new Customer
        {
            Name = request.Name,
            Email = request.Email,
            RequiresAccount = false
        });

        return new PaymentGatewayCustomer(customer.Id, customer.Name ?? request.Name, customer.Email ?? request.Email);
    }

    public async Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCreateCardTokenRequest request, CancellationToken cancellationToken = default)
    {
        try
        {
            var card = await _openPayAdapterService.CreateCardTokenAsync(new Card
            {
                CardNumber = request.CardNumber,
                HolderName = request.HolderName,
                ExpirationYear = request.ExpirationYear,
                ExpirationMonth = request.ExpirationMonth,
                Cvv2 = request.Cvv2,
                DeviceSessionId = request.DeviceSessionId
            });

            return new PaymentGatewayCardToken(card.Id, card.CreationDate);
        }
        catch (OpenpayException ex) when (IsCustomerActionError(ex))
        {
            throw new PaymentProviderCustomerActionException(
                $"OpenPay rejected card tokenization: {ex.Message}",
                ex.ErrorCode.ToString(System.Globalization.CultureInfo.InvariantCulture),
                ex);
        }
    }

    public async Task<PaymentGatewayChargeResult> CreateChargeAsync(PaymentGatewayCreateChargeRequest request, CancellationToken cancellationToken = default)
    {
        try
        {
            var charge = await _openPayAdapterService.CreateChargeAsync(new ChargeRequest
            {
                Method = "card",
                SourceId = request.SourceId,
                Amount = request.Amount,
                Currency = request.Currency,
                Description = request.Description,
                DeviceSessionId = request.DeviceSessionId,
                OrderId = request.AttemptOrderId,
                Use3DSecure = request.Use3DSecure,
                RedirectUrl = request.RedirectUrl,
                Customer = new Customer
                {
                    Id = request.Customer.Id,
                    Name = request.Customer.Name,
                    Email = request.Customer.Email,
                    RequiresAccount = false
                }
            });

            return new PaymentGatewayChargeResult(
                charge.Id,
                charge.Status,
                charge.Amount,
                charge.CreationDate,
                charge.Authorization,
                charge.ErrorMessage,
                charge.PaymentMethod?.Url);
        }
        catch (OpenpayException ex) when (IsCustomerActionError(ex))
        {
            throw new PaymentProviderCustomerActionException(
                $"OpenPay declined charge: {ex.Message}",
                ex.ErrorCode.ToString(System.Globalization.CultureInfo.InvariantCulture),
                ex);
        }
    }

    public async Task<PaymentGatewayChargeResult> GetChargeAsync(string chargeId, string? customerId = null, CancellationToken cancellationToken = default)
    {
        var charge = await _openPayAdapterService.GetChargeAsync(chargeId, customerId);

        return new PaymentGatewayChargeResult(
            charge.Id,
            charge.Status,
            charge.Amount,
            charge.CreationDate,
            charge.Authorization,
            charge.ErrorMessage,
            charge.PaymentMethod?.Url);
    }

    /// <summary>
    /// Returns true for OpenPay error codes in the 3000–3999 range (card-level
    /// terminal failures: declined, expired, insufficient funds, fraud, stolen/lost,
    /// bank-restricted, authorization required). These are definitive customer-action
    /// outcomes that must not be retried or sent to reconciliation.
    /// </summary>
    private static bool IsCustomerActionError(OpenpayException ex) =>
        ex.ErrorCode is >= 3000 and <= 3999;
}