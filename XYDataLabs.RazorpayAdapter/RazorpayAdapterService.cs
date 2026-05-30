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
    private readonly RazorpayClient _client;
    private readonly ILogger _logger;
    private readonly ResiliencePipeline _pipeline;

    public string ProviderType => PaymentProviderTypes.Razorpay;

    public RazorpayAdapterService(
        IOptions<RazorpayConfig> config,
        ILogger logger,
        ResiliencePipelineProvider<string> pipelineProvider)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(pipelineProvider);

        _logger = logger;
        _client = new RazorpayClient(config.Value.MerchantId, config.Value.PrivateKey);
        _pipeline = pipelineProvider.GetPipeline("razorpay");

        var mode = config.Value.IsProduction ? "LIVE" : "TEST";
        var keyHint = config.Value.MerchantId.Length > 12
            ? string.Concat(config.Value.MerchantId.AsSpan(0, 12), "...")
            : config.Value.MerchantId;
        _logger.Information(
            "RazorpayAdapterService initialized in {Mode} mode (key_id prefix: {KeyHint})",
            mode, keyHint);
    }

    public async Task<RazorpayOrderResult> CreateOrderAsync(
        RazorpayCreateOrderRequest request,
        CancellationToken cancellationToken = default)
    {
        // Razorpay amounts are in paise (smallest currency unit) — multiply by 100 for INR
        var amountInPaise = (int)(request.Amount * 100);

        _logger.Information(
            "Creating Razorpay order for amount {Amount} {Currency} receipt {Receipt}",
            request.Amount, request.Currency, request.Receipt);

        try
        {
            var order = await _pipeline.ExecuteAsync<Order>(ct =>
            {
                var attributes = new Dictionary<string, object>
                {
                    ["amount"] = amountInPaise,
                    ["currency"] = request.Currency,
                    ["receipt"] = request.Receipt
                };

                if (!string.IsNullOrWhiteSpace(request.Notes))
                    attributes["notes"] = new Dictionary<string, string> { ["description"] = request.Notes };

                return new ValueTask<Order>(Task.Run(
                    () => _client.Order.Create(attributes), ct));
            }, cancellationToken);

            var orderId = order["id"].ToString()!;
            var status = order["status"]?.ToString() ?? "created";
            var createdAt = DateTimeOffset.FromUnixTimeSeconds(
                order["created_at"] != null ? (long)order["created_at"] : DateTimeOffset.UtcNow.ToUnixTimeSeconds())
                .UtcDateTime;

            _logger.Information("Razorpay order created: {OrderId} status {Status}", orderId, status);

            return new RazorpayOrderResult(orderId, status, request.Amount, request.Currency, createdAt);
        }
        catch (Exception ex)
        {
            _logger.Error(ex,
                "Failed to create Razorpay order for receipt {Receipt}", request.Receipt);
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
}
