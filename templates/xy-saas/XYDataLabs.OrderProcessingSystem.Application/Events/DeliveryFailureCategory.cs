namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public enum DeliveryFailureCategory
{
    Unknown = 0,
    Transient = 1,
    Poison = 2,
    Expired = 3,
    Rejected = 4,
}