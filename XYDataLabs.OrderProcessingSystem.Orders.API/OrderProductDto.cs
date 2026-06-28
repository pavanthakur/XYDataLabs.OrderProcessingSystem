namespace XYDataLabs.OrderProcessingSystem.Orders.API;

public class OrderProductDto
{
    public int SysId { get; set; }
    public int OrderId { get; set; }
    public int ProductId { get; set; }
    public int Quantity { get; set; }
    public decimal Price { get; set; }
    public OrderDto? OrderDto { get; set; }
    public ProductDto? ProductDto { get; set; }
}

