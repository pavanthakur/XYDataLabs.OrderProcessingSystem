using Openpay.Entities;
using Openpay.Entities.Request;

namespace XYDataLabs.OpenPayAdapter
{
    public interface IOpenPayAdapterService
    {
        Task<Customer> CreateCustomerAsync(Customer customer);
        Task<Card> CreateCardTokenAsync(Card card);
        Task<Charge> CreateChargeAsync(ChargeRequest request);
    }
}
