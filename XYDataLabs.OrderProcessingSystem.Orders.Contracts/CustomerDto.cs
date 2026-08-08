namespace XYDataLabs.OrderProcessingSystem.Orders.Contracts;

public class CustomerDto
{
    public int CustomerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public List<OrderDto> OrderDtos { get; set; } = new();
}
