namespace XYDataLabs.OrderProcessingSystem.API.Models;

public sealed class PaymentClientEventRequest
{
    public string? EventName { get; init; }

    public string? Severity { get; init; }

    public string? TenantCode { get; init; }

    public string? ClientFlowId { get; init; }

    public string? CustomerOrderId { get; init; }

    public string? AttemptOrderId { get; init; }

    public string? PaymentId { get; init; }

    public string? PaymentStatus { get; init; }

    public string? StatusCategory { get; init; }

    public int? HttpStatus { get; init; }

    public string? ErrorCode { get; init; }

    public string? ErrorMessage { get; init; }

    public string? PagePath { get; init; }

    public string? ClientTimestampUtc { get; init; }
}