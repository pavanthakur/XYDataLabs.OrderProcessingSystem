using XYDataLabs.OpenPayAdapter.Configuration;
using Microsoft.Extensions.Options;
using Polly;
using Polly.Registry;
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
        private readonly ResiliencePipeline _pipeline;

        public OpenPayAdapterService(
            IOptions<OpenPayConfig> config,
            ILogger logger,
            ResiliencePipelineProvider<string> pipelineProvider)
        {
            _logger = logger;
            _openpayApi = new OpenpayAPI(config.Value.PrivateKey, config.Value.MerchantId, config.Value.IsProduction);
            _pipeline = pipelineProvider.GetPipeline("openpay");
        }

        public async Task<Customer> CreateCustomerAsync(Customer customer)
        {
            var maskedEmail = MaskEmail(customer.Email);
            _logger.Information("Creating customer with email: {Email}", maskedEmail);
            try
            {
                var createdCustomer = await _pipeline.ExecuteAsync<Customer>(
                    ct => new ValueTask<Customer>(Task.Run(() => _openpayApi.CustomerService.Create(customer), ct)),
                    CancellationToken.None);
                _logger.Information("Successfully created customer with ID: {CustomerId}", createdCustomer.Id);
                return createdCustomer;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create customer with email: {Email}", maskedEmail);
                throw;
            }
        }
        public async Task<Card> CreateCardTokenAsync(Card card)
        {
            var maskedHolderName = MaskHolder(card.HolderName);
            _logger.Information("Creating card token for holder: {HolderName}", maskedHolderName);
            try
            {
                var createdToken = await _pipeline.ExecuteAsync<Card>(
                    ct => new ValueTask<Card>(Task.Run(() => _openpayApi.CardService.Create(card), ct)),
                    CancellationToken.None);
                _logger.Information("Successfully created card token with ID: {TokenId}", createdToken.Id);
                return createdToken;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create card token for holder: {HolderName}", maskedHolderName);
                throw;
            }
        }

        public async Task<Charge> CreateChargeAsync(ChargeRequest request)
        {
            _logger.Information("Creating charge for amount: {Amount} {Currency}", request.Amount, request.Currency);
            try
            {
                var charge = await _pipeline.ExecuteAsync<Charge>(
                    ct => new ValueTask<Charge>(Task.Run(() => _openpayApi.ChargeService.Create(request), ct)),
                    CancellationToken.None);
                _logger.Information("Successfully created charge with ID: {ChargeId}", charge.Id);
                return charge;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to create charge for amount: {Amount} {Currency}", request.Amount, request.Currency);
                throw;
            }
        }

        public async Task<Charge> GetChargeAsync(string chargeId, string? customerId = null)
        {
            _logger.Information("Retrieving charge {ChargeId} from OpenPay", chargeId);

            try
            {
                var charge = await Task.Run(() => _openpayApi.ChargeService.Get(chargeId));

                _logger.Information("Successfully retrieved charge {ChargeId} with status {Status} using merchant scope", chargeId, charge.Status);
                return charge;
            }
            catch (OpenpayException ex) when (ex.ErrorCode == 1005 && !string.IsNullOrWhiteSpace(customerId))
            {
                _logger.Warning(
                    ex,
                    "Merchant-scope charge lookup returned 1005 for charge {ChargeId}. Retrying with customer scope for customer {CustomerId}",
                    chargeId,
                    customerId);

                var fallbackCharge = await Task.Run(() => _openpayApi.ChargeService.Get(customerId, chargeId));
                _logger.Information(
                    "Successfully retrieved charge {ChargeId} with status {Status} using customer scope fallback",
                    chargeId,
                    fallbackCharge.Status);
                return fallbackCharge;
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "Failed to retrieve charge {ChargeId} from OpenPay", chargeId);
                throw;
            }
        }

        private static string MaskEmail(string? email)
        {
            if (string.IsNullOrWhiteSpace(email))
            {
                return "[empty]";
            }

            var atIndex = email.IndexOf('@');
            if (atIndex <= 1)
            {
                return "***@***";
            }

            return $"{email[0]}***{email[atIndex..]}";
        }

        private static string MaskHolder(string? name)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                return "[empty]";
            }

            return $"{name[0]}{new string('*', Math.Max(name.Length - 1, 2))}";
        }
    }
}