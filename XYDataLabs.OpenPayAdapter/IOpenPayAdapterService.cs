using Openpay.Entities;
using Openpay.Entities.Request;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OpenPayAdapter
{
    public interface IOpenPayAdapterService : IPaymentProviderAdapter
    {
        Task<Customer> CreateCustomerAsync(Customer customer);
        Task<Card> CreateCardTokenAsync(Card card);
        Task<Charge> CreateChargeAsync(ChargeRequest request);
        Task<Charge> GetChargeAsync(string chargeId, string? customerId = null);
    }
}
