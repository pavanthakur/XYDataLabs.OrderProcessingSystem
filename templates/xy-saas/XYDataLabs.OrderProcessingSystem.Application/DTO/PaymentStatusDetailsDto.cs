namespace XYDataLabs.OrderProcessingSystem.Application.DTO;

public sealed class PaymentStatusDetailsDto
{
    public string PaymentId { get; set; } = string.Empty;

    public string? CustomerOrderId { get; set; }

    public string Status { get; set; } = "unknown";

    public string StatusCategory { get; set; } = "info";

    public string StatusMessage { get; set; } = string.Empty;

    public bool IsSuccess { get; set; }

    public bool IsPending { get; set; }

    public bool IsFailure { get; set; }

    public bool IsFinal { get; set; }

    public bool CallbackRecorded { get; set; }

    public bool RemoteStatusConfirmed { get; set; }

    public string StatusSource { get; set; } = "database";

    public string? ErrorMessage { get; set; }

    public string? TransactionReferenceId { get; set; }

    public DateTime? TransactionDate { get; set; }

    public string? ThreeDSecureUrl { get; set; }

    public bool IsThreeDSecureEnabled { get; set; }

    public string? ThreeDSecureStage { get; set; }
}