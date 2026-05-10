namespace XYDataLabs.OrderProcessingSystem.PaymentGateway.Configuration;

public sealed class PaymentGatewayOptions
{
    public string ProviderName { get; set; } = "DefaultGateway";
    public string AccountId { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
    public string DeviceSessionId { get; set; } = string.Empty;
    public string RedirectUrl { get; set; } = string.Empty;
    public bool IsProduction { get; set; }
}