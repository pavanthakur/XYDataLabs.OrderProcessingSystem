namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public sealed class NullPaymentTelemetryTracker : IPaymentTelemetryTracker
{
    public static readonly NullPaymentTelemetryTracker Instance = new();

    private NullPaymentTelemetryTracker()
    {
    }

    public void Track(PaymentTelemetryEvent telemetryEvent)
    {
        ArgumentNullException.ThrowIfNull(telemetryEvent);
    }
}