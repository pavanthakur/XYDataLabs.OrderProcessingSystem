namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public static class PaymentTelemetryCorrelation
{
    public static string? ResolveRunPrefix(string? customerOrderId)
    {
        if (string.IsNullOrWhiteSpace(customerOrderId))
        {
            return null;
        }

        var segments = customerOrderId.Trim().Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length < 3)
        {
            return null;
        }

        return string.Equals(segments[0], "OR", StringComparison.OrdinalIgnoreCase)
            ? string.Join('-', segments[..3])
            : null;
    }
}