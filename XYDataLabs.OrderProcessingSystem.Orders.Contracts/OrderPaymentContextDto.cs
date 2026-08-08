namespace XYDataLabs.OrderProcessingSystem.Orders.Contracts;

public sealed record OrderPaymentContextDto(
    int OrderId,
    string CustomerOrderId,
    Guid OrderReferenceId,
    decimal Amount,
    string CurrencyCode,
    string Status,
    string ConcurrencyToken);
