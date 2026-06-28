namespace XYDataLabs.OrderProcessingSystem.Orders.API;

public class OrderDto
{
    public int OrderId { get; set; }
    public DateTime OrderDate { get; set; }
    public int CustomerId { get; set; }
    public decimal TotalPrice { get; set; }
    public string Status { get; set; } = string.Empty;
    public CustomerDto? CustomerDto { get; set; }
    public bool IsFulfilled { get; set; }
    public List<OrderProductDto>? OrderProductDtos { get; set; }
}

