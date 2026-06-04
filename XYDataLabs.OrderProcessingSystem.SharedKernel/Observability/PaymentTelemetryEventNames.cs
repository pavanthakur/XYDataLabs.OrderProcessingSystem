namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public static class PaymentTelemetryEventNames
{
    public const string AttemptCreated = "payment_validation_attempt_created";
    public const string ChargeCreated = "payment_validation_charge_created";
    public const string CallbackReconciled = "payment_validation_callback_reconciled";
}