namespace XYDataLabs.OrderProcessingSystem.Application.DTO;

public sealed class PaymentStatusLookupRequestDto
{
    public string? AttemptOrderId { get; set; }

    public string? CallbackStatus { get; set; }

    public string? ErrorMessage { get; set; }

    public IReadOnlyDictionary<string, string>? CallbackParameters { get; set; }
}