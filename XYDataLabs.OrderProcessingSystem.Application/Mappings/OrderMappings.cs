using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using AppOrderDto = XYDataLabs.OrderProcessingSystem.Application.DTO.OrderDto;
using AppOrderProductDto = XYDataLabs.OrderProcessingSystem.Application.DTO.OrderProductDto;
using AppProductDto = XYDataLabs.OrderProcessingSystem.Application.DTO.ProductDto;

namespace XYDataLabs.OrderProcessingSystem.Application.Mappings;

public static class OrderMappings
{
    public static AppOrderDto ToDto(this Order order) => new()
    {
        OrderId = order.OrderId,
        OrderDate = order.OrderDate,
        CustomerId = order.CustomerId,
        TotalPrice = order.TotalPrice,
        Status = order.Status.ToString(),
        IsFulfilled = order.IsFulfilled,
        OrderProductDtos = order.OrderProducts
            .Select(op => (XYDataLabs.OrderProcessingSystem.Orders.API.OrderProductDto)op.ToDto())
            .ToList()
    };

    public static AppOrderProductDto ToDto(this OrderProduct orderProduct) => new()
    {
        SysId = orderProduct.SysId,
        OrderId = orderProduct.OrderId,
        ProductId = orderProduct.ProductId,
        Quantity = orderProduct.Quantity,
        Price = orderProduct.Price,
        ProductDto = orderProduct.Product?.ToDto()
    };

    public static AppProductDto ToDto(this Product product) => new()
    {
        ProductId = product.ProductId,
        Name = product.Name,
        Description = product.Description,
        Price = product.Price
    };
}

