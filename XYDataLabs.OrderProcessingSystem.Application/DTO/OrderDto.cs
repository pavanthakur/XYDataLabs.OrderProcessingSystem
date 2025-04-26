namespace XYDataLabs.OrderProcessingSystem.Application.DTO
{
    public class OrderDto
    {
        public int OrderId { get; set; }
        public DateTime OrderDate { get; set; }
        public int CustomerId { get; set; }
        public decimal TotalPrice { get; set; }
        public CustomerDto? CustomerDto { get; set; }
        public bool IsFulfilled { get; set; } // Fulfilled or not
        public List<OrderProductDto>? OrderProductDtos { get; set; }

    }
}
