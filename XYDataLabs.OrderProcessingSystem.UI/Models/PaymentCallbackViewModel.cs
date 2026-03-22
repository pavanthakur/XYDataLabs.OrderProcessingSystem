namespace XYDataLabs.OrderProcessingSystem.UI.Models;

public sealed class PaymentCallbackViewModel
{
    public string? PaymentId { get; init; }

    public string Status { get; init; } = "unknown";

    public string? ErrorMessage { get; init; }

    public IReadOnlyDictionary<string, string> Parameters { get; init; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
}