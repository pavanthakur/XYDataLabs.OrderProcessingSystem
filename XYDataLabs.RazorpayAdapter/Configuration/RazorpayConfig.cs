namespace XYDataLabs.RazorpayAdapter.Configuration;

public sealed class RazorpayConfig
{
    public string MerchantId { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
    public bool IsProduction { get; set; }
}
