using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Commands;

public sealed record ConfirmPaymentStatusCommand(
    string PaymentId,
    string? AttemptOrderId,
    string? CallbackStatus,
    string? ErrorMessage,
    IReadOnlyDictionary<string, string>? CallbackParameters)
    : ICommand<Result<PaymentStatusDetailsDto>>;
