namespace XYDataLabs.OrderProcessingSystem.PaymentGateway;

public sealed class PaymentGatewayCustomer
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public bool RequiresAccount { get; set; }
}

public sealed class PaymentGatewayCardTokenRequest
{
    public string CardNumber { get; set; } = string.Empty;
    public string HolderName { get; set; } = string.Empty;
    public string ExpirationYear { get; set; } = string.Empty;
    public string ExpirationMonth { get; set; } = string.Empty;
    public string Cvv2 { get; set; } = string.Empty;
    public string DeviceSessionId { get; set; } = string.Empty;
}

public sealed class PaymentGatewayCardToken
{
    public string Id { get; set; } = string.Empty;
    public DateTime? CreationDate { get; set; }
}

public sealed class PaymentGatewayChargeRequest
{
    public string Method { get; set; } = string.Empty;
    public string SourceId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string DeviceSessionId { get; set; } = string.Empty;
    public string OrderId { get; set; } = string.Empty;
    public bool UseThreeDSecure { get; set; }
    public string RedirectUrl { get; set; } = string.Empty;
    public PaymentGatewayCustomer Customer { get; set; } = new();
}

public sealed class PaymentGatewayPaymentMethod
{
    public string? Url { get; set; }
}

public sealed class PaymentGatewayCharge
{
    public string Id { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public DateTime? CreationDate { get; set; }
    public string? Authorization { get; set; }
    public string? ErrorMessage { get; set; }
    public PaymentGatewayPaymentMethod? PaymentMethod { get; set; }
}