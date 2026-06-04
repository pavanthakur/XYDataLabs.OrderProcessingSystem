namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public sealed class PaymentTelemetryEvent
{
    public string EventName { get; init; } = string.Empty;

    public string Application { get; init; } = "API";

    public string? TenantCode { get; init; }

    public string? CustomerOrderId { get; init; }

    public string? AttemptOrderId { get; init; }

    public string? PaymentId { get; init; }

    public string? PaymentTraceId { get; init; }

    public string? ProviderType { get; init; }

    public string? PaymentStatus { get; init; }

    public string? StatusCategory { get; init; }

    public string? StatusSource { get; init; }

    public string? ThreeDSecureStage { get; init; }

    public string? ClientFlowId { get; init; }

    public string? PagePath { get; init; }

    public string? ErrorCode { get; init; }

    public string? ErrorMessage { get; init; }

    public string? ClientTimestampUtc { get; init; }

    public string? Severity { get; init; }

    public int? HttpStatus { get; init; }

    public bool? RemoteStatusConfirmed { get; init; }

    public bool? CallbackRecorded { get; init; }

    public bool? IsThreeDSecureEnabled { get; init; }
}