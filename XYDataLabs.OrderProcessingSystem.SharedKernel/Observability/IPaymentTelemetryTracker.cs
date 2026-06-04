namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public interface IPaymentTelemetryTracker
{
    void Track(PaymentTelemetryEvent telemetryEvent);
}