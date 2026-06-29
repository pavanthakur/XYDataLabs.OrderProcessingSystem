using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using AppCustomerDto = XYDataLabs.OrderProcessingSystem.Application.DTO.CustomerDto;
using AppOrderDto = XYDataLabs.OrderProcessingSystem.Application.DTO.OrderDto;

namespace XYDataLabs.OrderProcessingSystem.Application.Mappings;

public static class CustomerMappings
{
    public static AppCustomerDto ToDto(this Customer customer) => new()
    {
        CustomerId = customer.CustomerId,
        Name = customer.Name,
        Email = customer.Email,
        OrderDtos = (customer.Orders ?? Enumerable.Empty<Order>())
            .Select(o => (XYDataLabs.OrderProcessingSystem.Orders.API.OrderDto)o.ToCustomerOrderDto())
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
    private static AppOrderDto ToCustomerOrderDto(this Order order) => new()
    {
        OrderId = order.OrderId,
        OrderDate = order.OrderDate,
        CustomerId = order.CustomerId,
        TotalPrice = order.TotalPrice,
        Status = order.Status.ToString(),
        IsFulfilled = order.IsFulfilled
    };
}

