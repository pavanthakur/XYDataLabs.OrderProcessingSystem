namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public enum OrderStatus
    {
        Created = 0,
        Paid = 1,
        Shipped = 2,
        Delivered = 3,
        Cancelled = 4
    }
}