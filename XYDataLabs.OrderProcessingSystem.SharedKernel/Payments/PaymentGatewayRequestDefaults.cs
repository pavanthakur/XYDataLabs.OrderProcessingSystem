namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

public sealed class PaymentGatewayRequestDefaults
{
    public string RedirectUrl { get; set; } = string.Empty;

    public string DeviceSessionId { get; set; } = string.Empty;
}