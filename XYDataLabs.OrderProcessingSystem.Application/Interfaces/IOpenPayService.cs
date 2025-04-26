using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Interfaces
{
    public interface IOpenPayService
    {
        Task<PaymentDto> ProcessPaymentAsync(CustomerWithCardPaymentRequestDto paymentRequestDto);
    }
}
