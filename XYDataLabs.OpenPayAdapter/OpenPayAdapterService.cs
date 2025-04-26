using XYDataLabs.OpenPayAdapter.Configuration;
using Microsoft.Extensions.Options;
using Serilog;
using Openpay;
using Openpay.Entities;
using Openpay.Entities.Request;

namespace XYDataLabs.OpenPayAdapter
{
    public class OpenPayAdapterService : IOpenPayAdapterService
    {
        private readonly OpenpayAPI _openpayApi;
        private readonly ILogger _logger;
        public OpenPayAdapterService(
            IOptions<OpenPayConfig> config,
            ILogger logger)
        {
            _logger = logger;
            _openpayApi = new OpenpayAPI(config.Value.MerchantId, config.Value.PrivateKey, config.Value.IsProduction);
        }

        public async Task<Customer> CreateCustomerAsync(Customer customer)
        {
            _logger.Information("Creating customer with email: {Email}", customer.Email);
            try
            {
                var createdCustomer = await Task.Run(() => _openpayApi.CustomerService.Create(customer));
                _logger.Information("Successfully created customer with ID: {CustomerId}", createdCustomer.Id);
                return createdCustomer;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create customer with email: {Email}", customer.Email);
                throw;
            }
        }
        public async Task<Card> CreateCardTokenAsync(Card card)
        {
            _logger.Information("Creating card token for holder: {HolderName}", card.HolderName);
            try
            {
                var createdToken = await Task.Run(() => _openpayApi.CardService.Create(card));
                _logger.Information("Successfully created card token with ID: {TokenId}", createdToken.Id);
                return createdToken;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create card token for holder: {HolderName}", card.HolderName);
                throw;
            }
        }

        public async Task<Charge> CreateChargeAsync(ChargeRequest request)
        {
            _logger.Information("Creating charge for amount: {Amount} {Currency}", request.Amount, request.Currency);
            try
            {
                var charge = await Task.Run(() => _openpayApi.ChargeService.Create(request));
                _logger.Information("Successfully created charge with ID: {ChargeId}", charge.Id);
                return charge;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create charge for amount: {Amount} {Currency}", request.Amount, request.Currency);
                throw;
            }
        }
    }
}