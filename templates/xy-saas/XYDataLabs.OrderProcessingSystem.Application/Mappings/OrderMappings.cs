using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Mappings;

public static class OrderMappings
{
    public static OrderDto ToDto(this Order order) => new()
    {
        OrderId = order.OrderId,
        OrderDate = order.OrderDate,
        CustomerId = order.CustomerId,
        TotalPrice = order.TotalPrice,
        Status = order.Status.ToString(),
        IsFulfilled = order.IsFulfilled,
        OrderProductDtos = order.OrderProducts
            .Select(op => op.ToDto())
            .ToList()
    };

    public static OrderProductDto ToDto(this OrderProduct orderProduct) => new()
    {
        SysId = orderProduct.SysId,
        OrderId = orderProduct.OrderId,
        ProductId = orderProduct.ProductId,
        Quantity = orderProduct.Quantity,
        Price = orderProduct.Price,
        ProductDto = orderProduct.Product?.ToDto()
    };

    public static ProductDto ToDto(this Product product) => new()
    {
        ProductId = product.ProductId,
        Name = product.Name,
        Description = product.Description,
        Price = product.Price
    };
}
