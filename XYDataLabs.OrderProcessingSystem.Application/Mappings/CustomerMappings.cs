using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Mappings;

public static class CustomerMappings
{
    public static CustomerDto ToDto(this Customer customer) => new()
    {
        CustomerId = customer.CustomerId,
        Name = customer.Name,
        Email = customer.Email,
        OrderDtos = customer.Orders
            .Select(o => o.ToCustomerOrderDto())
            .ToList()
    };

    public static Customer ToEntity(this CreateCustomerRequestDto dto) => new()
    {
        Name = dto.Name,
        Email = dto.Email
    };

    public static void ApplyUpdate(this Customer customer, UpdateCustomerRequestDto dto)
    {
        customer.Name = dto.Name;
        customer.Email = dto.Email;
    }

    // Lightweight order projection used inside CustomerDto (no nested products needed)
    private static OrderDto ToCustomerOrderDto(this Order order) => new()
    {
        OrderId = order.OrderId,
        OrderDate = order.OrderDate,
        CustomerId = order.CustomerId,
        TotalPrice = order.TotalPrice,
        IsFulfilled = order.IsFulfilled
    };
}
