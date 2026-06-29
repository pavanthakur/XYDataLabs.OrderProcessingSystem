namespace XYDataLabs.OrderProcessingSystem.Orders.API;

public class ProductDto
{
    public int ProductId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public decimal Price { get; set; }
    public List<OrderProductDto>? OrderProductDtos { get; set; }
}

