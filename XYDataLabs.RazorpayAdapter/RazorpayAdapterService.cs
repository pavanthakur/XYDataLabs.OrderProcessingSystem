using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Http;
using Microsoft.Extensions.Options;
using Polly;
using Polly.Registry;
using Razorpay.Api;
using Razorpay.Api.Errors;
using Serilog;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.RazorpayAdapter.Configuration;

namespace XYDataLabs.RazorpayAdapter;

public sealed class RazorpayAdapterService : IRazorpayAdapterService
{
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    private readonly RazorpayClient _client;
    private readonly ILogger _logger;
    private readonly ResiliencePipeline _pipeline;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly string _merchantId;
    private readonly string _privateKey;

    public string ProviderType => PaymentProviderTypes.Razorpay;

    public RazorpayAdapterService(
        ITenantPaymentProviderConfigurationResolver paymentProviderConfigurationResolver,
        ILogger logger,
        ResiliencePipelineProvider<string> pipelineProvider,
        IHttpClientFactory httpClientFactory)
    {
        ArgumentNullException.ThrowIfNull(paymentProviderConfigurationResolver);
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(pipelineProvider);
        ArgumentNullException.ThrowIfNull(httpClientFactory);

        var configuration = paymentProviderConfigurationResolver.ResolveCurrentTenantConfiguration();
        _logger = logger;
        _merchantId = configuration.MerchantId;
        _privateKey = configuration.PrivateKey;
        _client = new RazorpayClient(_merchantId, _privateKey);
        _pipeline = pipelineProvider.GetPipeline("razorpay");
        _httpClientFactory = httpClientFactory;

        var mode = configuration.IsProduction ? "LIVE" : "TEST";
        _logger.Information(
            "RazorpayAdapterService initialized in {Mode} mode for merchant {MerchantId}",
            mode,
            configuration.MerchantId);
    }

    public async Task<RazorpayOrderResult> CreateOrderAsync(
        RazorpayCreateOrderRequest request,
        CancellationToken cancellationToken = default)
    {
        // Razorpay amounts are in paise (smallest currency unit) — multiply by 100 for INR
        var amountInPaise = (int)(request.Amount * 100);

        _logger.Information(
            "Creating Razorpay order with payload: Amount={Amount}, Currency={Currency}, Receipt={Receipt}, Notes={Notes}",
            request.Amount, request.Currency, request.Receipt, request.Notes);

        try
        {
            var order = await _pipeline.ExecuteAsync<Order>(ct =>
            {
                var attributes = new Dictionary<string, object>
                {
                    ["amount"] = amountInPaise,
                    ["currency"] = "INR", // Always use INR for Razorpay
                    ["receipt"] = request.Receipt
                };

                if (!string.IsNullOrWhiteSpace(request.Notes))
                    attributes["notes"] = new Dictionary<string, string> { ["description"] = request.Notes };

                _logger.Information("Sending order creation request to Razorpay: {Attributes}", attributes);

                return new ValueTask<Order>(Task.Run(
                    () => _client.Order.Create(attributes), ct));
            }, cancellationToken);

            var orderId = order["id"].ToString()!;
            var status = order["status"]?.ToString() ?? "created";
            var createdAt = DateTimeOffset.FromUnixTimeSeconds(
                order["created_at"] != null ? (long)order["created_at"] : DateTimeOffset.UtcNow.ToUnixTimeSeconds())
                .UtcDateTime;

            _logger.Information("Razorpay order created successfully: {OrderId}, Status: {Status}, FullResponse: {Order}", orderId, status, order.Attributes);

            return new RazorpayOrderResult(orderId, status, request.Amount, request.Currency, createdAt);
        }
        catch (Exception ex)
        {
            _logger.Error(ex,
                "Failed to create Razorpay order for receipt {Receipt}. Exception: {ExceptionMessage}. Full exception: {ExceptionDetails}",
                request.Receipt, ex.Message, ex.ToString());
            throw;
        }
    }

    public async Task<RazorpayPaymentResult> GetPaymentAsync(
        string paymentId,
        CancellationToken cancellationToken = default)
    {
        _logger.Information("Retrieving Razorpay payment {PaymentId}", paymentId);

        try
        {
            var payment = await Task.Run(() => _client.Payment.Fetch(paymentId), cancellationToken);

            var amountInPaise = payment["amount"] != null ? (int)payment["amount"] : 0;
            var currency = payment["currency"]?.ToString() ?? "INR";
            var status = payment["status"]?.ToString();
            var orderId = payment["order_id"]?.ToString();
            var errorCode = payment["error_code"]?.ToString();
            var errorDesc = payment["error_description"]?.ToString();
            var createdAt = DateTimeOffset.FromUnixTimeSeconds(
                payment["created_at"] != null ? (long)payment["created_at"] : DateTimeOffset.UtcNow.ToUnixTimeSeconds())
                .UtcDateTime;

            _logger.Information(
                "Retrieved Razorpay payment {PaymentId} status {Status}", paymentId, status);

            return new RazorpayPaymentResult(
                paymentId,
                orderId,
                status,
                amountInPaise / 100m,
                currency,
                createdAt,
                errorCode,
                errorDesc);
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Failed to retrieve Razorpay payment {PaymentId}", paymentId);
            throw;
        }
    }

    /// <summary>
    /// Submits card details directly to Razorpay S2S JSON v2 (<c>POST /v1/payments/create/json</c>)
    /// with <c>auth.type = "3ds"</c>. Returns the bank ACS redirect URL in
    /// <c>NextRedirectUrl</c> when the card requires OTP/3DS. When <c>NextRedirectUrl</c> is null
    /// the payment was directly authorized and no redirect is needed.
    /// </summary>
    public async Task<RazorpayS2SPaymentResult> CreateS2SPaymentAsync(
        RazorpayS2SPaymentRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var amountInPaise = (int)(request.Amount * 100);

        _logger.Information(
            "Creating Razorpay S2S payment for order {OrderId}, amount {Amount} {Currency}",
            request.OrderId, request.Amount, request.Currency);

        var payload = JsonSerializer.Serialize(new
        {
            amount = amountInPaise,
            currency = request.Currency,
            order_id = request.OrderId,
            email = request.Email,
            contact = request.Contact,
            method = "card",
            card = new
            {
                name = request.CardName,
                number = request.CardNumber,
                expiry_month = request.CardExpiryMonth,
                expiry_year = request.CardExpiryYear,
                cvv = request.CardCvv
            },
            auth = new { type = "3ds" },
            callback_url = request.CallbackUrl
        });

        var credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_merchantId}:{_privateKey}"));

        using var httpRequest = new HttpRequestMessage(System.Net.Http.HttpMethod.Post, "https://api.razorpay.com/v1/payments/create/json")
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json")
        };
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);

        var httpClient = _httpClientFactory.CreateClient("razorpay-s2s");
        var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        _logger.Information(
            "Razorpay S2S response: Status={StatusCode}, Body={Body}",
            (int)response.StatusCode, responseBody);

        if (!response.IsSuccessStatusCode)
        {
            var errorDesc = TryParseRazorpayErrorDescription(responseBody)
                ?? $"HTTP {(int)response.StatusCode}";

            // Detect the specific "S2S not enabled on account" error.
            // Razorpay returns source:"internal" + "URL not found" when the S2S JSON v2 feature
            // has not been activated on the merchant account. This is a setup issue, not a card decline.
            if (IsS2SNotEnabledError(responseBody))
            {
                _logger.Error(
                    "Razorpay S2S integration is not enabled on merchant account {MerchantId}. " +
                    "Enable it at: Razorpay Dashboard → Settings → API & Integrations → S2S Integration. " +
                    "Raw response: {Body}",
                    _merchantId, responseBody);

                throw new PaymentProviderIntegrationNotEnabledException(
                    "Razorpay S2S card collection is not enabled on this account. " +
                    "Enable it in the Razorpay Dashboard under Settings → API & Integrations → S2S Integration.",
                    providerErrorCode: "S2S_NOT_ENABLED",
                    inner: null);
            }

            throw new PaymentProviderCustomerActionException(
                $"Razorpay S2S payment rejected: {errorDesc}",
                providerErrorCode: null,
                inner: null);
        }

        using var doc = JsonDocument.Parse(responseBody);
        var root = doc.RootElement;

        var paymentId = root.GetProperty("razorpay_payment_id").GetString()
            ?? throw new InvalidOperationException("Razorpay S2S response missing razorpay_payment_id.");

        string? nextRedirectUrl = null;
        if (root.TryGetProperty("next", out var nextArr) && nextArr.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in nextArr.EnumerateArray())
            {
                if (item.TryGetProperty("action", out var actionEl)
                    && string.Equals(actionEl.GetString(), "redirect", StringComparison.OrdinalIgnoreCase)
                    && item.TryGetProperty("url", out var urlEl))
                {
                    nextRedirectUrl = urlEl.GetString();
                    break;
                }
            }
        }

        _logger.Information(
            "Razorpay S2S payment created: PaymentId={PaymentId}, NeedsRedirect={NeedsRedirect}",
            paymentId, nextRedirectUrl is not null);

        return new RazorpayS2SPaymentResult(paymentId, "charge_pending", nextRedirectUrl, null);
    }

    private static string? TryParseRazorpayErrorDescription(string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            if (doc.RootElement.TryGetProperty("error", out var errObj)
                && errObj.TryGetProperty("description", out var desc))
            {
                return desc.GetString();
            }
        }
        catch (JsonException)
        {
            // Malformed response — caller falls back to raw status code
        }

        return null;
    }

    /// <summary>
    /// Returns true when the Razorpay error body indicates the S2S JSON v2 feature is not enabled
    /// on the merchant account. The characteristic pattern is source:"internal" and a description
    /// of "The requested URL was not found on the server." — distinct from card-level declines.
    /// </summary>
    private static bool IsS2SNotEnabledError(string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            if (!doc.RootElement.TryGetProperty("error", out var errObj)) return false;

            var source = errObj.TryGetProperty("source", out var s) ? s.GetString() : null;
            var description = errObj.TryGetProperty("description", out var d) ? d.GetString() : null;

            return string.Equals(source, "internal", StringComparison.OrdinalIgnoreCase)
                && description != null
                && description.Contains("URL", StringComparison.OrdinalIgnoreCase)
                && description.Contains("not found", StringComparison.OrdinalIgnoreCase);
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
