using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Mappings;

public static class PaymentMappings
{
    public static BillingCustomer ToBillingCustomer(this CustomerWithCardPaymentRequestDto dto) => new()
    {
        Name = dto.Name,
        Email = dto.Email
    };
}
