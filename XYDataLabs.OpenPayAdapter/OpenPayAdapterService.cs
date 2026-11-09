using XYDataLabs.OpenPayAdapter.Configuration;
using Polly;
using Polly.Registry;
using Serilog;
using Openpay;
using Openpay.Entities;
using Openpay.Entities.Request;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OpenPayAdapter
{
    public class OpenPayAdapterService : IOpenPayAdapterService
    {
        private readonly OpenpayAPI _openpayApi;
        private readonly ILogger _logger;
        private readonly ResiliencePipeline _pipeline;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly PaymentProviderRuntimeConfiguration _configuration;

        public string ProviderType => PaymentProviderTypes.OpenPay;

        public OpenPayAdapterService(
            ITenantPaymentProviderConfigurationResolver paymentProviderConfigurationResolver,
            ILogger logger,
            ResiliencePipelineProvider<string> pipelineProvider,
            IHttpClientFactory httpClientFactory)
        {
            ArgumentNullException.ThrowIfNull(paymentProviderConfigurationResolver);
            ArgumentNullException.ThrowIfNull(logger);
            _logger = logger;
            var configuration = paymentProviderConfigurationResolver.ResolveCurrentTenantConfiguration();
            _configuration=configuration;
            _httpClientFactory=httpClientFactory;
            _openpayApi = new OpenpayAPI(configuration.PrivateKey, configuration.MerchantId, configuration.IsProduction);
            _pipeline = pipelineProvider.GetPipeline("openpay");

            var mode = configuration.IsProduction ? "LIVE" : "TEST";
            _logger.Information("OpenPayAdapterService initialized in {Mode} mode", mode);
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
                // A timeout may occur after the provider accepted the charge.
                // Never automatically repeat this non-idempotent write; reconcile
                // the existing attempt instead of risking a duplicate charge.
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

        // Openpay 1.0.25 drops the currency field when deserializing Charge.
        // Fetch only the public transaction metadata through the authenticated API;
        // never fabricate provider currency from our requested currency.
        public async Task<string?> GetChargeCurrencyAsync(string chargeId, string? customerId = null, CancellationToken cancellationToken = default)
        {
            var host=_configuration.IsProduction ? "https://api.openpay.mx" : "https://sandbox-api.openpay.mx";
            var basePath=$"{host}/v1/{Uri.EscapeDataString(_configuration.MerchantId)}";
            var paths=new List<string>{$"{basePath}/charges/{Uri.EscapeDataString(chargeId)}"};
            if(!string.IsNullOrWhiteSpace(customerId)) paths.Add($"{basePath}/customers/{Uri.EscapeDataString(customerId)}/charges/{Uri.EscapeDataString(chargeId)}");
            using var client=_httpClientFactory.CreateClient("openpay-metadata");
            foreach(var path in paths)
            {
                using var request=new HttpRequestMessage(HttpMethod.Get,path);
                request.Headers.Authorization=new System.Net.Http.Headers.AuthenticationHeaderValue("Basic",Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes($"{_configuration.PrivateKey}:")));
                using var response=await client.SendAsync(request,cancellationToken);
                if(response.StatusCode==System.Net.HttpStatusCode.NotFound && paths.Count>1 && path==paths[0]) continue;
                response.EnsureSuccessStatusCode();
                using var json=System.Text.Json.JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
                return json.RootElement.TryGetProperty("currency",out var currency) ? currency.GetString() : null;
            }
            return null;
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
