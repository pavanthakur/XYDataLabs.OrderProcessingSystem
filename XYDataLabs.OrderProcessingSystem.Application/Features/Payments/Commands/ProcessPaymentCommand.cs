using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

public sealed record ProcessPaymentCommand(
    string Name,
    string Email,
    string DeviceSessionId,
    string CardNumber,
    string ExpirationYear,
    string ExpirationMonth,
    string Cvv2,
    string CustomerOrderId) : ICommand<Result<PaymentDto>>;
