using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.DTO
{
    public class CustomerDto
    {
        public int CustomerId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string? OpenpayCustomerId { get; set; }
        public List<OrderDto> OrderDtos { get; set; } = new List<OrderDto>();
    }
}
