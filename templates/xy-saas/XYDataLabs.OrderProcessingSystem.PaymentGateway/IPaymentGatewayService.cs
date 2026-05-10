namespace XYDataLabs.OrderProcessingSystem.PaymentGateway;

public interface IPaymentGatewayService
{
    Task<PaymentGatewayCustomer> CreateCustomerAsync(PaymentGatewayCustomer customer);
    Task<PaymentGatewayCardToken> CreateCardTokenAsync(PaymentGatewayCardTokenRequest card);
    Task<PaymentGatewayCharge> CreateChargeAsync(PaymentGatewayChargeRequest request);
    Task<PaymentGatewayCharge> GetChargeAsync(string chargeId, string? customerId = null);
}