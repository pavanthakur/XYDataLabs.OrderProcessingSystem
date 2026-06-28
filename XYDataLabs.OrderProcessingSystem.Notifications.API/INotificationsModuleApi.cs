namespace XYDataLabs.OrderProcessingSystem.Notifications.API;

public interface INotificationsModuleApi
{
    Task SendOrderConfirmationAsync(string orderId, string customerName);

    Task SendShipmentNotificationAsync(string shipmentId, string recipientName);
}

