using XYDataLabs.OrderProcessingSystem.Notifications.API;

namespace XYDataLabs.OrderProcessingSystem.Application.API.Services
{
    public sealed class NotificationsService : INotificationsModuleApi
    {
        public Task SendOrderConfirmationAsync(string orderId, string customerName)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(orderId);
            ArgumentException.ThrowIfNullOrWhiteSpace(customerName);
            return Task.CompletedTask;
        }

        public Task SendShipmentNotificationAsync(string shipmentId, string recipientName)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(shipmentId);
            ArgumentException.ThrowIfNullOrWhiteSpace(recipientName);
            return Task.CompletedTask;
        }
    }
}

