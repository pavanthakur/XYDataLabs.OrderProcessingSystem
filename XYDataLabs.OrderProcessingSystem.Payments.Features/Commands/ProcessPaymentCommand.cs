using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Commands;

public sealed record ProcessPaymentCommand(
    string Name,
    string Email,
    string DeviceSessionId,
    string CardNumber,
    string ExpirationYear,
    string ExpirationMonth,
    string Cvv2,
    string CustomerOrderId,
    Guid? OrderReferenceId,
    string? ClientCallbackOrigin) : ICommand<Result<PaymentDto>>;
